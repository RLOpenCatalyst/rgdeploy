/*
 * ponytail: S3 Files NFS xattr shim.
 *
 * GNOME Files (Nautilus) hangs on listxattr/getxattr calls against S3 Files
 * NFS mounts because the server-side never responds (xattr not supported).
 * This LD_PRELOAD shim returns immediately (empty / ENODATA) for any path
 * that resolves into a known s3files NFS mount.
 *
 * Known ceiling: per-process; won't cover suid helpers or already-running
 * GNOME daemons unless they are started with LD_PRELOAD in their environment
 * (see /etc/profile.d/rg-s3files-xattr.sh and the Nautilus .desktop override).
 * Upgrade path: remove when S3 Files client supports xattr no-op or Linux
 * nfs client acquires per-mount xattr-disable mount option.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_S3FILES_MOUNTS 64
#define MOUNT_PREFIX_MAX   512

static char s3files_mounts[MAX_S3FILES_MOUNTS][MOUNT_PREFIX_MAX];
static int  s3files_mount_count = 0;
static pthread_once_t init_once = PTHREAD_ONCE_INIT;

static void load_s3files_mounts(void) {
    FILE *fp = fopen("/proc/mounts", "r");
    if (!fp) {
        return;
    }
    char dev[256], mnt[512], fstype[64], opts[512];
    int  dummy1, dummy2;
    while (fscanf(fp, "%255s %511s %63s %511s %d %d\n",
                  dev, mnt, fstype, opts, &dummy1, &dummy2) == 6) {
        if (strcmp(fstype, "s3files") == 0 && s3files_mount_count < MAX_S3FILES_MOUNTS) {
            strncpy(s3files_mounts[s3files_mount_count], mnt, MOUNT_PREFIX_MAX - 1);
            s3files_mounts[s3files_mount_count][MOUNT_PREFIX_MAX - 1] = '\0';
            s3files_mount_count++;
        }
    }
    fclose(fp);
}

static void ensure_inited(void) {
    pthread_once(&init_once, load_s3files_mounts);
}

static int rg_is_s3files_path(const char *path) {
    if (!path) {
        return 0;
    }
    ensure_inited();
    for (int i = 0; i < s3files_mount_count; i++) {
        const char *mp = s3files_mounts[i];
        size_t len = strlen(mp);
        if (strncmp(path, mp, len) == 0 &&
            (path[len] == '\0' || path[len] == '/')) {
            return 1;
        }
    }
    /* Fallback: unresolved path that lands under studies/.s3files */
    return strstr(path, "studies/.s3files") != NULL;
}

static int rg_fd_is_s3files(int fd) {
    char link_path[64];
    char resolved[4096];
    ssize_t n;
    snprintf(link_path, sizeof(link_path), "/proc/self/fd/%d", fd);
    n = readlink(link_path, resolved, sizeof(resolved) - 1);
    if (n < 0) {
        return 0;
    }
    resolved[n] = '\0';
    return rg_is_s3files_path(resolved);
}

ssize_t listxattr(const char *path, char *list, size_t size) {
    if (rg_is_s3files_path(path)) {
        return 0;
    }
    ssize_t (*real)(const char *, char *, size_t) = dlsym(RTLD_NEXT, "listxattr");
    return real(path, list, size);
}

ssize_t llistxattr(const char *path, char *list, size_t size) {
    if (rg_is_s3files_path(path)) {
        return 0;
    }
    ssize_t (*real)(const char *, char *, size_t) = dlsym(RTLD_NEXT, "llistxattr");
    return real(path, list, size);
}

ssize_t flistxattr(int fd, char *list, size_t size) {
    if (rg_fd_is_s3files(fd)) {
        return 0;
    }
    ssize_t (*real)(int, char *, size_t) = dlsym(RTLD_NEXT, "flistxattr");
    return real(fd, list, size);
}

ssize_t getxattr(const char *path, const char *name, void *value, size_t size) {
    if (rg_is_s3files_path(path)) {
        errno = ENODATA;
        return -1;
    }
    ssize_t (*real)(const char *, const char *, void *, size_t) =
        dlsym(RTLD_NEXT, "getxattr");
    return real(path, name, value, size);
}

ssize_t lgetxattr(const char *path, const char *name, void *value, size_t size) {
    if (rg_is_s3files_path(path)) {
        errno = ENODATA;
        return -1;
    }
    ssize_t (*real)(const char *, const char *, void *, size_t) =
        dlsym(RTLD_NEXT, "lgetxattr");
    return real(path, name, value, size);
}

ssize_t fgetxattr(int fd, const char *name, void *value, size_t size) {
    if (rg_fd_is_s3files(fd)) {
        errno = ENODATA;
        return -1;
    }
    ssize_t (*real)(int, const char *, void *, size_t) =
        dlsym(RTLD_NEXT, "fgetxattr");
    return real(fd, name, value, size);
}
