#ifndef KB_MODELS_H
#define KB_MODELS_H

#include <stdint.h>
#include <stddef.h>

#define KB_NAME_MAX 256
#define KB_PATH_MAX 1024
#define KB_PROVIDER_MAX 16
#define KB_IFNAME_MAX 64
#define KB_STATE_MAX 32
#define KB_UUID_MAX 64

typedef struct {
    int32_t pid;
    int32_t ppid;
    uint32_t uid;
    uint64_t start_time_us;
    char name[KB_NAME_MAX];
    char path[KB_PATH_MAX];

    /* PROC_PIDTASKINFO, mach absolute ticks for CPU times. */
    uint64_t cpu_user_ticks;
    uint64_t cpu_system_ticks;
    uint64_t resident_bytes;
    uint64_t virtual_bytes;
    uint32_t threads;
    uint32_t running_threads;
    int32_t priority;
    int32_t nice;
    uint32_t status;        /* proc_bsdinfo.pbi_status */
    uint8_t has_task_info;  /* 0 when taskinfo is not readable */
    /* rusage_info_v6; cumulative counters. */
    uint64_t energy_nj;
    uint64_t penergy_nj;
    uint64_t interrupt_wkups;
    uint64_t pkg_idle_wkups;
    uint64_t diskio_bytes_read;
    uint64_t diskio_bytes_written;
    uint64_t logical_writes;
} kb_process;

typedef struct {
    uint32_t index;
    uint64_t user_ticks;
    uint64_t system_ticks;
    uint64_t idle_ticks;
    uint64_t nice_ticks;
} kb_cpu_core;

#define KB_MAX_CORES 256

typedef struct {
    uint32_t core_count;
    kb_cpu_core cores[KB_MAX_CORES];
    uint64_t page_size;
    uint64_t mem_total;
    uint64_t mem_free;
    uint64_t mem_active;
    uint64_t mem_inactive;
    uint64_t mem_wired;
    uint64_t mem_compressor;
    uint64_t mem_speculative;
    uint64_t mem_purgeable;
    uint64_t mem_internal;
    uint64_t mem_external;
    uint64_t swap_total;
    uint64_t swap_used;
    uint64_t swap_avail;
    uint8_t swap_encrypted;
    /* 100 - memorystatus free %, or -1 when unavailable. */
    int32_t mem_pressure_percent;
    /* kern.memorystatus_vm_pressure_level (1 normal, 2 warning, 4 critical),
       or -1 when unavailable. */
    int32_t mem_pressure_level;
    uint8_t load_valid;
    double load1;
    double load5;
    double load15;
    uint64_t boot_time_us;
} kb_host_stats;

typedef struct {
    int32_t valid;
    /* -1 when the key is missing. */
    double utilization_percent;   /* Device Utilization % */
    double renderer_percent;       /* Renderer Utilization % */
    double tiler_percent;          /* Tiler Utilization % */
    uint64_t in_use_memory;        /* In use system memory */
    uint64_t alloc_memory;         /* Alloc system memory */
    char name[128];                /* machdep.cpu.brand_string */
} kb_gpu_stats;

typedef struct {
    int32_t valid;
    int32_t has_battery;
    int32_t is_plugged_in;
    int32_t is_charging;
    int32_t is_charged;
    int32_t charge_percent;        /* -1 unknown */
    int32_t time_remaining_min;    /* minutes; -1 unknown */
    char source[32];               /* "AC Power" / "Battery Power" */
} kb_power_stats;

/* Battery charge history for the last 12 hours, as Activity Monitor's Energy
   tab shows it. Times are seconds before the moment of the read. */
typedef struct {
    double *charge_times;          /* charge sample times, oldest -> newest */
    double *charge_levels;         /* percentage 0...100 */
    size_t charge_count;
    double *state_times;           /* AC/battery transition times */
    int32_t *on_ac;                /* 1 = on AC power, 0 = on battery */
    size_t state_count;
} kb_battery_charge_graph;

typedef struct {
    uint64_t source_id;
    int32_t pid;
    int32_t epid;
    uint32_t uid;
    char process_name[KB_NAME_MAX];
    char provider[KB_PROVIDER_MAX];
    char tcp_state[KB_STATE_MAX];
    char if_name[KB_IFNAME_MAX];
    char if_type[KB_IFNAME_MAX];
    char uuid[KB_UUID_MAX];
    uint8_t local_family;
    uint8_t remote_family;
    uint8_t local_addr[16];
    uint8_t remote_addr[16];
    uint16_t local_port;
    uint16_t remote_port;
    uint32_t local_scope;
    uint32_t remote_scope;
    uint64_t rx_bytes;
    uint64_t tx_bytes;
    uint64_t rx_packets;
    uint64_t tx_packets;
    uint64_t rx_wifi;
    uint64_t tx_wifi;
    uint64_t rx_wired;
    uint64_t tx_wired;
    uint64_t rx_cellular;
    uint64_t tx_cellular;
    uint64_t rx_dupe;
    uint64_t rx_ooo;
    uint64_t tx_retx;
    double rtt;
    uint64_t start_ns;
    uint8_t has_splits;
} kb_nstat_source;

typedef struct {
    int32_t pid;
    int32_t fd;
    int32_t family;
    int32_t protocol;
    int32_t type;
    int32_t state;
    uint8_t local_addr[16];
    uint8_t remote_addr[16];
    uint16_t local_port;
    uint16_t remote_port;
    uint32_t local_scope;
    uint32_t remote_scope;
} kb_socket;

typedef struct {
    int32_t pid;
    uint32_t total;       /* unique sockets (deduped by soi_so) */
    uint32_t fds;         /* socket FDs, duplicates included */
    uint32_t tcp4;
    uint32_t tcp6;
    uint32_t udp4;
    uint32_t udp6;
    uint32_t unix_count;
    uint32_t raw4;
    uint32_t raw6;
    uint32_t other;
    uint64_t other_families; /* bitset of address families counted in `other` (AF_MAX < 64) */
    uint64_t inet_protocols[4]; /* bitset of IPPROTO 0..255 for INET sockets outside TCP/UDP */
    uint32_t stream;
    uint32_t dgram;
    uint32_t raw_type;
    uint32_t seqpacket;
    uint32_t other_type;
    uint8_t restricted;   /* PROC_PIDLISTFDS failed (permissions/gone) */
    uint8_t truncated;    /* per-PID socket cap reached */
} kb_socket_summary;

typedef struct {
    int32_t fd;
    uint32_t type;
    uint64_t size;
    char path[KB_PATH_MAX];
} kb_open_file;

typedef struct {
    uint32_t index;
    char name[KB_IFNAME_MAX];
    uint32_t flags;
    uint32_t type;
    uint64_t rx_bytes;
    uint64_t tx_bytes;
    uint64_t rx_packets;
    uint64_t tx_packets;
    uint64_t rx_errors;
    uint64_t tx_errors;
    uint64_t rx_drops;
    uint64_t collisions;
    uint32_t mtu;
    uint64_t baudrate;
} kb_interface;

#endif
