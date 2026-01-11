#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <time.h>
#include <sys/time.h>
#include <sys/sysctl.h>
#include <sys/statvfs.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/mach_host.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

#include "include/pcstats.h"

// Forward declarations for private HID APIs (not in public headers)
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;

// ============================================================================
// SMC (System Management Controller) Interface for Apple Silicon
// Based on macmon implementation (https://github.com/vladkens/macmon)
// ============================================================================

// SMC data structures (must match Apple's internal format exactly)
typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCKeyDataVers;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpu_p_limit;
    uint32_t gpu_p_limit;
    uint32_t mem_p_limit;
} SMCKeyDataPLimitData;

typedef struct {
    uint32_t data_size;
    uint32_t data_type;
    uint8_t data_attributes;
} SMCKeyDataKeyInfo;

typedef struct {
    uint32_t key;
    SMCKeyDataVers vers;
    SMCKeyDataPLimitData p_limit_data;
    SMCKeyDataKeyInfo key_info;
    uint8_t result;
    uint8_t status;
    uint8_t data8;      // Command goes here (5=read, 9=keyinfo)
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

static io_connect_t smc_conn = 0;

// Convert 4-char string to big-endian uint32
static uint32_t str_to_fourcc(const char *s) {
    return ((uint32_t)(unsigned char)s[0] << 24) |
           ((uint32_t)(unsigned char)s[1] << 16) |
           ((uint32_t)(unsigned char)s[2] << 8) |
           (uint32_t)(unsigned char)s[3];
}

// Open SMC connection - iterates through AppleSMC to find AppleSMCKeysEndpoint
static int smc_open(void) {
    if (smc_conn) return 0;

    io_iterator_t iter;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("AppleSMC"), &iter);
    if (kr != KERN_SUCCESS) return -1;

    io_object_t device;
    while ((device = IOIteratorNext(iter)) != 0) {
        char name[128] = {0};
        IORegistryEntryGetName(device, name);

        if (strcmp(name, "AppleSMCKeysEndpoint") == 0) {
            kr = IOServiceOpen(device, mach_task_self(), 0, &smc_conn);
            IOObjectRelease(device);
            if (kr == KERN_SUCCESS) {
                IOObjectRelease(iter);
                return 0;
            }
        }
        IOObjectRelease(device);
    }
    IOObjectRelease(iter);
    return -1;
}

// SMC read operation using selector 2
static int smc_read(SMCKeyData *input, SMCKeyData *output) {
    if (!smc_conn) return -1;

    size_t outsize = sizeof(SMCKeyData);
    kern_return_t kr = IOConnectCallStructMethod(smc_conn, 2,
        input, sizeof(SMCKeyData), output, &outsize);

    if (kr != KERN_SUCCESS) return -1;
    if (output->result == 132) return -1;  // Key not found
    if (output->result != 0) return -1;

    return 0;
}

// Read SMC key info
static int smc_read_key_info(const char *key, SMCKeyDataKeyInfo *info) {
    SMCKeyData input = {0};
    SMCKeyData output = {0};

    input.key = str_to_fourcc(key);
    input.data8 = 9;  // Command: read key info

    if (smc_read(&input, &output) != 0) return -1;

    *info = output.key_info;
    return 0;
}


// Pre-computed fourcc constants for type checking (avoids runtime computation)
#define FOURCC_FLT  0x666c7420  // "flt "
#define FOURCC_SP78 0x73703738  // "sp78"
#define FOURCC_IOFT 0x696f6674  // "ioft"

// Convert SMC value to float (handles flt, sp78, etc.)
static float smc_bytes_to_float(uint8_t *data, uint32_t size, uint32_t type) {
    if (size == 0) return 0.0f;

    // flt - 32-bit float
    if (type == FOURCC_FLT && size >= 4) {
        float f;
        memcpy(&f, data, 4);
        return f;
    }

    // sp78 - signed fixed point 7.8
    if (type == FOURCC_SP78 && size >= 2) {
        int16_t raw = ((int16_t)data[0] << 8) | data[1];
        return raw / 256.0f;
    }

    // ioft - double
    if (type == FOURCC_IOFT && size >= 8) {
        double d;
        memcpy(&d, data, 8);
        return (float)d;
    }

    // ui8 - unsigned 8-bit
    if (size == 1) {
        return (float)data[0];
    }

    // ui16 - unsigned 16-bit
    if (size == 2) {
        return (float)(((uint16_t)data[0] << 8) | data[1]);
    }

    return 0.0f;
}

// ============================================================================
// SMC Key Cache - probes keys once at startup, caches key_info
// ============================================================================

#define MAX_CACHED_KEYS 32

typedef struct {
    uint32_t key_fourcc;           // Pre-computed fourcc
    SMCKeyDataKeyInfo key_info;    // Cached key info
} CachedSMCKey;

static CachedSMCKey cached_cpu_keys[MAX_CACHED_KEYS];
static CachedSMCKey cached_gpu_keys[MAX_CACHED_KEYS];
static CachedSMCKey cached_board_keys[MAX_CACHED_KEYS];
static int num_cached_cpu_keys = 0;
static int num_cached_gpu_keys = 0;
static int num_cached_board_keys = 0;
static int smc_cache_initialized = 0;

// Read a single SMC float value by key string (for non-cached reads like fans)
static float smc_read_key(const char *key) {
    SMCKeyDataKeyInfo info;
    if (smc_read_key_info(key, &info) != 0) return 0.0f;
    if (info.data_size > 32) return 0.0f;

    SMCKeyData input = {0};
    SMCKeyData output = {0};

    input.key = str_to_fourcc(key);
    input.data8 = 5;  // Command: read bytes
    input.key_info = info;

    if (smc_read(&input, &output) != 0) return 0.0f;

    return smc_bytes_to_float(output.bytes, info.data_size, info.data_type);
}

// Read temperature using cached key_info (skips key_info lookup - 1 IOKit call instead of 2)
static float smc_read_temp_cached(uint32_t key_fourcc, SMCKeyDataKeyInfo *info) {
    SMCKeyData input = {0};
    SMCKeyData output = {0};

    input.key = key_fourcc;
    input.data8 = 5;  // Command: read bytes
    input.key_info = *info;

    if (smc_read(&input, &output) != 0) return 0.0f;

    return smc_bytes_to_float(output.bytes, info->data_size, info->data_type);
}

// Initialize SMC key cache - probe all possible keys once, remember valid ones
static void smc_init_cache(void) {
    if (smc_cache_initialized) return;
    if (smc_open() != 0) return;

    // All possible temperature keys to probe
    const char *cpu_keys[] = {
        "Tp01", "Tp02", "Tp03", "Tp04", "Tp05", "Tp06", "Tp07", "Tp08",
        "Tp09", "Tp0A", "Tp0B", "Tp0C", "Tp0D", "Tp0E", "Tp0F", "Tp0G",
        "Te01", "Te02", "Te03", "Te04", "Te05", "Te06", "Te07", "Te08",
        "Tc0c", "Tc1c", "Tc2c", "Tc3c",
        NULL
    };

    const char *gpu_keys[] = {
        "Tg0f", "Tg0j", "Tg0D", "Tg0d", "Tg05", "Tg0P", "Tg0p",
        NULL
    };

    // Motherboard/PCH/system temperature keys
    const char *board_keys[] = {
        "Tm0P", "Tm1P", "Tm2P",  // PCH (Platform Controller Hub)
        "Ts0P", "Ts1P", "Ts2P",  // System/case sensors
        "TM0P", "TM1P",          // Alternate PCH
        "Tw0P",                   // Wireless module (often on board)
        NULL
    };

    // Probe CPU keys
    for (int i = 0; cpu_keys[i] && num_cached_cpu_keys < MAX_CACHED_KEYS; i++) {
        SMCKeyDataKeyInfo info;
        if (smc_read_key_info(cpu_keys[i], &info) == 0 && info.data_size > 0) {
            cached_cpu_keys[num_cached_cpu_keys].key_fourcc = str_to_fourcc(cpu_keys[i]);
            cached_cpu_keys[num_cached_cpu_keys].key_info = info;
            num_cached_cpu_keys++;
        }
    }

    // Probe GPU keys
    for (int i = 0; gpu_keys[i] && num_cached_gpu_keys < MAX_CACHED_KEYS; i++) {
        SMCKeyDataKeyInfo info;
        if (smc_read_key_info(gpu_keys[i], &info) == 0 && info.data_size > 0) {
            cached_gpu_keys[num_cached_gpu_keys].key_fourcc = str_to_fourcc(gpu_keys[i]);
            cached_gpu_keys[num_cached_gpu_keys].key_info = info;
            num_cached_gpu_keys++;
        }
    }

    // Probe motherboard/system keys
    for (int i = 0; board_keys[i] && num_cached_board_keys < MAX_CACHED_KEYS; i++) {
        SMCKeyDataKeyInfo info;
        if (smc_read_key_info(board_keys[i], &info) == 0 && info.data_size > 0) {
            cached_board_keys[num_cached_board_keys].key_fourcc = str_to_fourcc(board_keys[i]);
            cached_board_keys[num_cached_board_keys].key_info = info;
            num_cached_board_keys++;
        }
    }

    smc_cache_initialized = 1;
}

// Get temperatures from SMC using cached keys (optimized)
static void smc_get_temperatures(float *cpu_temp, float *gpu_temp) {
    *cpu_temp = 0.0f;
    *gpu_temp = 0.0f;

    // Initialize cache on first call
    if (!smc_cache_initialized) {
        smc_init_cache();
    }

    if (!smc_conn) return;

    float cpu_sum = 0, gpu_sum = 0;
    int cpu_count = 0, gpu_count = 0;

    // Read only cached (valid) CPU keys - 1 IOKit call each
    for (int i = 0; i < num_cached_cpu_keys; i++) {
        float t = smc_read_temp_cached(cached_cpu_keys[i].key_fourcc,
                                        &cached_cpu_keys[i].key_info);
        if (t > 10 && t < 130) {
            cpu_sum += t;
            cpu_count++;
        }
    }

    // Read only cached (valid) GPU keys - 1 IOKit call each
    for (int i = 0; i < num_cached_gpu_keys; i++) {
        float t = smc_read_temp_cached(cached_gpu_keys[i].key_fourcc,
                                        &cached_gpu_keys[i].key_info);
        if (t > 10 && t < 130) {
            gpu_sum += t;
            gpu_count++;
        }
    }

    if (cpu_count > 0) *cpu_temp = cpu_sum / cpu_count;
    if (gpu_count > 0) *gpu_temp = gpu_sum / gpu_count;
}

// Get motherboard/system temperature from SMC
static float smc_get_board_temperature(void) {
    // Initialize cache on first call
    if (!smc_cache_initialized) {
        smc_init_cache();
    }

    if (!smc_conn || num_cached_board_keys == 0) return 0.0f;

    float board_sum = 0;
    int board_count = 0;

    for (int i = 0; i < num_cached_board_keys; i++) {
        float t = smc_read_temp_cached(cached_board_keys[i].key_fourcc,
                                        &cached_board_keys[i].key_info);
        if (t > 10 && t < 100) {  // Board temps typically lower than CPU/GPU
            board_sum += t;
            board_count++;
        }
    }

    return (board_count > 0) ? board_sum / board_count : 0.0f;
}

// Get fan RPM info from SMC
void get_fan_info(FanInfo *fans) {
    fans->count = 0;
    for (int i = 0; i < MAX_FANS; i++) {
        fans->rpm[i] = 0;
        fans->min_rpm[i] = 0;
        fans->max_rpm[i] = 0;
    }

    if (smc_open() != 0) return;

    // Fan keys: F0Ac (actual), F0Mn (min), F0Mx (max)
    for (int i = 0; i < MAX_FANS; i++) {
        char key[5];

        // Read actual RPM (F0Ac, F1Ac, etc.)
        snprintf(key, sizeof(key), "F%dAc", i);
        float rpm = smc_read_key(key);

        if (rpm > 0) {
            fans->rpm[i] = rpm;

            // Read min RPM
            snprintf(key, sizeof(key), "F%dMn", i);
            fans->min_rpm[i] = smc_read_key(key);

            // Read max RPM
            snprintf(key, sizeof(key), "F%dMx", i);
            fans->max_rpm[i] = smc_read_key(key);

            fans->count = i + 1;
        } else {
            break;  // No more fans
        }
    }
}

// ============================================================================
// HID Temperature Sensors (M1 chips fallback)
// ============================================================================

// HID constants
#define kHIDPage_AppleVendor 0xff00
#define kHIDUsage_AppleVendor_TemperatureSensor 0x0005
#define kIOHIDEventTypeTemperature 15

// External HID functions (from IOKit.framework)
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef);
extern void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef, CFDictionaryRef);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef, CFStringRef);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef, int64_t, int32_t, int64_t);
extern double IOHIDEventGetFloatValue(IOHIDEventRef, int32_t);

static void hid_get_temperatures(float *cpu_temp, float *gpu_temp) {
    *cpu_temp = 0.0f;
    *gpu_temp = 0.0f;

    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) return;

    // Create matching dictionary for temperature sensors
    CFNumberRef page = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType,
        &(int){kHIDPage_AppleVendor});
    CFNumberRef usage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType,
        &(int){kHIDUsage_AppleVendor_TemperatureSensor});

    CFStringRef keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    CFTypeRef vals[] = { page, usage };

    CFDictionaryRef match = CFDictionaryCreate(kCFAllocatorDefault,
        (const void **)keys, (const void **)vals, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    IOHIDEventSystemClientSetMatching(client, match);
    CFRelease(match);
    CFRelease(page);
    CFRelease(usage);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (!services) {
        CFRelease(client);
        return;
    }

    float cpu_sum = 0, gpu_sum = 0;
    int cpu_count = 0, gpu_count = 0;

    CFIndex count = CFArrayGetCount(services);
    for (CFIndex i = 0; i < count; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);

        CFStringRef product = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        if (!product) continue;

        char name[128] = {0};
        CFStringGetCString(product, name, sizeof(name), kCFStringEncodingUTF8);
        CFRelease(product);

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service,
            kIOHIDEventTypeTemperature, 0, 0);
        if (!event) continue;

        float temp = (float)IOHIDEventGetFloatValue(event,
            kIOHIDEventTypeTemperature << 16);
        CFRelease(event);

        if (temp < 10 || temp > 130) continue;

        // Match sensor names (M1 chips)
        // CPU: pACC MTR Temp Sensor*, eACC MTR Temp Sensor*
        // GPU: GPU MTR Temp Sensor*
        if (strstr(name, "ACC MTR Temp") || strstr(name, "CPU")) {
            cpu_sum += temp;
            cpu_count++;
        } else if (strstr(name, "GPU MTR Temp") || strstr(name, "GPU")) {
            gpu_sum += temp;
            gpu_count++;
        }
    }

    CFRelease(services);
    CFRelease(client);

    if (cpu_count > 0) *cpu_temp = cpu_sum / cpu_count;
    if (gpu_count > 0) *gpu_temp = gpu_sum / gpu_count;
}

// ============================================================================
// Combined temperature reading (tries SMC first, then HID)
// ============================================================================

static void get_apple_silicon_temps(float *cpu_temp, float *gpu_temp) {
    // Try SMC first (M2/M3)
    smc_get_temperatures(cpu_temp, gpu_temp);

    // If SMC didn't work, try HID (M1)
    if (*cpu_temp == 0 && *gpu_temp == 0) {
        hid_get_temperatures(cpu_temp, gpu_temp);
    }
}

// ============================================================================
// IOReport Interface for Power and Frequency (Apple Silicon)
// Private API - loaded dynamically from IOReport.framework
// ============================================================================

#include <dlfcn.h>

// IOReport opaque types
typedef struct __IOReportSubscription *IOReportSubscriptionRef;

// Function pointer types for IOReport API
typedef CFDictionaryRef (*IOReportCopyChannelsInGroup_t)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
typedef void (*IOReportMergeChannels_t)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
typedef IOReportSubscriptionRef (*IOReportCreateSubscription_t)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
typedef CFDictionaryRef (*IOReportCreateSamples_t)(IOReportSubscriptionRef, CFMutableDictionaryRef, CFTypeRef);
typedef CFDictionaryRef (*IOReportCreateSamplesDelta_t)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
typedef CFStringRef (*IOReportChannelGetGroup_t)(CFDictionaryRef);
typedef CFStringRef (*IOReportChannelGetSubGroup_t)(CFDictionaryRef);
typedef CFStringRef (*IOReportChannelGetChannelName_t)(CFDictionaryRef);
typedef CFStringRef (*IOReportChannelGetUnitLabel_t)(CFDictionaryRef);
typedef int64_t (*IOReportSimpleGetIntegerValue_t)(CFDictionaryRef, int32_t);
typedef int32_t (*IOReportStateGetCount_t)(CFDictionaryRef);
typedef CFStringRef (*IOReportStateGetNameForIndex_t)(CFDictionaryRef, int32_t);
typedef int64_t (*IOReportStateGetResidency_t)(CFDictionaryRef, int32_t);

// Function pointers (loaded dynamically)
static IOReportCopyChannelsInGroup_t pIOReportCopyChannelsInGroup = NULL;
static IOReportMergeChannels_t pIOReportMergeChannels = NULL;
static IOReportCreateSubscription_t pIOReportCreateSubscription = NULL;
static IOReportCreateSamples_t pIOReportCreateSamples = NULL;
static IOReportCreateSamplesDelta_t pIOReportCreateSamplesDelta = NULL;
static IOReportChannelGetGroup_t pIOReportChannelGetGroup = NULL;
static IOReportChannelGetSubGroup_t pIOReportChannelGetSubGroup = NULL;
static IOReportChannelGetChannelName_t pIOReportChannelGetChannelName = NULL;
static IOReportChannelGetUnitLabel_t pIOReportChannelGetUnitLabel = NULL;
static IOReportSimpleGetIntegerValue_t pIOReportSimpleGetIntegerValue = NULL;
static IOReportStateGetCount_t pIOReportStateGetCount = NULL;
static IOReportStateGetNameForIndex_t pIOReportStateGetNameForIndex = NULL;
static IOReportStateGetResidency_t pIOReportStateGetResidency = NULL;

static void *ior_handle = NULL;
static int ior_lib_loaded = 0;

// Load IOReport framework dynamically
static int ior_load_framework(void) {
    if (ior_lib_loaded) return (ior_handle != NULL) ? 0 : -1;
    ior_lib_loaded = 1;

    ior_handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY);
    if (!ior_handle) {
        return -1;
    }

    pIOReportCopyChannelsInGroup = (IOReportCopyChannelsInGroup_t)dlsym(ior_handle, "IOReportCopyChannelsInGroup");
    pIOReportMergeChannels = (IOReportMergeChannels_t)dlsym(ior_handle, "IOReportMergeChannels");
    pIOReportCreateSubscription = (IOReportCreateSubscription_t)dlsym(ior_handle, "IOReportCreateSubscription");
    pIOReportCreateSamples = (IOReportCreateSamples_t)dlsym(ior_handle, "IOReportCreateSamples");
    pIOReportCreateSamplesDelta = (IOReportCreateSamplesDelta_t)dlsym(ior_handle, "IOReportCreateSamplesDelta");
    pIOReportChannelGetGroup = (IOReportChannelGetGroup_t)dlsym(ior_handle, "IOReportChannelGetGroup");
    pIOReportChannelGetSubGroup = (IOReportChannelGetSubGroup_t)dlsym(ior_handle, "IOReportChannelGetSubGroup");
    pIOReportChannelGetChannelName = (IOReportChannelGetChannelName_t)dlsym(ior_handle, "IOReportChannelGetChannelName");
    pIOReportChannelGetUnitLabel = (IOReportChannelGetUnitLabel_t)dlsym(ior_handle, "IOReportChannelGetUnitLabel");
    pIOReportSimpleGetIntegerValue = (IOReportSimpleGetIntegerValue_t)dlsym(ior_handle, "IOReportSimpleGetIntegerValue");
    pIOReportStateGetCount = (IOReportStateGetCount_t)dlsym(ior_handle, "IOReportStateGetCount");
    pIOReportStateGetNameForIndex = (IOReportStateGetNameForIndex_t)dlsym(ior_handle, "IOReportStateGetNameForIndex");
    pIOReportStateGetResidency = (IOReportStateGetResidency_t)dlsym(ior_handle, "IOReportStateGetResidency");

    // Check if essential functions were loaded
    if (!pIOReportCopyChannelsInGroup || !pIOReportCreateSubscription ||
        !pIOReportCreateSamples || !pIOReportSimpleGetIntegerValue) {
        return -1;
    }

    return 0;
}

// IOReport state
static IOReportSubscriptionRef ior_subscription = NULL;
static CFMutableDictionaryRef ior_channels = NULL;
static CFDictionaryRef ior_prev_sample = NULL;
static uint64_t ior_prev_time_ms = 0;
static int ior_initialized = 0;

// Cached power/frequency values
static float cached_cpu_power = 0.0f;   // Watts
static float cached_gpu_power = 0.0f;   // Watts
static float cached_gpu_freq = 0.0f;    // MHz
static float cached_gpu_load = 0.0f;    // Percent

// GPU frequency table (will be populated from pmgr)
#define MAX_GPU_FREQS 32
static uint32_t gpu_freqs[MAX_GPU_FREQS];
static int num_gpu_freqs = 0;

// Get current time in milliseconds
static uint64_t get_time_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

// Helper: get CFString as C string
static int cfstring_to_cstr(CFStringRef str, char *buf, size_t bufsize) {
    if (!str) return 0;
    return CFStringGetCString(str, buf, bufsize, kCFStringEncodingUTF8);
}

// Get GPU frequencies from pmgr IOKit device
static void ior_load_gpu_freqs(void) {
    if (num_gpu_freqs > 0) return;  // Already loaded

    io_iterator_t iter;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("AppleARMIODevice"), &iter);
    if (kr != KERN_SUCCESS) return;

    io_object_t device;
    while ((device = IOIteratorNext(iter)) != 0) {
        char name[128] = {0};
        IORegistryEntryGetName(device, name);

        if (strcmp(name, "pmgr") == 0) {
            CFMutableDictionaryRef props = NULL;
            if (IORegistryEntryCreateCFProperties(device, &props,
                    kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {

                // Get voltage-states9 (GPU frequencies)
                CFDataRef data = CFDictionaryGetValue(props, CFSTR("voltage-states9"));
                if (data) {
                    CFIndex len = CFDataGetLength(data);
                    const uint8_t *bytes = CFDataGetBytePtr(data);

                    // Data is pairs of (freq_hz, voltage) - 4 bytes each
                    int count = (int)(len / 8);
                    for (int i = 0; i < count && num_gpu_freqs < MAX_GPU_FREQS; i++) {
                        uint32_t freq_hz = bytes[i*8] | (bytes[i*8+1] << 8) |
                                          (bytes[i*8+2] << 16) | (bytes[i*8+3] << 24);
                        uint32_t freq_mhz = freq_hz / 1000000;
                        if (freq_mhz > 0) {
                            gpu_freqs[num_gpu_freqs++] = freq_mhz;
                        }
                    }
                }
                CFRelease(props);
            }
        }
        IOObjectRelease(device);
    }
    IOObjectRelease(iter);
}

// Initialize IOReport subscription
static int ior_init(void) {
    if (ior_initialized) return 0;

    // Load IOReport framework
    if (ior_load_framework() != 0) {
        return -1;
    }

    // Get channels for Energy Model (power) and GPU Stats (frequency)
    CFDictionaryRef energy_ch = pIOReportCopyChannelsInGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
    CFDictionaryRef gpu_ch = pIOReportCopyChannelsInGroup(CFSTR("GPU Stats"),
                                                          CFSTR("GPU Performance States"), 0, 0, 0);

    if (!energy_ch && !gpu_ch) {
        return -1;  // No channels available
    }

    // Merge channels
    if (energy_ch && gpu_ch) {
        if (pIOReportMergeChannels) pIOReportMergeChannels(energy_ch, gpu_ch, NULL);
        CFRelease(gpu_ch);
        ior_channels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault,
                                                      CFDictionaryGetCount(energy_ch), energy_ch);
        CFRelease(energy_ch);
    } else if (energy_ch) {
        ior_channels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault,
                                                      CFDictionaryGetCount(energy_ch), energy_ch);
        CFRelease(energy_ch);
    } else {
        ior_channels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault,
                                                      CFDictionaryGetCount(gpu_ch), gpu_ch);
        CFRelease(gpu_ch);
    }

    if (!ior_channels) return -1;

    // Create subscription
    CFMutableDictionaryRef result = NULL;
    ior_subscription = pIOReportCreateSubscription(NULL, ior_channels, &result, 0, NULL);
    if (!ior_subscription) {
        CFRelease(ior_channels);
        ior_channels = NULL;
        return -1;
    }

    // Load GPU frequencies
    ior_load_gpu_freqs();

    ior_initialized = 1;
    return 0;
}

// Convert energy to power (watts)
// energy_val is in nJ, uJ, or mJ depending on unit
static float energy_to_watts(int64_t energy_val, const char *unit, uint64_t duration_ms) {
    if (duration_ms == 0) return 0.0f;

    double joules_per_sec = (double)energy_val / (duration_ms / 1000.0);

    if (strcmp(unit, "nJ") == 0) {
        return (float)(joules_per_sec / 1e9);
    } else if (strcmp(unit, "uJ") == 0) {
        return (float)(joules_per_sec / 1e6);
    } else if (strcmp(unit, "mJ") == 0) {
        return (float)(joules_per_sec / 1e3);
    }
    return 0.0f;
}

// Calculate GPU frequency from residency states
static void calc_gpu_freq_from_residency(CFDictionaryRef channel, float *freq_mhz, float *load_pct) {
    *freq_mhz = 0.0f;
    *load_pct = 0.0f;

    if (num_gpu_freqs == 0) return;

    if (!pIOReportStateGetCount || !pIOReportStateGetResidency) return;

    int state_count = pIOReportStateGetCount(channel);
    if (state_count <= 0) return;

    // Find offset (skip IDLE/OFF states)
    int offset = 0;
    for (int i = 0; i < state_count; i++) {
        CFStringRef name = pIOReportStateGetNameForIndex ? pIOReportStateGetNameForIndex(channel, i) : NULL;
        if (name) {
            char buf[64];
            cfstring_to_cstr(name, buf, sizeof(buf));
            if (strcmp(buf, "IDLE") != 0 && strcmp(buf, "OFF") != 0 && strcmp(buf, "DOWN") != 0) {
                offset = i;
                break;
            }
        }
    }

    // Sum residencies
    int64_t total_residency = 0;
    int64_t active_residency = 0;
    double weighted_freq = 0.0;

    for (int i = 0; i < state_count; i++) {
        int64_t residency = pIOReportStateGetResidency(channel, i);
        total_residency += residency;

        if (i >= offset) {
            active_residency += residency;
            int freq_idx = i - offset;
            if (freq_idx < num_gpu_freqs) {
                weighted_freq += (double)residency * gpu_freqs[freq_idx];
            }
        }
    }

    if (active_residency > 0 && total_residency > 0) {
        *freq_mhz = (float)(weighted_freq / active_residency);
        *load_pct = (float)active_residency / total_residency * 100.0f;
    }
}

// Sample IOReport and update cached values
static void ior_sample(void) {
    if (!ior_initialized && ior_init() != 0) return;
    if (!ior_subscription) return;

    CFDictionaryRef sample = pIOReportCreateSamples(ior_subscription, ior_channels, NULL);
    if (!sample) return;

    uint64_t now_ms = get_time_ms();

    // Need previous sample to compute delta
    if (ior_prev_sample && ior_prev_time_ms > 0) {
        uint64_t duration_ms = now_ms - ior_prev_time_ms;
        if (duration_ms < 10) duration_ms = 10;  // Minimum 10ms

        CFDictionaryRef delta = pIOReportCreateSamplesDelta ? pIOReportCreateSamplesDelta(ior_prev_sample, sample, NULL) : NULL;
        if (delta) {
            // Get channels array
            CFArrayRef channels = CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
            if (channels) {
                float cpu_power = 0, gpu_power = 0;
                float gpu_freq = 0, gpu_load = 0;

                CFIndex count = CFArrayGetCount(channels);
                for (CFIndex i = 0; i < count; i++) {
                    CFDictionaryRef ch = CFArrayGetValueAtIndex(channels, i);
                    if (!ch) continue;

                    CFStringRef group = pIOReportChannelGetGroup ? pIOReportChannelGetGroup(ch) : NULL;
                    CFStringRef channel_name = pIOReportChannelGetChannelName ? pIOReportChannelGetChannelName(ch) : NULL;
                    CFStringRef unit_label = pIOReportChannelGetUnitLabel ? pIOReportChannelGetUnitLabel(ch) : NULL;

                    char group_str[64] = {0};
                    char name_str[64] = {0};
                    char unit_str[16] = {0};

                    if (group) cfstring_to_cstr(group, group_str, sizeof(group_str));
                    if (channel_name) cfstring_to_cstr(channel_name, name_str, sizeof(name_str));
                    if (unit_label) cfstring_to_cstr(unit_label, unit_str, sizeof(unit_str));

                    // Energy Model - power consumption
                    if (strcmp(group_str, "Energy Model") == 0) {
                        int64_t energy = pIOReportSimpleGetIntegerValue(ch, 0);

                        // CPU Energy (handles both "CPU Energy" and "DIE_*_CPU Energy" for Ultra)
                        if (strstr(name_str, "CPU Energy")) {
                            cpu_power += energy_to_watts(energy, unit_str, duration_ms);
                        }
                        // GPU Energy
                        else if (strcmp(name_str, "GPU Energy") == 0) {
                            gpu_power += energy_to_watts(energy, unit_str, duration_ms);
                        }
                    }
                    // GPU Stats - frequency
                    else if (strcmp(group_str, "GPU Stats") == 0) {
                        if (strcmp(name_str, "GPUPH") == 0) {
                            calc_gpu_freq_from_residency(ch, &gpu_freq, &gpu_load);
                        }
                    }
                }

                cached_cpu_power = cpu_power;
                cached_gpu_power = gpu_power;
                cached_gpu_freq = gpu_freq;
                cached_gpu_load = gpu_load;
            }
            CFRelease(delta);
        }
    }

    // Store current sample for next delta
    if (ior_prev_sample) {
        CFRelease(ior_prev_sample);
    }
    ior_prev_sample = sample;
    ior_prev_time_ms = now_ms;
}

// Public getters for power/frequency
float get_cpu_power(void) {
    return cached_cpu_power;
}

float get_gpu_power(void) {
    return cached_gpu_power;
}

float get_gpu_freq(void) {
    return cached_gpu_freq;
}

float get_gpu_load(void) {
    return cached_gpu_load;
}

// Data structures are defined in pcstats.h

// Cached mach host port (doesn't change)
static mach_port_t cached_host_port = 0;

static mach_port_t get_host_port(void) {
    if (!cached_host_port) {
        cached_host_port = mach_host_self();
    }
    return cached_host_port;
}

// Previous CPU ticks for calculating usage
static uint64_t prev_total_ticks = 0;
static uint64_t prev_idle_ticks = 0;

// Previous network bytes for calculating throughput
static uint64_t prev_bytes_in = 0;
static uint64_t prev_bytes_out = 0;
static struct timeval prev_net_time;

// Start time for uptime calculation
static struct timeval start_time;

// Get CPU usage percentage
float get_cpu_usage(void) {
    host_cpu_load_info_data_t cpu_info;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;

    if (host_statistics(get_host_port(), HOST_CPU_LOAD_INFO,
                        (host_info_t)&cpu_info, &count) != KERN_SUCCESS) {
        return 0.0f;
    }

    uint64_t total_ticks = 0;
    for (int i = 0; i < CPU_STATE_MAX; i++) {
        total_ticks += cpu_info.cpu_ticks[i];
    }
    uint64_t idle_ticks = cpu_info.cpu_ticks[CPU_STATE_IDLE];

    uint64_t total_diff = total_ticks - prev_total_ticks;
    uint64_t idle_diff = idle_ticks - prev_idle_ticks;

    prev_total_ticks = total_ticks;
    prev_idle_ticks = idle_ticks;

    if (total_diff == 0) return 0.0f;

    return (1.0f - ((float)idle_diff / (float)total_diff)) * 100.0f;
}

// Get memory usage
void get_memory_usage(Memory *mem) {
    vm_size_t page_size;
    vm_statistics64_data_t vm_stats;
    mach_msg_type_number_t count = sizeof(vm_stats) / sizeof(natural_t);

    host_page_size(get_host_port(), &page_size);

    if (host_statistics64(get_host_port(), HOST_VM_INFO64,
                          (host_info64_t)&vm_stats, &count) != KERN_SUCCESS) {
        mem->used = 0;
        mem->avail = 0;
        mem->percent = 0;
        return;
    }

    // Get total physical memory
    int64_t total_mem;
    size_t len = sizeof(total_mem);
    sysctlbyname("hw.memsize", &total_mem, &len, NULL, 0);

    // Calculate used and available
    uint64_t used_pages = vm_stats.active_count + vm_stats.wire_count;
    uint64_t free_pages = vm_stats.free_count + vm_stats.inactive_count;

    mem->used = (float)(used_pages * page_size) / (1024.0f * 1024.0f * 1024.0f);  // GB
    mem->avail = (float)(free_pages * page_size) / (1024.0f * 1024.0f * 1024.0f); // GB
    mem->percent = ((float)(used_pages * page_size) / (float)total_mem) * 100.0f;
}

// Get network throughput (Mb/s - megabits per second)
void get_network_throughput(Network *net) {
    struct ifaddrs *ifap, *ifa;
    uint64_t bytes_in = 0, bytes_out = 0;
    struct timeval now;

    gettimeofday(&now, NULL);

    if (getifaddrs(&ifap) == 0) {
        for (ifa = ifap; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_addr == NULL) continue;
            if (ifa->ifa_addr->sa_family != AF_LINK) continue;
            if (!(ifa->ifa_flags & IFF_UP)) continue;
            if (ifa->ifa_flags & IFF_LOOPBACK) continue;

            struct if_data *if_data = (struct if_data *)ifa->ifa_data;
            if (if_data) {
                bytes_in += if_data->ifi_ibytes;
                bytes_out += if_data->ifi_obytes;
            }
        }
        freeifaddrs(ifap);
    }

    // Calculate time difference
    double time_diff = (now.tv_sec - prev_net_time.tv_sec) +
                       (now.tv_usec - prev_net_time.tv_usec) / 1000000.0;

    if (time_diff > 0 && prev_bytes_in > 0) {
        // Convert bytes/s to Mb/s (megabits per second): bytes * 8 / 1,000,000
        net->down = (float)(bytes_in - prev_bytes_in) / time_diff * 8.0f / 1000000.0f;   // Mb/s
        net->up = (float)(bytes_out - prev_bytes_out) / time_diff * 8.0f / 1000000.0f;   // Mb/s
    } else {
        net->down = 0;
        net->up = 0;
    }

    prev_bytes_in = bytes_in;
    prev_bytes_out = bytes_out;
    prev_net_time = now;
}

// Get disk usage
void get_disk_usage(Storage *storage) {
    struct statvfs stat;

    if (statvfs("/", &stat) == 0) {
        uint64_t total = stat.f_blocks * stat.f_frsize;
        uint64_t free_space = stat.f_bfree * stat.f_frsize;
        uint64_t used = total - free_space;

        storage->percent = ((float)used / (float)total) * 100.0f;
    } else {
        storage->percent = 0;
    }

    // Disk read/write speeds would require IOKit - set to 0 for now
    storage->read = 0;
    storage->write = 0;
    storage->temp = 0;
}

// Get uptime in seconds
int get_uptime_seconds(void) {
    struct timeval now;
    gettimeofday(&now, NULL);
    return (int)(now.tv_sec - start_time.tv_sec);
}

// Cached temperature values
static float cached_cpu_temp = 0.0f;
static float cached_gpu_temp = 0.0f;
static int use_native_temps = 0;  // -t flag enables native temp reading
static int pcstats_initialized = 0;

// ============================================================================
// Public API Functions
// ============================================================================

// Initialize the stats collection system
void pcstats_init(void) {
    if (pcstats_initialized) return;

    // Initialize timing
    gettimeofday(&start_time, NULL);
    gettimeofday(&prev_net_time, NULL);

    // Take initial CPU reading to establish baseline
    get_cpu_usage();

    // Take initial IOReport sample (for power/frequency delta)
    ior_sample();

    pcstats_initialized = 1;
}

// Enable/disable temperature reading
void pcstats_enable_temps(int enable) {
    use_native_temps = enable;
}

// Update temperatures using native IOKit (no external tools needed)
static void update_temperatures_native(void) {
    get_apple_silicon_temps(&cached_cpu_temp, &cached_gpu_temp);
}

// Get CPU temperature
float get_cpu_temperature(void) {
    return cached_cpu_temp;
}

// Get GPU temperature
float get_gpu_temperature(void) {
    return cached_gpu_temp;
}

// Build JSON string
int build_json(PcStatus *status, char *buffer, size_t bufsize) {
    return snprintf(buffer, bufsize,
        "{"
        "\"board\":{\"temp\":%.1f,\"rpm\":%.1f,\"tick\":%d},"
        "\"cpu\":{\"temp\":%.1f,\"tempMax\":%.1f,\"load\":%.1f,\"consume\":%.1f,"
                "\"tjMax\":%d,\"core1DistanceToTjMax\":%.1f,\"core1Temp\":%.1f},"
        "\"gpu\":{\"temp\":%.1f,\"tempMax\":%.1f,\"load\":%.1f,\"consume\":%.1f,"
                "\"rpm\":%.1f,\"memUsed\":%.1f,\"memTotal\":%.1f,\"freq\":%.1f},"
        "\"storage\":{\"temp\":%.1f,\"read\":%.1f,\"write\":%.1f,\"percent\":%.1f},"
        "\"memory\":{\"used\":%.1f,\"avail\":%.1f,\"percent\":%.1f},"
        "\"network\":{\"up\":%.1f,\"down\":%.1f},"
        "\"cmd\":1230,"
        "\"time\":%ld"
        "}",
        status->board.temp, status->board.rpm, status->board.tick,
        status->cpu.temp, status->cpu.tempMax, status->cpu.load, status->cpu.consume,
        status->cpu.tjMax, status->cpu.core1DistanceToTjMax, status->cpu.core1Temp,
        status->gpu.temp, status->gpu.tempMax, status->gpu.load, status->gpu.consume,
        status->gpu.rpm, status->gpu.memUsed, status->gpu.memTotal, status->gpu.freq,
        status->storage.temp, status->storage.read, status->storage.write, status->storage.percent,
        status->memory.used, status->memory.avail, status->memory.percent,
        status->network.up, status->network.down,
        status->time_stamp
    );
}

// Open serial port
int open_serial(const char *port, int baud) {
    int fd = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) {
        perror("open serial port");
        return -1;
    }

    struct termios options;
    tcgetattr(fd, &options);

    // Set baud rate
    speed_t speed;
    switch (baud) {
        case 9600:   speed = B9600; break;
        case 19200:  speed = B19200; break;
        case 38400:  speed = B38400; break;
        case 57600:  speed = B57600; break;
        case 115200: speed = B115200; break;
        case 230400: speed = B230400; break;
        default:     speed = B115200; break;
    }
    cfsetispeed(&options, speed);
    cfsetospeed(&options, speed);

    // 8N1, no flow control
    options.c_cflag &= ~PARENB;
    options.c_cflag &= ~CSTOPB;
    options.c_cflag &= ~CSIZE;
    options.c_cflag |= CS8;
    options.c_cflag &= ~CRTSCTS;
    options.c_cflag |= CLOCAL | CREAD;

    // Raw input
    options.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
    options.c_iflag &= ~(IXON | IXOFF | IXANY);
    options.c_iflag &= ~(INLCR | ICRNL);
    options.c_oflag &= ~OPOST;

    // Timeouts
    options.c_cc[VMIN] = 0;
    options.c_cc[VTIME] = 10;

    tcsetattr(fd, TCSANOW, &options);
    tcflush(fd, TCIOFLUSH);

    // Clear non-blocking
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);

    return fd;
}

// Send PC status to device
int send_pc_status(int fd, PcStatus *status) {
    char json_buffer[2048];
    int json_len = build_json(status, json_buffer, sizeof(json_buffer));

    if (json_len < 0 || (size_t)json_len >= sizeof(json_buffer)) {
        fprintf(stderr, "JSON buffer overflow\n");
        return -1;
    }

    // Protocol: "pcs" + 2-byte length (big endian) + JSON
    unsigned char header[5];
    header[0] = 'p';
    header[1] = 'c';
    header[2] = 's';
    header[3] = (json_len >> 8) & 0xFF;  // High byte
    header[4] = json_len & 0xFF;          // Low byte

    // Send header
    if (write(fd, header, 5) != 5) {
        perror("write header");
        return -1;
    }

    // Send JSON
    if (write(fd, json_buffer, json_len) != json_len) {
        perror("write json");
        return -1;
    }

    return 0;
}

// Collect all system stats
void collect_stats(PcStatus *status) {
    // Time - adjust for local timezone
    // Device displays timestamp as UTC, so we send local time "as if" it were UTC
    time_t now = time(NULL);
    struct tm *local = localtime(&now);
    status->time_stamp = now + local->tm_gmtoff - 3600;

    // Update temperatures and power/frequency using native IOKit
    if (use_native_temps) {
        update_temperatures_native();
        ior_sample();  // Update power and frequency
    }

    // Board - get fan RPM from SMC
    FanInfo fans;
    get_fan_info(&fans);
    status->board.tick = get_uptime_seconds();
    status->board.temp = smc_get_board_temperature();
    status->board.rpm = (fans.count > 0) ? fans.rpm[0] : 0;  // System fan 1

    // CPU
    status->cpu.load = get_cpu_usage();
    status->cpu.temp = get_cpu_temperature();
    status->cpu.core1Temp = status->cpu.temp;
    status->cpu.tempMax = 100.0f;  // Typical max
    status->cpu.tjMax = 100;
    status->cpu.core1DistanceToTjMax = status->cpu.tjMax - status->cpu.temp;
    status->cpu.consume = get_cpu_power();  // Power in Watts from IOReport

    // GPU - get temp from SMC/HID, power/freq from IOReport
    status->gpu.temp = get_gpu_temperature();
    status->gpu.tempMax = 100.0f;
    status->gpu.load = get_gpu_load();      // GPU usage % from IOReport
    status->gpu.consume = get_gpu_power();  // Power in Watts from IOReport
    status->gpu.rpm = (fans.count > 1) ? fans.rpm[1] : 0;  // System fan 2 (if available)
    status->gpu.memUsed = 0;
    status->gpu.memTotal = 0;
    status->gpu.freq = get_gpu_freq();      // Frequency in MHz from IOReport

    // Storage
    get_disk_usage(&status->storage);

    // Memory
    get_memory_usage(&status->memory);

    // Network
    get_network_throughput(&status->network);

    status->cmd = 1230;
}

void print_stats(PcStatus *status) {
    printf("\033[2J\033[H");  // Clear screen
    printf("=== PC Stats Monitor ===\n\n");

    // CPU with temperature and power
    printf("CPU:     %.1f%%", status->cpu.load);
    if (status->cpu.temp > 0) {
        printf("  Temp: %.1f°C", status->cpu.temp);
    }
    if (status->cpu.consume > 0) {
        printf("  Power: %.1fW", status->cpu.consume);
    }
    printf("\n");

    // GPU (if available)
    if (status->gpu.temp > 0 || status->gpu.load > 0 || status->gpu.consume > 0) {
        printf("GPU:     %.1f%%", status->gpu.load);
        if (status->gpu.temp > 0) {
            printf("  Temp: %.1f°C", status->gpu.temp);
        }
        if (status->gpu.consume > 0) {
            printf("  Power: %.1fW", status->gpu.consume);
        }
        if (status->gpu.freq > 0) {
            printf("  Freq: %.0f MHz", status->gpu.freq);
        }
        if (status->gpu.rpm > 0) {
            printf("  Fan: %.0f RPM", status->gpu.rpm);
        }
        printf("\n");
    }

    // Board (motherboard temp and fan)
    if (status->board.temp > 0 || status->board.rpm > 0) {
        printf("Board:  ");
        if (status->board.temp > 0) {
            printf(" Temp: %.1f°C", status->board.temp);
        }
        if (status->board.rpm > 0) {
            printf("  Fan: %.0f RPM", status->board.rpm);
        }
        printf("\n");
    }

    // Memory
    printf("Memory:  %.1f%% (%.1f GB used / %.1f GB free)\n",
           status->memory.percent, status->memory.used, status->memory.avail);

    // Disk
    printf("Disk:    %.1f%% used\n", status->storage.percent);

    // Network
    printf("Network: down %.1f Mb/s  up %.1f Mb/s\n", status->network.down, status->network.up);

    // Uptime
    int hours = status->board.tick / 3600;
    int mins = (status->board.tick % 3600) / 60;
    int secs = status->board.tick % 60;
    printf("Uptime:  %02d:%02d:%02d\n", hours, mins, secs);

    printf("\nTimestamp: %ld\n", status->time_stamp);
}

// print_usage() and main() have been moved to pcstats_cli.c
