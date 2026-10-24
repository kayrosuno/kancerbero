#include "KBDisk.h"

#include <CoreFoundation/CoreFoundation.h>
#include <DiskArbitration/DiskArbitration.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOMedia.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/attr.h>
#include <sys/mount.h>
#include <unistd.h>

#define KB_DISK_APFS_CONTAINER_CONTENT "EF57347C-0000-11AA-AA11-00306543ECAC"

static uint32_t read_u32(const char *pointer)
{
    uint32_t value = 0;
    memcpy(&value, pointer, sizeof(value));
    return value;
}

static uint64_t read_u64(const char *pointer)
{
    uint64_t value = 0;
    memcpy(&value, pointer, sizeof(value));
    return value;
}

static void copy_string(CFTypeRef value, char *destination, size_t size)
{
    if (!destination || size == 0) {
        return;
    }
    destination[0] = '\0';
    if (!value) {
        return;
    }

    CFTypeID type = CFGetTypeID(value);
    if (type == CFStringGetTypeID()) {
        CFStringGetCString((CFStringRef)value, destination, (CFIndex)size,
                           kCFStringEncodingUTF8);
    } else if (type == CFURLGetTypeID()) {
        CFURLGetFileSystemRepresentation((CFURLRef)value, true,
                                         (UInt8 *)destination, (CFIndex)size);
    } else if (type == CFUUIDGetTypeID()) {
        CFStringRef text = CFUUIDCreateString(kCFAllocatorDefault, (CFUUIDRef)value);
        if (text) {
            CFStringGetCString(text, destination, (CFIndex)size,
                               kCFStringEncodingUTF8);
            CFRelease(text);
        }
    }
}

static uint64_t copy_u64(CFTypeRef value)
{
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    int64_t number = 0;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &number)) {
        return 0;
    }
    return (uint64_t)number;
}

static uint8_t copy_bool(CFTypeRef value)
{
    if (!value || CFGetTypeID(value) != CFBooleanGetTypeID()) {
        return 0;
    }
    return CFBooleanGetValue((CFBooleanRef)value) ? 1 : 0;
}

static void copy_class(io_registry_entry_t entry, char *destination, size_t size)
{
    io_name_t name;
    if (IOObjectGetClass(entry, name) == KERN_SUCCESS) {
        strncpy(destination, name, size - 1);
        destination[size - 1] = '\0';
    }
}

static void copy_roles(CFTypeRef value, char *destination, size_t size)
{
    if (!destination || size == 0) {
        return;
    }
    destination[0] = '\0';
    if (!value || CFGetTypeID(value) != CFArrayGetTypeID()) {
        return;
    }

    CFArrayRef array = (CFArrayRef)value;
    CFIndex count = CFArrayGetCount(array);
    size_t offset = 0;
    for (CFIndex index = 0; index < count; index++) {
        CFTypeRef item = CFArrayGetValueAtIndex(array, index);
        if (!item || CFGetTypeID(item) != CFStringGetTypeID()) {
            continue;
        }
        char part[64];
        if (!CFStringGetCString((CFStringRef)item, part, sizeof(part),
                                kCFStringEncodingUTF8)) {
            continue;
        }
        size_t part_length = strlen(part);
        size_t separator = offset > 0 ? 1 : 0;
        if (offset + separator + part_length >= size) {
            break;
        }
        if (separator) {
            destination[offset++] = ',';
        }
        memcpy(destination + offset, part, part_length);
        offset += part_length;
        destination[offset] = '\0';
    }
}

/* Returns the nearest ancestor that is an IOMedia, or 0. The caller releases it. */
static io_registry_entry_t copy_parent_media(io_registry_entry_t service)
{
    io_registry_entry_t current = service;
    IOObjectRetain(current);
    for (int depth = 0; depth < 32; depth++) {
        io_registry_entry_t parent = 0;
        kern_return_t result = IORegistryEntryGetParentEntry(current,
                                                              kIOServicePlane,
                                                              &parent);
        IOObjectRelease(current);
        if (result != KERN_SUCCESS) {
            return 0;
        }
        current = parent;
        if (IOObjectConformsTo(current, kIOMediaClass)) {
            return current;
        }
    }
    IOObjectRelease(current);
    return 0;
}

static void fill_capacity_from_mount(kb_disk_media *item,
                                     const struct statfs *mount)
{
    struct attrlist attributes;
    memset(&attributes, 0, sizeof(attributes));
    attributes.bitmapcount = ATTR_BIT_MAP_COUNT;
    attributes.volattr = ATTR_VOL_INFO |
                         ATTR_VOL_SIZE |
                         ATTR_VOL_SPACEFREE |
                         ATTR_VOL_SPACEAVAIL |
                         ATTR_VOL_SPACEUSED;

    char buffer[256];
    int result = getattrlist(mount->f_mntonname, &attributes, buffer,
                             sizeof(buffer), 0);
    if (result == 0) {
        uint32_t length = read_u32(buffer);
        if (length >= sizeof(uint32_t) + 4 * sizeof(uint64_t)) {
            const char *field = buffer + sizeof(uint32_t);
            item->volume_size_bytes = read_u64(field);
            field += sizeof(uint64_t);
            item->free_bytes = read_u64(field);
            field += sizeof(uint64_t);
            item->available_bytes = read_u64(field);
            field += sizeof(uint64_t);
            item->used_bytes = read_u64(field);
        }
    }

    if (item->volume_size_bytes == 0) {
        uint64_t block_size = (uint64_t)mount->f_bsize;
        item->volume_size_bytes = (uint64_t)mount->f_blocks * block_size;
        item->free_bytes = (uint64_t)mount->f_bfree * block_size;
        item->available_bytes = (uint64_t)mount->f_bavail * block_size;
        item->used_bytes = item->volume_size_bytes >= item->free_bytes
            ? item->volume_size_bytes - item->free_bytes
            : 0;
    }
}

int kb_disk_media_list(kb_disk_media **out, size_t *count)
{
    if (!out || !count) {
        return -1;
    }
    *out = NULL;
    *count = 0;

    CFMutableDictionaryRef matching = IOServiceMatching(kIOMediaClass);
    if (!matching) {
        return -1;
    }

    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching,
                                     &iterator) != KERN_SUCCESS) {
        return -1;
    }

    DASessionRef session = DASessionCreate(kCFAllocatorDefault);

    kb_disk_media *items = NULL;
    size_t capacity = 0;
    size_t used = 0;
    int failed = 0;

    io_service_t service = 0;
    while ((service = IOIteratorNext(iterator))) {
        kb_disk_media item;
        memset(&item, 0, sizeof(item));

        CFTypeRef bsd_name = IORegistryEntryCreateCFProperty(
            service, CFSTR("BSD Name"), kCFAllocatorDefault, 0);
        copy_string(bsd_name, item.bsd_name, sizeof(item.bsd_name));
        if (bsd_name) {
            CFRelease(bsd_name);
        }

        CFTypeRef size = IORegistryEntryCreateCFProperty(
            service, CFSTR("Size"), kCFAllocatorDefault, 0);
        item.size_bytes = copy_u64(size);
        if (size) {
            CFRelease(size);
        }

        CFTypeRef content = IORegistryEntryCreateCFProperty(
            service, CFSTR("Content"), kCFAllocatorDefault, 0);
        copy_string(content, item.content, sizeof(item.content));
        if (content) {
            CFRelease(content);
        }

        CFTypeRef whole = IORegistryEntryCreateCFProperty(
            service, CFSTR("Whole"), kCFAllocatorDefault, 0);
        item.is_whole = copy_bool(whole);
        if (whole) {
            CFRelease(whole);
        }

        CFTypeRef leaf = IORegistryEntryCreateCFProperty(
            service, CFSTR("Leaf"), kCFAllocatorDefault, 0);
        item.is_leaf = copy_bool(leaf);
        if (leaf) {
            CFRelease(leaf);
        }

        CFTypeRef media_uuid = IORegistryEntryCreateCFProperty(
            service, CFSTR("UUID"), kCFAllocatorDefault, 0);
        copy_string(media_uuid, item.media_uuid, sizeof(item.media_uuid));
        if (media_uuid) {
            CFRelease(media_uuid);
        }

        CFTypeRef removable = IORegistryEntryCreateCFProperty(
            service, CFSTR("Removable"), kCFAllocatorDefault, 0);
        item.is_removable = copy_bool(removable);
        if (removable) {
            CFRelease(removable);
        }

        CFTypeRef ejectable = IORegistryEntryCreateCFProperty(
            service, CFSTR("Ejectable"), kCFAllocatorDefault, 0);
        item.is_ejectable = copy_bool(ejectable);
        if (ejectable) {
            CFRelease(ejectable);
        }

        CFTypeRef writable = IORegistryEntryCreateCFProperty(
            service, CFSTR("Writable"), kCFAllocatorDefault, 0);
        item.is_writable = copy_bool(writable);
        if (writable) {
            CFRelease(writable);
        }

        CFTypeRef role_value = IORegistryEntryCreateCFProperty(
            service, CFSTR("RoleValue"), kCFAllocatorDefault, 0);
        item.role_value = (uint32_t)copy_u64(role_value);
        if (role_value) {
            CFRelease(role_value);
        }

        CFTypeRef role = IORegistryEntryCreateCFProperty(
            service, CFSTR("Role"), kCFAllocatorDefault, 0);
        copy_roles(role, item.roles, sizeof(item.roles));
        if (role) {
            CFRelease(role);
        }

        CFTypeRef group_uuid = IORegistryEntryCreateCFProperty(
            service, CFSTR("VolGroupUUID"), kCFAllocatorDefault, 0);
        copy_string(group_uuid, item.vol_group_uuid,
                    sizeof(item.vol_group_uuid));
        if (group_uuid) {
            CFRelease(group_uuid);
        }

        CFTypeRef full_name = IORegistryEntryCreateCFProperty(
            service, CFSTR("FullName"), kCFAllocatorDefault, 0);
        copy_string(full_name, item.volume_name, sizeof(item.volume_name));
        if (full_name) {
            CFRelease(full_name);
        }

        io_name_t entry_name;
        if (IORegistryEntryGetName(service, entry_name) == KERN_SUCCESS) {
            strncpy(item.media_name, entry_name, sizeof(item.media_name) - 1);
        }

        char class_name[128];
        memset(class_name, 0, sizeof(class_name));
        copy_class(service, class_name, sizeof(class_name));

        io_registry_entry_t parent = copy_parent_media(service);
        if (parent) {
            CFTypeRef parent_name = IORegistryEntryCreateCFProperty(
                parent, CFSTR("BSD Name"), kCFAllocatorDefault, 0);
            copy_string(parent_name, item.parent_bsd_name,
                        sizeof(item.parent_bsd_name));
            if (parent_name) {
                CFRelease(parent_name);
            }
            IOObjectRelease(parent);
        }

        if (session) {
            DADiskRef disk = DADiskCreateFromIOMedia(kCFAllocatorDefault,
                                                     session, service);
            if (disk) {
                CFDictionaryRef description = DADiskCopyDescription(disk);
                if (description) {
                    CFTypeRef value = NULL;

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionVolumeNameKey);
                    if (value) {
                        copy_string(value, item.volume_name,
                                    sizeof(item.volume_name));
                    }

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionVolumeKindKey);
                    if (value) {
                        copy_string(value, item.file_system,
                                    sizeof(item.file_system));
                    }

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionVolumePathKey);
                    if (value) {
                        copy_string(value, item.mount_point,
                                    sizeof(item.mount_point));
                    }

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionVolumeUUIDKey);
                    if (value) {
                        copy_string(value, item.volume_uuid,
                                    sizeof(item.volume_uuid));
                    }

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionMediaNameKey);
                    if (value) {
                        char media_name[256];
                        copy_string(value, media_name, sizeof(media_name));
                        if (media_name[0] != '\0') {
                            strncpy(item.media_name, media_name,
                                    sizeof(item.media_name) - 1);
                        }
                    }

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionDeviceModelKey);
                    if (value) {
                        copy_string(value, item.device_model,
                                    sizeof(item.device_model));
                    }

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionDeviceProtocolKey);
                    if (value) {
                        copy_string(value, item.device_protocol,
                                    sizeof(item.device_protocol));
                    }

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionBusNameKey);
                    if (value) {
                        copy_string(value, item.bus_name,
                                    sizeof(item.bus_name));
                    }

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionDeviceInternalKey);
                    if (value) {
                        item.is_internal = copy_bool(value);
                    }

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionMediaRemovableKey);
                    if (value) {
                        item.is_removable = copy_bool(value);
                    }

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionMediaEjectableKey);
                    if (value) {
                        item.is_ejectable = copy_bool(value);
                    }

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionMediaWritableKey);
                    if (value) {
                        item.is_writable = copy_bool(value);
                    }

                    value = CFDictionaryGetValue(
                        description, kDADiskDescriptionMediaEncryptedKey);
                    if (value) {
                        item.is_encrypted = copy_bool(value);
                    }

                    CFRelease(description);
                }
                CFRelease(disk);
            }
        }

        if (item.volume_name[0] == '\0') {
            strncpy(item.volume_name, item.media_name,
                    sizeof(item.volume_name) - 1);
        }
        if (item.volume_uuid[0] == '\0') {
            strncpy(item.volume_uuid, item.media_uuid,
                    sizeof(item.volume_uuid) - 1);
        }

        item.is_apfs_container =
            (strcmp(class_name, "AppleAPFSMedia") == 0) ||
            (strcmp(item.content, KB_DISK_APFS_CONTAINER_CONTENT) == 0);
        item.is_apfs_volume =
            (strcmp(class_name, "AppleAPFSVolume") == 0) ||
            (item.roles[0] != '\0') ||
            (strcmp(item.file_system, "apfs") == 0);
        item.is_partition = !item.is_whole &&
                            !item.is_apfs_container &&
                            !item.is_apfs_volume;
        item.is_mounted = item.mount_point[0] != '\0';

        if (used == capacity) {
            size_t next_capacity = capacity == 0 ? 32 : capacity * 2;
            kb_disk_media *grown = (kb_disk_media *)realloc(
                items, next_capacity * sizeof(kb_disk_media));
            if (!grown) {
                failed = 1;
                IOObjectRelease(service);
                break;
            }
            items = grown;
            capacity = next_capacity;
        }
        items[used++] = item;

        IOObjectRelease(service);
    }

    IOObjectRelease(iterator);
    if (session) {
        CFRelease(session);
    }

    if (failed) {
        free(items);
        return -1;
    }

    struct statfs *mounts = NULL;
    int mount_count = getmntinfo(&mounts, MNT_NOWAIT);
    for (int index = 0; index < mount_count; index++) {
        const char *device = mounts[index].f_mntfromname;
        const char *bsd_name = device;
        if (strncmp(device, "/dev/", 5) == 0) {
            bsd_name = device + 5;
        }

        for (size_t item_index = 0; item_index < used; item_index++) {
            if (strcmp(items[item_index].bsd_name, bsd_name) != 0) {
                continue;
            }

            strncpy(items[item_index].mount_point,
                    mounts[index].f_mntonname,
                    sizeof(items[item_index].mount_point) - 1);
            items[item_index].mount_point[
                sizeof(items[item_index].mount_point) - 1] = '\0';

            if (items[item_index].file_system[0] == '\0') {
                strncpy(items[item_index].file_system,
                        mounts[index].f_fstypename,
                        sizeof(items[item_index].file_system) - 1);
            }

            fill_capacity_from_mount(&items[item_index], &mounts[index]);
            items[item_index].is_mounted = 1;
            break;
        }
    }

    /* APFS volumes share the container's free space. Propagate it upward. */
    for (size_t container_index = 0; container_index < used; container_index++) {
        if (!items[container_index].is_apfs_container) {
            continue;
        }
        for (size_t child_index = 0; child_index < used; child_index++) {
            if (!items[child_index].is_mounted) {
                continue;
            }
            if (strcmp(items[child_index].parent_bsd_name,
                       items[container_index].bsd_name) != 0) {
                continue;
            }
            items[container_index].volume_size_bytes =
                items[child_index].volume_size_bytes;
            items[container_index].free_bytes =
                items[child_index].free_bytes;
            items[container_index].available_bytes =
                items[child_index].available_bytes;
            items[container_index].used_bytes =
                items[container_index].volume_size_bytes >=
                    items[container_index].free_bytes
                ? items[container_index].volume_size_bytes -
                    items[container_index].free_bytes
                : 0;
            break;
        }
    }

    if (used == 0) {
        free(items);
        items = NULL;
    } else if (used < capacity) {
        kb_disk_media *shrunk = (kb_disk_media *)realloc(
            items, used * sizeof(kb_disk_media));
        if (shrunk) {
            items = shrunk;
        }
    }

    *out = items;
    *count = used;
    return 0;
}

void kb_disk_media_list_free(kb_disk_media *items)
{
    free(items);
}
