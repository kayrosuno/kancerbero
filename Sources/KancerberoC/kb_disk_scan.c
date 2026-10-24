#include "KBDisk.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/attr.h>
#include <sys/vnode.h>
#include <unistd.h>

#define KB_DISK_BUFFER_SIZE (64 * 1024)
#define KB_DISK_NAME_MAX 256

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

/*
 * Parses one getattrlistbulk entry. The buffer layout is:
 *
 *   u32 length
 *   attribute_set_t returned
 *   [u32 error]            if ATTR_CMN_ERROR
 *   [attrreference_t name] if ATTR_CMN_NAME
 *   [u32 obj_type]         if ATTR_CMN_OBJTYPE
 *   dir group: [u32 mount_status] [u64 alloc_size]
 *   file group: [u64 total_size] [u64 alloc_size]
 *
 * Attributes are 4-byte aligned (including 64-bit values). Every requested
 * field is a multiple of four bytes, so sequential parsing needs no padding.
 */
static int parse_entry(const char *entry,
                       size_t available,
                       kb_disk_entry *out,
                       uint32_t *entry_length)
{
    if (available < sizeof(uint32_t) + sizeof(attribute_set_t)) {
        return EINVAL;
    }

    const char *base = entry;
    const char *end = entry + available;
    uint32_t length = read_u32(entry);
    if (length < sizeof(uint32_t) + sizeof(attribute_set_t) || length > available) {
        return EINVAL;
    }
    end = entry + length;

    memset(out, 0, sizeof(*out));

    const char *field = entry + sizeof(uint32_t);
    attribute_set_t returned;
    memcpy(&returned, field, sizeof(returned));
    field += sizeof(returned);

    if (returned.commonattr & ATTR_CMN_ERROR) {
        if (field + sizeof(uint32_t) > end) {
            return EINVAL;
        }
        uint32_t entry_error = read_u32(field);
        field += sizeof(uint32_t);
        if (entry_error != 0) {
            out->flags |= KB_DISK_FLAG_ERROR;
            *entry_length = length;
            return 0;
        }
    }

    if (returned.commonattr & ATTR_CMN_NAME) {
        if (field + sizeof(attrreference_t) > end) {
            return EINVAL;
        }
        const attrreference_t *name_reference = (const attrreference_t *)field;
        const char *name = (const char *)name_reference + name_reference->attr_dataoffset;
        size_t name_length = (size_t)name_reference->attr_length;
        if (name < base || name > end) {
            return EINVAL;
        }
        size_t maximum = (size_t)(end - name);
        if (name_length > maximum) {
            name_length = maximum;
        }
        if (name_length > KB_DISK_NAME_MAX - 1) {
            name_length = KB_DISK_NAME_MAX - 1;
        }
        memcpy(out->name, name, name_length);
        out->name[name_length] = '\0';
        field += sizeof(attrreference_t);
    }

    if (returned.commonattr & ATTR_CMN_OBJTYPE) {
        if (field + sizeof(uint32_t) > end) {
            return EINVAL;
        }
        out->obj_type = read_u32(field);
        field += sizeof(uint32_t);
    }

    if (returned.dirattr & ATTR_DIR_MOUNTSTATUS) {
        if (field + sizeof(uint32_t) > end) {
            return EINVAL;
        }
        out->mount_status = read_u32(field);
        field += sizeof(uint32_t);
    }

    if (returned.dirattr & ATTR_DIR_ALLOCSIZE) {
        if (field + sizeof(uint64_t) > end) {
            return EINVAL;
        }
        out->alloc_size = read_u64(field);
        field += sizeof(uint64_t);
    }

    if (returned.fileattr & ATTR_FILE_TOTALSIZE) {
        if (field + sizeof(uint64_t) > end) {
            return EINVAL;
        }
        out->total_size = read_u64(field);
        field += sizeof(uint64_t);
    }

    if (returned.fileattr & ATTR_FILE_ALLOCSIZE) {
        if (field + sizeof(uint64_t) > end) {
            return EINVAL;
        }
        out->alloc_size = read_u64(field);
        field += sizeof(uint64_t);
    }

    if (out->obj_type == VDIR) {
        out->flags |= KB_DISK_FLAG_DIRECTORY;
    } else if (out->obj_type == VLNK) {
        out->flags |= KB_DISK_FLAG_SYMLINK;
    }
    if (out->mount_status & DIR_MNTSTATUS_MNTPOINT) {
        out->flags |= KB_DISK_FLAG_MOUNT_POINT;
    }

    *entry_length = length;
    return 0;
}

int kb_disk_list_directory(const char *path, kb_disk_entry **out, size_t *count)
{
    if (!path || !out || !count) {
        return EINVAL;
    }
    *out = NULL;
    *count = 0;

    int descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (descriptor < 0) {
        return errno;
    }

    char *buffer = (char *)malloc(KB_DISK_BUFFER_SIZE);
    if (!buffer) {
        close(descriptor);
        return ENOMEM;
    }

    struct attrlist attributes;
    memset(&attributes, 0, sizeof(attributes));
    attributes.bitmapcount = ATTR_BIT_MAP_COUNT;
    attributes.commonattr = ATTR_CMN_RETURNED_ATTRS |
                            ATTR_CMN_ERROR |
                            ATTR_CMN_NAME |
                            ATTR_CMN_OBJTYPE;
    attributes.dirattr = ATTR_DIR_MOUNTSTATUS | ATTR_DIR_ALLOCSIZE;
    attributes.fileattr = ATTR_FILE_TOTALSIZE | ATTR_FILE_ALLOCSIZE;

    kb_disk_entry *entries = NULL;
    size_t capacity = 0;
    size_t used = 0;
    int result = 0;

    for (;;) {
        int entry_count = getattrlistbulk(descriptor, &attributes, buffer,
                                          KB_DISK_BUFFER_SIZE, FSOPT_NOFOLLOW);
        if (entry_count < 0) {
            result = errno;
            break;
        }
        if (entry_count == 0) {
            break;
        }

        const char *cursor = buffer;
        for (int index = 0; index < entry_count; index++) {
            size_t remaining = (size_t)((buffer + KB_DISK_BUFFER_SIZE) - cursor);
            kb_disk_entry entry;
            uint32_t length = 0;
            int parse_result = parse_entry(cursor, remaining, &entry, &length);
            if (parse_result != 0) {
                result = parse_result;
                break;
            }

            if (!(entry.flags & KB_DISK_FLAG_ERROR)) {
                if (used == capacity) {
                    size_t next_capacity = capacity == 0 ? 128 : capacity * 2;
                    kb_disk_entry *grown = (kb_disk_entry *)realloc(
                        entries, next_capacity * sizeof(kb_disk_entry));
                    if (!grown) {
                        result = ENOMEM;
                        break;
                    }
                    entries = grown;
                    capacity = next_capacity;
                }
                entries[used++] = entry;
            }

            cursor += length;
        }

        if (result != 0) {
            break;
        }
    }

    free(buffer);
    close(descriptor);

    if (result != 0) {
        free(entries);
        return result;
    }

    if (used == 0) {
        free(entries);
        entries = NULL;
    } else if (used < capacity) {
        kb_disk_entry *shrunk = (kb_disk_entry *)realloc(
            entries, used * sizeof(kb_disk_entry));
        if (shrunk) {
            entries = shrunk;
        }
    }

    *out = entries;
    *count = used;
    return 0;
}

void kb_disk_entries_free(kb_disk_entry *entries)
{
    free(entries);
}
