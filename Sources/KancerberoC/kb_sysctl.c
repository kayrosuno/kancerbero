#include "KancerberoC.h"

#include <net/if.h>
#include <net/if_mib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/types.h>

/*
 * Interface counters come from the IFMIB sysctl, not NET_RT_IFLIST2.
 * On macOS 27 the NET_RT_IFLIST2 path returns if_data64 with only the low
 * 32 bits of ifi_ibytes/ifi_obytes populated (verified against netstat),
 * while net.link.generic.ifdata returns the full 64-bit values.
 */
int kb_interface_list(kb_interface **out, size_t *count)
{
    if (!out || !count) {
        return -1;
    }
    *out = NULL;
    *count = 0;

    int name[16];
    size_t name_length = sizeof(name) / sizeof(name[0]);
    if (sysctlnametomib("net.link.generic.system.ifcount", name, &name_length) != 0) {
        return -1;
    }
    if (name_length < 5) {
        return -1;
    }

    int interface_count = 0;
    size_t count_length = sizeof(interface_count);
    if (sysctl(name, (u_int)name_length, &interface_count, &count_length, NULL, 0) != 0) {
        return -1;
    }
    if (interface_count <= 0) {
        return -1;
    }

    kb_interface *items = (kb_interface *)calloc((size_t)interface_count, sizeof(kb_interface));
    if (!items) {
        return -1;
    }

    size_t cursor = 0;
    for (int index = 1; index <= interface_count; index++) {
        int mib[8];
        memcpy(mib, name, sizeof(int) * name_length);
        mib[3] = IFMIB_IFDATA;
        mib[4] = index;
        mib[5] = IFDATA_GENERAL;

        struct ifmibdata data;
        size_t length = sizeof(data);
        memset(&data, 0, sizeof(data));
        if (sysctl(mib, 6, &data, &length, NULL, 0) != 0) {
            continue;
        }

        kb_interface *item = &items[cursor++];
        item->index = (uint32_t)index;
        strncpy(item->name, data.ifmd_name, sizeof(item->name) - 1);
        item->flags = data.ifmd_flags;
        item->type = data.ifmd_data.ifi_type;
        item->rx_bytes = data.ifmd_data.ifi_ibytes;
        item->tx_bytes = data.ifmd_data.ifi_obytes;
        item->rx_packets = data.ifmd_data.ifi_ipackets;
        item->tx_packets = data.ifmd_data.ifi_opackets;
        item->rx_errors = data.ifmd_data.ifi_ierrors;
        item->tx_errors = data.ifmd_data.ifi_oerrors;
        item->rx_drops = data.ifmd_data.ifi_iqdrops;
        item->collisions = data.ifmd_data.ifi_collisions;
        item->mtu = data.ifmd_data.ifi_mtu;
        item->baudrate = data.ifmd_data.ifi_baudrate;
    }

    *out = items;
    *count = cursor;
    return 0;
}

void kb_interface_list_free(kb_interface *items)
{
    free(items);
}

int kb_sysctl_int(const char *name, int *value)
{
    if (!name || !value) {
        return -1;
    }
    size_t length = sizeof(*value);
    return sysctlbyname(name, value, &length, NULL, 0);
}
