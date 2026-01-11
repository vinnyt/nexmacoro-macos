/*
 * pcstats.h - macOS PC Stats for NexMacro Device
 *
 * Header file exposing core functionality for CLI and GUI apps
 */

#ifndef PCSTATS_H
#define PCSTATS_H

#include <stdint.h>
#include <stddef.h>

// ============================================================================
// Data Structures
// ============================================================================

typedef struct {
    float temp;
    float rpm;
    int tick;
} Motherboard;

typedef struct {
    float temp;
    float tempMax;
    float load;
    float consume;
    int tjMax;
    float core1DistanceToTjMax;
    float core1Temp;
} CPU;

typedef struct {
    float temp;
    float tempMax;
    float load;
    float consume;
    float rpm;
    float memUsed;
    float memTotal;
    float freq;
} GPU;

typedef struct {
    float temp;
    float read;
    float write;
    float percent;
} Storage;

typedef struct {
    float used;
    float avail;
    float percent;
} Memory;

typedef struct {
    float up;
    float down;
} Network;

typedef struct {
    Motherboard board;
    CPU cpu;
    GPU gpu;
    Storage storage;
    Memory memory;
    Network network;
    int cmd;
    long time_stamp;
} PcStatus;

// ============================================================================
// Core Functions
// ============================================================================

// Initialize the stats collection system (call once at startup)
void pcstats_init(void);

// Enable/disable temperature reading
void pcstats_enable_temps(int enable);

// Collect all system stats into the provided structure
void collect_stats(PcStatus *status);

// Individual stat getters
float get_cpu_usage(void);
float get_cpu_temperature(void);
float get_gpu_temperature(void);

// Fan info
#define MAX_FANS 4
typedef struct {
    int count;
    float rpm[MAX_FANS];
    float min_rpm[MAX_FANS];
    float max_rpm[MAX_FANS];
} FanInfo;

void get_fan_info(FanInfo *fans);
void get_memory_usage(Memory *mem);
void get_network_throughput(Network *net);
void get_disk_usage(Storage *storage);
int get_uptime_seconds(void);

// JSON building
int build_json(PcStatus *status, char *buffer, size_t bufsize);

// Serial port communication
int open_serial(const char *port, int baud);
int send_pc_status(int fd, PcStatus *status);

// Display
void print_stats(PcStatus *status);

#endif // PCSTATS_H
