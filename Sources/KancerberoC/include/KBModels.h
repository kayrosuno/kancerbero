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
} kb_process;

typedef struct {
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
