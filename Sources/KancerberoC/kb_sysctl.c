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

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPSKeys.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

/*
 * Exported by libsystem_kernel and used by Activity Monitor. It fills the
 * system-wide memory free percentage (0-100); it takes no port argument.
 */
extern int memorystatus_get_level(int *level);

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

int kb_memory_pressure_read(int32_t *percent, int32_t *level)
{
    if (!percent || !level) {
        return -1;
    }

    int free_percent = -1;
    if (memorystatus_get_level(&free_percent) != 0) {
        return -1;
    }
    *percent = (int32_t)(100 - free_percent);

    int vm_level = 0;
    size_t level_size = sizeof(vm_level);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &vm_level,
                     &level_size, NULL, 0) == 0) {
        *level = (int32_t)vm_level;
    } else {
        *level = -1;
    }
    return 0;
}

static double kb_cf_double(CFDictionaryRef dictionary, CFStringRef key)
{
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return -1;
    }
    double result = -1;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &result)) {
        return -1;
    }
    return result;
}

static uint64_t kb_cf_u64(CFDictionaryRef dictionary, CFStringRef key)
{
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    int64_t result = 0;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &result)) {
        return 0;
    }
    return result < 0 ? 0 : (uint64_t)result;
}

int kb_gpu_stats_read(kb_gpu_stats *out)
{
    if (!out) {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    out->utilization_percent = -1;
    out->renderer_percent = -1;
    out->tiler_percent = -1;

    size_t name_length = sizeof(out->name);
    if (sysctlbyname("machdep.cpu.brand_string", out->name, &name_length,
                     NULL, 0) != 0) {
        out->name[0] = '\0';
    }

    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                     IOServiceMatching("IOAccelerator"),
                                     &iterator) != KERN_SUCCESS) {
        return -1;
    }

    io_service_t service = 0;
    while ((service = IOIteratorNext(iterator)) != 0) {
        CFMutableDictionaryRef properties = NULL;
        if (IORegistryEntryCreateCFProperties(service, &properties,
                                              kCFAllocatorDefault, 0) == KERN_SUCCESS
            && properties) {
            CFTypeRef statistics =
                CFDictionaryGetValue(properties, CFSTR("PerformanceStatistics"));
            if (statistics && CFGetTypeID(statistics) == CFDictionaryGetTypeID()) {
                CFDictionaryRef dictionary = (CFDictionaryRef)statistics;
                out->utilization_percent =
                    kb_cf_double(dictionary, CFSTR("Device Utilization %"));
                out->renderer_percent =
                    kb_cf_double(dictionary, CFSTR("Renderer Utilization %"));
                out->tiler_percent =
                    kb_cf_double(dictionary, CFSTR("Tiler Utilization %"));
                out->in_use_memory =
                    kb_cf_u64(dictionary, CFSTR("In use system memory"));
                out->alloc_memory =
                    kb_cf_u64(dictionary, CFSTR("Alloc system memory"));
                out->valid = 1;
            }
            CFRelease(properties);
        }
        IOObjectRelease(service);
        if (out->valid) {
            break;
        }
    }
    IOObjectRelease(iterator);
    return out->valid ? 0 : -1;
}

static int kb_cf_int(CFDictionaryRef dictionary, CFStringRef key, int fallback)
{
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return fallback;
    }
    int result = fallback;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &result)) {
        return fallback;
    }
    return result;
}

static int kb_cf_bool(CFDictionaryRef dictionary, CFStringRef key)
{
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    if (!value || CFGetTypeID(value) != CFBooleanGetTypeID()) {
        return 0;
    }
    return CFBooleanGetValue((CFBooleanRef)value) ? 1 : 0;
}

int kb_power_stats_read(kb_power_stats *out)
{
    if (!out) {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    out->charge_percent = -1;
    out->time_remaining_min = -1;

    CFTypeRef blob = IOPSCopyPowerSourcesInfo();
    if (!blob) {
        return -1;
    }
    CFArrayRef sources = IOPSCopyPowerSourcesList(blob);
    if (!sources) {
        CFRelease(blob);
        return -1;
    }

    out->valid = 1;
    CFIndex count = CFArrayGetCount(sources);
    for (CFIndex index = 0; index < count; index++) {
        CFTypeRef source = CFArrayGetValueAtIndex(sources, index);
        CFDictionaryRef description = IOPSGetPowerSourceDescription(blob, source);
        if (!description) {
            continue;
        }
        CFStringRef type = CFDictionaryGetValue(description, CFSTR(kIOPSTypeKey));
        if (!type || CFGetTypeID(type) != CFStringGetTypeID() ||
            CFStringCompare(type, CFSTR(kIOPSInternalBatteryType), 0) != kCFCompareEqualTo) {
            continue;
        }

        out->has_battery = kb_cf_bool(description, CFSTR(kIOPSIsPresentKey));
        if (out->has_battery) {
            int current = kb_cf_int(description, CFSTR(kIOPSCurrentCapacityKey), -1);
            int maximum = kb_cf_int(description, CFSTR(kIOPSMaxCapacityKey), -1);
            if (current >= 0 && maximum > 0) {
                out->charge_percent = (int32_t)((int64_t)current * 100 / maximum);
            }
            out->is_charging = kb_cf_bool(description, CFSTR(kIOPSIsChargingKey));
            out->is_charged = kb_cf_bool(description, CFSTR(kIOPSIsChargedKey));

            CFStringRef state = CFDictionaryGetValue(description,
                                                     CFSTR(kIOPSPowerSourceStateKey));
            if (state && CFGetTypeID(state) == CFStringGetTypeID()) {
                out->is_plugged_in =
                    CFStringCompare(state, CFSTR(kIOPSACPowerValue), 0) == kCFCompareEqualTo;
                CFStringGetCString(state, out->source, sizeof(out->source),
                                   kCFStringEncodingUTF8);
            }

            CFStringRef time_key = out->is_charging
                ? CFSTR(kIOPSTimeToFullChargeKey)
                : CFSTR(kIOPSTimeToEmptyKey);
            int minutes = kb_cf_int(description, time_key, -1);
            out->time_remaining_min = minutes > 0 ? minutes : -1;
        }
        break;
    }

    CFRelease(sources);
    CFRelease(blob);
    return 0;
}

int kb_prevent_sleep_pids(int32_t **pids, size_t *count)
{
    if (!pids || !count) {
        return -1;
    }
    *pids = NULL;
    *count = 0;

    CFDictionaryRef assertions = NULL;
    if (IOPMCopyAssertionsByProcess(&assertions) != kIOReturnSuccess ||
        !assertions) {
        return -1;
    }

    CFIndex total = CFDictionaryGetCount(assertions);
    size_t capacity = (size_t)(total > 0 ? total : 1);
    int32_t *result = (int32_t *)calloc(capacity, sizeof(int32_t));
    const void **keys = (const void **)calloc(capacity, sizeof(void *));
    const void **values = (const void **)calloc(capacity, sizeof(void *));
    if (!result || !keys || !values) {
        free(result);
        free(keys);
        free(values);
        CFRelease(assertions);
        return -1;
    }
    CFDictionaryGetKeysAndValues(assertions, keys, values);

    size_t found = 0;
    for (CFIndex index = 0; index < total; index++) {
        int32_t pid = 0;
        if (!keys[index] || CFGetTypeID(keys[index]) != CFNumberGetTypeID() ||
            !CFNumberGetValue((CFNumberRef)keys[index], kCFNumberSInt32Type, &pid)) {
            continue;
        }
        if (!values[index] || CFGetTypeID(values[index]) != CFArrayGetTypeID()) {
            continue;
        }
        CFArrayRef list = (CFArrayRef)values[index];
        CFIndex assertionCount = CFArrayGetCount(list);
        int prevents = 0;
        for (CFIndex item = 0; item < assertionCount && !prevents; item++) {
            CFTypeRef entry = CFArrayGetValueAtIndex(list, item);
            if (!entry || CFGetTypeID(entry) != CFDictionaryGetTypeID()) {
                continue;
            }
            CFDictionaryRef dictionary = (CFDictionaryRef)entry;
            if (kb_cf_int(dictionary, kIOPMAssertionLevelKey, 0) <= 0) {
                continue;
            }
            CFStringRef type = CFDictionaryGetValue(dictionary,
                                                    kIOPMAssertionTypeKey);
            if (!type || CFGetTypeID(type) != CFStringGetTypeID()) {
                continue;
            }
            if (CFStringCompare(type,
                                kIOPMAssertionTypePreventUserIdleSystemSleep, 0)
                    == kCFCompareEqualTo ||
                CFStringCompare(type, kIOPMAssertionTypePreventSystemSleep, 0)
                    == kCFCompareEqualTo) {
                prevents = 1;
            }
        }
        if (prevents) {
            result[found++] = pid;
        }
    }

    free(keys);
    free(values);
    CFRelease(assertions);

    if (found == 0) {
        free(result);
        return 0;
    }
    *pids = result;
    *count = found;
    return 0;
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

    /*
     * Memory pressure exactly as Activity Monitor reports it: the free
     * percentage from memorystatus_get_level, inverted, plus the kernel's
     * discrete pressure level (1 normal, 2 warning, 4 critical).
     */
    out->mem_pressure_percent = -1;
    out->mem_pressure_level = -1;
    int32_t pressure_percent = -1;
    int32_t pressure_level = -1;
    if (kb_memory_pressure_read(&pressure_percent, &pressure_level) == 0) {
        out->mem_pressure_percent = pressure_percent;
        out->mem_pressure_level = pressure_level;
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
