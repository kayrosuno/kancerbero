#include "KancerberoC.h"

#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/machine.h>
#include <mach/processor_info.h>
#include <mach/vm_statistics.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>

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

int kb_host_stats_read(kb_host_stats *out)
{
    if (!out) {
        return -1;
    }
    memset(out, 0, sizeof(*out));

    mach_port_t host = mach_host_self();
    if (host == MACH_PORT_NULL) {
        return -1;
    }

    vm_size_t page_size = 0;
    if (host_page_size(host, &page_size) == KERN_SUCCESS && page_size > 0) {
        out->page_size = (uint64_t)page_size;
    } else {
        long fallback = sysconf(_SC_PAGESIZE);
        out->page_size = fallback > 0 ? (uint64_t)fallback : 4096;
    }

    size_t length = sizeof(out->mem_total);
    if (sysctlbyname("hw.memsize", &out->mem_total, &length, NULL, 0) != 0) {
        out->mem_total = 0;
    }

    struct xsw_usage swap;
    memset(&swap, 0, sizeof(swap));
    length = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &length, NULL, 0) == 0) {
        out->swap_total = swap.xsu_total;
        out->swap_used = swap.xsu_used;
        out->swap_avail = swap.xsu_avail;
        out->swap_encrypted = swap.xsu_encrypted ? 1 : 0;
    }

    struct timeval boot_time;
    memset(&boot_time, 0, sizeof(boot_time));
    length = sizeof(boot_time);
    int boot_mib[2] = {CTL_KERN, KERN_BOOTTIME};
    if (sysctl(boot_mib, 2, &boot_time, &length, NULL, 0) == 0) {
        out->boot_time_us = ((uint64_t)boot_time.tv_sec * 1000000ULL) +
                            (uint64_t)boot_time.tv_usec;
    }

    double loads[3] = {0, 0, 0};
    if (getloadavg(loads, 3) == 3) {
        out->load_valid = 1;
        out->load1 = loads[0];
        out->load5 = loads[1];
        out->load15 = loads[2];
    }

    vm_statistics64_data_t vm;
    memset(&vm, 0, sizeof(vm));
    mach_msg_type_number_t vm_count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(host, HOST_VM_INFO64,
                          (host_info64_t)&vm, &vm_count) == KERN_SUCCESS) {
        uint64_t page = out->page_size;
        out->mem_free = (uint64_t)vm.free_count * page;
        out->mem_active = (uint64_t)vm.active_count * page;
        out->mem_inactive = (uint64_t)vm.inactive_count * page;
        out->mem_wired = (uint64_t)vm.wire_count * page;
        out->mem_compressor = (uint64_t)vm.compressor_page_count * page;
        out->mem_speculative = (uint64_t)vm.speculative_count * page;
        out->mem_purgeable = (uint64_t)vm.purgeable_count * page;
        out->mem_internal = (uint64_t)vm.internal_page_count * page;
        out->mem_external = (uint64_t)vm.external_page_count * page;
    }

    natural_t cpu_count = 0;
    processor_info_array_t cpu_info = NULL;
    mach_msg_type_number_t cpu_info_count = 0;
    if (host_processor_info(host, PROCESSOR_CPU_LOAD_INFO,
                            &cpu_count, &cpu_info, &cpu_info_count) == KERN_SUCCESS
        && cpu_info != NULL) {
        processor_cpu_load_info_t load =
            (processor_cpu_load_info_t)cpu_info;
        uint32_t count = cpu_count < KB_MAX_CORES ? (uint32_t)cpu_count : KB_MAX_CORES;
        out->core_count = count;
        for (uint32_t index = 0; index < count; index++) {
            out->cores[index].index = index;
            out->cores[index].user_ticks = load[index].cpu_ticks[CPU_STATE_USER];
            out->cores[index].system_ticks = load[index].cpu_ticks[CPU_STATE_SYSTEM];
            out->cores[index].idle_ticks = load[index].cpu_ticks[CPU_STATE_IDLE];
            out->cores[index].nice_ticks = load[index].cpu_ticks[CPU_STATE_NICE];
        }
        vm_deallocate(mach_task_self(), (vm_address_t)cpu_info,
                      (vm_size_t)cpu_info_count * sizeof(integer_t));
    }

    mach_port_deallocate(mach_task_self(), host);
    return 0;
}
