#include "KBDisk.h"

#include <sys/attr.h>
#include <sys/mount.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Match df's byte accounting while protecting malformed/huge counters. */
static uint64_t block_bytes(uint64_t blocks, uint64_t block_size)
{
    return blocks > UINT64_MAX / block_size
        ? UINT64_MAX : blocks * block_size;
}

int kb_filesystem_list(kb_filesystem **out, size_t *count)
{
    if (!out || !count) {
        return EINVAL;
    }
    *out = NULL;
    *count = 0;

    /* getmntinfo uses a process-global buffer, also used by the volume
     * collector. Use its underlying API with owned storage instead. NOWAIT
     * avoids hanging the whole snapshot on an unavailable network server. */
    int capacity = getfsstat(NULL, 0, MNT_NOWAIT);
    if (capacity < 0) {
        return errno;
    }
    struct statfs *mounts = NULL;
    int mounted = 0;
    for (int attempt = 0; attempt < 4; attempt++) {
        if (capacity > INT_MAX / (int)sizeof(*mounts) - 16) {
            return EOVERFLOW;
        }
        capacity += 16;
        mounts = calloc((size_t)capacity, sizeof(*mounts));
        if (!mounts) {
            return ENOMEM;
        }
        mounted = getfsstat(mounts, capacity * (int)sizeof(*mounts), MNT_NOWAIT);
        if (mounted < 0) {
            int error = errno;
            free(mounts);
            return error;
        }
        if (mounted < capacity) {
            break;
        }
        free(mounts);
        mounts = NULL;
        capacity = mounted;
    }
    if (!mounts) {
        return EAGAIN;
    }

    kb_filesystem *items = calloc((size_t)mounted, sizeof(*items));
    if (!items && mounted > 0) {
        free(mounts);
        return ENOMEM;
    }

    for (int index = 0; index < mounted; index++) {
        struct statfs mount = mounts[index];
        kb_filesystem *item = &items[index];
        strlcpy(item->filesystem, mount.f_mntfromname, sizeof(item->filesystem));
        strlcpy(item->file_system, mount.f_fstypename, sizeof(item->file_system));
        strlcpy(item->mount_point, mount.f_mntonname, sizeof(item->mount_point));
        item->is_cached = !(mount.f_flags & MNT_LOCAL)
            || strcmp(mount.f_fstypename, "autofs") == 0;

        if (!item->is_cached) {
            struct statfs fresh;
            if (statfs(mount.f_mntonname, &fresh) == 0) {
                /* An unmount may have exposed the parent filesystem. Do not
                 * publish the parent's counters under the old mount's name. */
                if (memcmp(&mount.f_fsid, &fresh.f_fsid, sizeof(mount.f_fsid)) == 0
                    && strcmp(fresh.f_mntonname, item->mount_point) == 0) {
                    mount = fresh;
                } else {
                    item->stats_error = ESTALE;
                }
            } else {
                item->stats_error = errno;
            }
        }

        uint64_t block_size = mount.f_bsize ? mount.f_bsize : 512;
        uint64_t used_blocks = mount.f_blocks > mount.f_bfree
            ? mount.f_blocks - mount.f_bfree : 0;
        item->size_bytes = block_bytes(mount.f_blocks, block_size);
        item->used_bytes = block_bytes(used_blocks, block_size);
        item->available_bytes = block_bytes(mount.f_bavail, block_size);
        item->inode_count = mount.f_files;
        item->free_inodes = mount.f_ffree;
        item->is_read_only = (mount.f_flags & MNT_RDONLY) != 0;

        /* Apple's df asks for ATTR_VOL_SPACEUSED rather than size - free:
         * APFS volumes share free space but report their own used space.
         * Only query accessible local mounts. Remote rows retain the kernel's
         * cached counters, explicitly marked as such by the UI. */
        if (!item->is_cached && !item->stats_error && used_blocks > 0) {
            struct attrlist attributes = {0};
            attributes.bitmapcount = ATTR_BIT_MAP_COUNT;
            attributes.volattr = ATTR_VOL_INFO | ATTR_VOL_SPACEUSED;
            unsigned char buffer[sizeof(uint32_t) + sizeof(uint64_t)] = {0};
            if (getattrlist(item->mount_point, &attributes, buffer,
                            sizeof(buffer), 0) == 0) {
                uint32_t length;
                uint64_t used_bytes;
                memcpy(&length, buffer, sizeof(length));
                if (length >= sizeof(buffer)) {
                    memcpy(&used_bytes, buffer + sizeof(length), sizeof(used_bytes));
                    /* df truncates to whole filesystem blocks. */
                    item->used_bytes = used_bytes / block_size * block_size;
                } else {
                    item->used_space_error = EIO;
                }
            } else if (errno != EINVAL && errno != ENOTSUP) {
                item->used_space_error = errno;
            }
        }
    }
    free(mounts);
    *out = items;
    *count = (size_t)mounted;
    return 0;
}

void kb_filesystem_list_free(kb_filesystem *items)
{
    free(items);
}
