#ifndef KB_DISK_H
#define KB_DISK_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Directory scanning (getattrlistbulk).
 *
 * One call per directory: the Swift scanner drives the traversal and can
 * cancel between directories. Names are UTF-8 basenames; no file content is
 * ever read.
 */

enum {
    KB_DISK_FLAG_DIRECTORY   = 1u << 0,
    KB_DISK_FLAG_SYMLINK     = 1u << 1,
    KB_DISK_FLAG_MOUNT_POINT = 1u << 2,
    KB_DISK_FLAG_ERROR       = 1u << 3,
};

typedef struct {
    char     name[256];
    uint32_t obj_type;
    uint32_t flags;
    uint32_t mount_status;
    uint64_t total_size;   /* ATTR_FILE_TOTALSIZE, 0 for directories */
    uint64_t alloc_size;   /* ATTR_FILE_ALLOCSIZE / ATTR_DIR_ALLOCSIZE */
} kb_disk_entry;

/* Returns 0 on success, or the errno from open/getattrlistbulk. */
int kb_disk_list_directory(const char *path, kb_disk_entry **out, size_t *count);
void kb_disk_entries_free(kb_disk_entry *entries);

/*
 * Medium inventory (IOKit + DiskArbitration + getmntinfo + getattrlist).
 *
 * The result is a flat list; parent_bsd_name reconstructs the IORegistry
 * hierarchy (disk -> partition -> APFS container -> APFS volume).
 */

typedef struct {
    char     bsd_name[32];
    char     parent_bsd_name[32];
    char     media_name[256];
    char     volume_name[256];
    char     content[64];
    char     file_system[32];
    char     mount_point[1024];
    char     volume_uuid[64];
    char     media_uuid[64];
    char     vol_group_uuid[64];
    char     roles[128];
    char     device_model[128];
    char     device_protocol[64];
    char     bus_name[128];
    uint32_t role_value;
    uint64_t size_bytes;          /* IOMedia Size */
    uint64_t volume_size_bytes;   /* ATTR_VOL_SIZE of the mounted volume */
    uint64_t free_bytes;          /* ATTR_VOL_SPACEFREE */
    uint64_t available_bytes;     /* ATTR_VOL_SPACEAVAIL */
    uint64_t used_bytes;          /* ATTR_VOL_SPACEUSED (per APFS volume) */
    uint8_t  is_whole;
    uint8_t  is_leaf;
    uint8_t  is_writable;
    uint8_t  is_removable;
    uint8_t  is_ejectable;
    uint8_t  is_internal;
    uint8_t  is_encrypted;
    uint8_t  is_mounted;
    uint8_t  is_apfs_container;
    uint8_t  is_apfs_volume;
    uint8_t  is_partition;
} kb_disk_media;

/* Returns 0 on success, or -1 when IOKit cannot be queried. */
int kb_disk_media_list(kb_disk_media **out, size_t *count);
void kb_disk_media_list_free(kb_disk_media *items);

#ifdef __cplusplus
}
#endif

#endif
