#include "cfs.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
    #define WIN32_LEAN_AND_MEAN
    #include <windows.h>
    #include <io.h>
    #include <direct.h>
#else
    #include <unistd.h>
    #include <fcntl.h>
    #include <sys/types.h>
    #include <sys/stat.h>
    #include <dirent.h>
    #include <time.h>
    #include <sys/time.h>
    #include <errno.h>
    #if defined(__APPLE__)
        #include <sys/clonefile.h>
        #include <copyfile.h>
    #endif
#endif

extern "C" {

#if defined(_WIN32)
static int map_error(DWORD err) {
    switch (err) {
        case ERROR_FILE_NOT_FOUND:
        case ERROR_PATH_NOT_FOUND:     return CFS_ERR_NOT_FOUND;
        case ERROR_FILE_EXISTS:
        case ERROR_ALREADY_EXISTS:     return CFS_ERR_ALREADY_EXISTS;
        case ERROR_ACCESS_DENIED:      return CFS_ERR_PERMISSION;
        case ERROR_DIR_NOT_EMPTY:      return CFS_ERR_DIR_NOT_EMPTY;
        case ERROR_NOT_ENOUGH_MEMORY:
        case ERROR_DISK_FULL:          return CFS_ERR_NO_SPACE;
        case ERROR_TOO_MANY_OPEN_FILES:return CFS_ERR_TOO_MANY_OPEN;
        case ERROR_NOT_SAME_DEVICE:    return CFS_ERR_XDEV;
        case ERROR_BAD_PATHNAME:       return CFS_ERR_INVALID_PATH;
        default:                       return CFS_ERR_GENERIC;
    }
}
#else
static int map_error(int err) {
    switch (err) {
        case ENOENT:       return CFS_ERR_NOT_FOUND;
        case EEXIST:       return CFS_ERR_ALREADY_EXISTS;
        case EACCES:
        case EPERM:        return CFS_ERR_PERMISSION;
        case ENOTDIR:      return CFS_ERR_NOT_DIR;
        case EISDIR:       return CFS_ERR_IS_DIR;
        case ENOTEMPTY:    return CFS_ERR_DIR_NOT_EMPTY;
        case EROFS:        return CFS_ERR_READ_ONLY;
        case ENOSPC:
        case EDQUOT:       return CFS_ERR_NO_SPACE;
        case EMFILE:
        case ENFILE:       return CFS_ERR_TOO_MANY_OPEN;
        case EXDEV:        return CFS_ERR_XDEV;
        case EINTR:        return CFS_ERR_INTERRUPTED;
        default:           return CFS_ERR_GENERIC;
    }
}
#endif

#if !defined(_WIN32)
static void fill_metadata(const struct stat* st, CFsMetadata* out) {
    if (!out || !st) return;
    memset(out, 0, sizeof(*out));

    if (S_ISREG(st->st_mode)) {
        out->kind = CFS_KIND_FILE;
    } else if (S_ISDIR(st->st_mode)) {
        out->kind = CFS_KIND_DIRECTORY;
    } else if (S_ISLNK(st->st_mode)) {
        out->kind = CFS_KIND_SYMLINK;
    } else {
        out->kind = CFS_KIND_OTHER;
    }

    out->size = st->st_size;
    out->mod_sec = st->st_mtime;
#if defined(__APPLE__)
    out->mod_nsec = (int32_t)st->st_mtimespec.tv_nsec;
    out->acc_sec = st->st_atime;
    out->acc_nsec = (int32_t)st->st_atimespec.tv_nsec;
    out->birth_sec = st->st_birthtime;
    out->birth_nsec = (int32_t)st->st_birthtimespec.tv_nsec;
#else
    out->mod_nsec = (int32_t)st->st_mtim.tv_nsec;
    out->acc_sec = st->st_atime;
    out->acc_nsec = (int32_t)st->st_atim.tv_nsec;
    out->birth_sec = 0;
    out->birth_nsec = 0;
#endif
    out->unix_mode = (uint32_t)st->st_mode;
    out->unix_uid = (uint32_t)st->st_uid;
    out->unix_gid = (uint32_t)st->st_gid;
    out->unix_ino = (uint64_t)st->st_ino;
    out->unix_dev = (uint64_t)st->st_dev;
    // Read-only where no one may write it, by its mode.
    out->is_readonly = (out->unix_mode & 0222) == 0;
}
#endif

int32_t cfs_last_error(void) {
#if defined(_WIN32)
    return (int32_t)GetLastError();
#else
    return (int32_t)errno;
#endif
}

int64_t cfs_now(int32_t* nanos) {
#if defined(_WIN32)
    FILETIME ft;
    GetSystemTimePreciseAsFileTime(&ft);
    int64_t ticks = ((int64_t)ft.dwHighDateTime << 32 | ft.dwLowDateTime) - 116444736000000000LL;
    int64_t secs = ticks / 10000000;
    int64_t rem = ticks % 10000000;
    if (rem < 0) { rem += 10000000; secs -= 1; }
    if (nanos) *nanos = (int32_t)(rem * 100);
    return secs;
#else
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    if (nanos) *nanos = (int32_t)ts.tv_nsec;
    return (int64_t)ts.tv_sec;
#endif
}

int32_t cfs_read_file(const char* path, uint8_t** out_buf, int64_t* out_len) {
    if (!path || !out_buf || !out_len) {
        return CFS_ERR_INVALID_PATH;
    }
    *out_buf = nullptr;
    *out_len = 0;

#if defined(_WIN32)
    HANDLE h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) {
        return map_error(GetLastError());
    }
    LARGE_INTEGER sz;
    if (!GetFileSizeEx(h, &sz)) {
        CloseHandle(h);
        return map_error(GetLastError());
    }
    int64_t total = sz.QuadPart;
    uint8_t* buf = (uint8_t*)malloc((size_t)(total > 0 ? total : 1));
    if (!buf) {
        CloseHandle(h);
        return CFS_ERR_NO_SPACE;
    }
    DWORD read_bytes = 0;
    if (total > 0 && !ReadFile(h, buf, (DWORD)total, &read_bytes, NULL)) {
        free(buf);
        CloseHandle(h);
        return map_error(GetLastError());
    }
    CloseHandle(h);
    *out_buf = buf;
    *out_len = read_bytes;
    return CFS_OK;
#else
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        return map_error(errno);
    }
    struct stat st;
    if (fstat(fd, &st) < 0) {
        close(fd);
        return map_error(errno);
    }
    int64_t total = st.st_size;
    uint8_t* buf = (uint8_t*)malloc((size_t)(total > 0 ? total : 1));
    if (!buf) {
        close(fd);
        return CFS_ERR_NO_SPACE;
    }
    int64_t read_bytes = 0;
    while (read_bytes < total) {
        ssize_t n = read(fd, buf + read_bytes, (size_t)(total - read_bytes));
        if (n < 0) {
            if (errno == EINTR) continue;
            free(buf);
            close(fd);
            return map_error(errno);
        }
        if (n == 0) break;
        read_bytes += n;
    }
    close(fd);
    *out_buf = buf;
    *out_len = read_bytes;
    return CFS_OK;
#endif
}

void cfs_free_buffer(uint8_t* buf) {
    if (buf) free(buf);
}

int32_t cfs_read_file_into(const char* path, void* buf, int64_t max_len, int64_t* out_read) {
    if (!path || !buf || !out_read) return CFS_ERR_INVALID_PATH;
    *out_read = 0;
#if !defined(_WIN32)
    int fd = open(path, O_RDONLY);
    if (fd < 0) return map_error(errno);
    int64_t total = 0;
    while (total < max_len) {
        ssize_t n = read(fd, (char*)buf + total, (size_t)(max_len - total));
        if (n < 0) {
            if (errno == EINTR) continue;
            int err = errno;
            close(fd);
            return map_error(err);
        }
        if (n == 0) break;
        total += n;
    }
    close(fd);
    *out_read = total;
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_write_file(const char* path, const uint8_t* data, int64_t len, int32_t atomic) {
    if (!path) return CFS_ERR_INVALID_PATH;

#if !defined(_WIN32)
    if (atomic) {
        char temp_path[1024];
        snprintf(temp_path, sizeof(temp_path), "%s.tmp.XXXXXX", path);
        int fd = mkstemp(temp_path);
        if (fd < 0) {
            return map_error(errno);
        }
        int64_t written = 0;
        while (written < len) {
            ssize_t n = write(fd, data + written, (size_t)(len - written));
            if (n < 0) {
                if (errno == EINTR) continue;
                close(fd);
                unlink(temp_path);
                return map_error(errno);
            }
            written += n;
        }
#if defined(__APPLE__)
        fcntl(fd, F_FULLFSYNC);
#else
        fsync(fd);
#endif
        close(fd);

        if (rename(temp_path, path) < 0) {
            int err = errno;
            unlink(temp_path);
            return map_error(err);
        }
        return CFS_OK;
    } else {
        int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
        if (fd < 0) return map_error(errno);
        int64_t written = 0;
        while (written < len) {
            ssize_t n = write(fd, data + written, (size_t)(len - written));
            if (n < 0) {
                if (errno == EINTR) continue;
                close(fd);
                return map_error(errno);
            }
            written += n;
        }
        close(fd);
        return CFS_OK;
    }
#else
    HANDLE h = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return map_error(GetLastError());
    DWORD written = 0;
    if (len > 0 && !WriteFile(h, data, (DWORD)len, &written, NULL)) {
        CloseHandle(h);
        return map_error(GetLastError());
    }
    CloseHandle(h);
    return CFS_OK;
#endif
}

int32_t cfs_append_file(const char* path, const uint8_t* data, int64_t len) {
    if (!path) return CFS_ERR_INVALID_PATH;

#if !defined(_WIN32)
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) return map_error(errno);
    int64_t written = 0;
    while (written < len) {
        ssize_t n = write(fd, data + written, (size_t)(len - written));
        if (n < 0) {
            if (errno == EINTR) continue;
            close(fd);
            return map_error(errno);
        }
        written += n;
    }
    close(fd);
    return CFS_OK;
#else
    HANDLE h = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return map_error(GetLastError());
    DWORD written = 0;
    if (len > 0 && !WriteFile(h, data, (DWORD)len, &written, NULL)) {
        CloseHandle(h);
        return map_error(GetLastError());
    }
    CloseHandle(h);
    return CFS_OK;
#endif
}

int32_t cfs_open(const char* path, int32_t flags, uint32_t mode) {
    if (!path) return CFS_ERR_INVALID_PATH;

#if !defined(_WIN32)
    int posix_flags = 0;
    if ((flags & CFS_OPEN_READ) && (flags & CFS_OPEN_WRITE)) {
        posix_flags |= O_RDWR;
    } else if (flags & CFS_OPEN_WRITE) {
        posix_flags |= O_WRONLY;
    } else {
        posix_flags |= O_RDONLY;
    }

    if (flags & CFS_OPEN_APPEND)   posix_flags |= O_APPEND;
    if (flags & CFS_OPEN_CREATE)   posix_flags |= O_CREAT;
    if (flags & CFS_OPEN_TRUNCATE) posix_flags |= O_TRUNC;
    if (flags & CFS_OPEN_EXCL)     posix_flags |= O_EXCL;

    if (mode == 0) mode = 0666;

    int fd = open(path, posix_flags, (mode_t)mode);
    if (fd < 0) return map_error(errno);
    return fd;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_close(int32_t fd) {
#if !defined(_WIN32)
    if (close(fd) < 0) return map_error(errno);
    return CFS_OK;
#else
    return CFS_OK;
#endif
}

int64_t cfs_read(int32_t fd, void* buf, int32_t count) {
#if !defined(_WIN32)
    ssize_t n = read(fd, buf, (size_t)count);
    if (n < 0) return map_error(errno);
    return (int64_t)n;
#else
    return CFS_ERR_GENERIC;
#endif
}

int64_t cfs_pread(int32_t fd, void* buf, int32_t count, int64_t offset) {
#if !defined(_WIN32)
    ssize_t n = pread(fd, buf, (size_t)count, (off_t)offset);
    if (n < 0) return map_error(errno);
    return (int64_t)n;
#else
    return CFS_ERR_GENERIC;
#endif
}

int64_t cfs_write(int32_t fd, const void* buf, int32_t count) {
#if !defined(_WIN32)
    ssize_t n = write(fd, buf, (size_t)count);
    if (n < 0) return map_error(errno);
    return (int64_t)n;
#else
    return CFS_ERR_GENERIC;
#endif
}

int64_t cfs_pwrite(int32_t fd, const void* buf, int32_t count, int64_t offset) {
#if !defined(_WIN32)
    ssize_t n = pwrite(fd, buf, (size_t)count, (off_t)offset);
    if (n < 0) return map_error(errno);
    return (int64_t)n;
#else
    return CFS_ERR_GENERIC;
#endif
}

int64_t cfs_seek(int32_t fd, int64_t offset, int32_t whence) {
#if !defined(_WIN32)
    int posix_whence = SEEK_SET;
    if (whence == 1) posix_whence = SEEK_CUR;
    else if (whence == 2) posix_whence = SEEK_END;
    off_t pos = lseek(fd, (off_t)offset, posix_whence);
    if (pos < 0) return map_error(errno);
    return (int64_t)pos;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_truncate(int32_t fd, int64_t length) {
#if !defined(_WIN32)
    if (ftruncate(fd, (off_t)length) < 0) return map_error(errno);
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_sync(int32_t fd, int32_t data_only) {
#if !defined(_WIN32)
#if defined(__APPLE__)
    if (fcntl(fd, F_FULLFSYNC) < 0) return map_error(errno);
#else
    if (data_only) {
        if (fdatasync(fd) < 0) return map_error(errno);
    } else {
        if (fsync(fd) < 0) return map_error(errno);
    }
#endif
    return CFS_OK;
#else
    return CFS_OK;
#endif
}

int32_t cfs_open_dir(const char* path, int32_t confined) {
    if (!path) return CFS_ERR_INVALID_PATH;
#if !defined(_WIN32)
    int fd = open(path, O_RDONLY | O_DIRECTORY);
    if (fd < 0) return map_error(errno);
    return fd;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_read_dir_records(int32_t dir_fd, uint8_t* out_buf, int32_t max_bytes,
                            int32_t* out_record_count, int32_t* out_bytes_written) {
    if (!out_buf || !out_record_count || !out_bytes_written) return CFS_ERR_GENERIC;
    *out_record_count = 0;
    *out_bytes_written = 0;

#if !defined(_WIN32)
    int dup_fd = dup(dir_fd);
    if (dup_fd < 0) return map_error(errno);
    DIR* dir = fdopendir(dup_fd);
    if (!dir) {
        close(dup_fd);
        return map_error(errno);
    }

    struct dirent* entry;
    int32_t count = 0;
    int32_t offset = 0;

    while ((entry = readdir(dir)) != nullptr) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }

        size_t name_len = strlen(entry->d_name);
        if (name_len > 65535) continue;
        size_t record_len = 2 + name_len + 1; // len(2) + name + kind(1)

        if (offset + (int32_t)record_len > max_bytes) {
            break;
        }

        // Write uint16 length (little endian)
        uint16_t nl = (uint16_t)name_len;
        out_buf[offset++] = (uint8_t)(nl & 0xFF);
        out_buf[offset++] = (uint8_t)((nl >> 8) & 0xFF);

        // Write name
        memcpy(out_buf + offset, entry->d_name, name_len);
        offset += (int32_t)name_len;

        // Write kind
        uint8_t kind = CFS_KIND_OTHER;
#if defined(DT_DIR)
        if (entry->d_type == DT_DIR) kind = CFS_KIND_DIRECTORY;
        else if (entry->d_type == DT_REG) kind = CFS_KIND_FILE;
        else if (entry->d_type == DT_LNK) kind = CFS_KIND_SYMLINK;
#endif
        out_buf[offset++] = kind;
        count++;
    }

    closedir(dir);
    *out_record_count = count;
    *out_bytes_written = offset;
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_mkdir(const char* path, uint32_t mode, int32_t recursive) {
    if (!path) return CFS_ERR_INVALID_PATH;
    if (mode == 0) mode = 0777;

#if !defined(_WIN32)
    if (!recursive) {
        if (mkdir(path, (mode_t)mode) < 0) return map_error(errno);
        return CFS_OK;
    }

    char tmp[1024];
    size_t len = strlen(path);
    if (len >= sizeof(tmp)) return CFS_ERR_INVALID_PATH;
    memcpy(tmp, path, len + 1);

    for (char* p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            if (mkdir(tmp, (mode_t)mode) < 0 && errno != EEXIST) {
                return map_error(errno);
            }
            *p = '/';
        }
    }
    if (mkdir(tmp, (mode_t)mode) < 0 && errno != EEXIST) {
        return map_error(errno);
    }
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_remove(const char* path) {
    if (!path) return CFS_ERR_INVALID_PATH;
#if !defined(_WIN32)
    if (unlink(path) == 0) return CFS_OK;
    if (errno == EPERM || errno == EISDIR) {
        if (rmdir(path) == 0) return CFS_OK;
    }
    return map_error(errno);
#else
    return CFS_ERR_GENERIC;
#endif
}

static int remove_all_internal(const char* path) {
#if !defined(_WIN32)
    struct stat st;
    if (lstat(path, &st) < 0) return map_error(errno);

    if (!S_ISDIR(st.st_mode)) {
        if (unlink(path) < 0) return map_error(errno);
        return CFS_OK;
    }

    DIR* dir = opendir(path);
    if (!dir) return map_error(errno);

    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        char child[1024];
        snprintf(child, sizeof(child), "%s/%s", path, entry->d_name);
        int rc = remove_all_internal(child);
        if (rc != CFS_OK) {
            closedir(dir);
            return rc;
        }
    }
    closedir(dir);
    if (rmdir(path) < 0) return map_error(errno);
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_remove_all(const char* path) {
    if (!path) return CFS_ERR_INVALID_PATH;
    return remove_all_internal(path);
}

int32_t cfs_rename(const char* src, const char* dst, int32_t replace) {
    if (!src || !dst) return CFS_ERR_INVALID_PATH;
#if !defined(_WIN32)
    if (!replace) {
        struct stat st;
        if (lstat(dst, &st) == 0) return CFS_ERR_ALREADY_EXISTS;
    }
    if (rename(src, dst) < 0) return map_error(errno);
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_copy_file(const char* src, const char* dst, int32_t overwrite) {
    if (!src || !dst) return CFS_ERR_INVALID_PATH;

#if defined(__APPLE__)
    if (!overwrite) {
        struct stat st;
        if (lstat(dst, &st) == 0) return CFS_ERR_ALREADY_EXISTS;
    } else {
        unlink(dst);
    }
    if (clonefile(src, dst, 0) == 0) {
        return CFS_OK;
    }
    // Fallback if clonefile fails (e.g. cross-filesystem)
#endif

#if !defined(_WIN32)
    int src_fd = open(src, O_RDONLY);
    if (src_fd < 0) return map_error(errno);

    int dst_flags = O_WRONLY | O_CREAT | (overwrite ? O_TRUNC : O_EXCL);
    int dst_fd = open(dst, dst_flags, 0666);
    if (dst_fd < 0) {
        int err = errno;
        close(src_fd);
        return map_error(err);
    }

    char buf[65536];
    while (true) {
        ssize_t n = read(src_fd, buf, sizeof(buf));
        if (n < 0) {
            if (errno == EINTR) continue;
            int err = errno;
            close(src_fd);
            close(dst_fd);
            return map_error(err);
        }
        if (n == 0) break;

        ssize_t written = 0;
        while (written < n) {
            ssize_t w = write(dst_fd, buf + written, (size_t)(n - written));
            if (w < 0) {
                if (errno == EINTR) continue;
                int err = errno;
                close(src_fd);
                close(dst_fd);
                return map_error(err);
            }
            written += w;
        }
    }
    close(src_fd);
    close(dst_fd);
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

static void fill_raw_fields(const CFsMetadata* meta, int64_t* out) {
    if (!out || !meta) return;
    out[0]  = (int64_t)meta->kind;
    out[1]  = meta->size;
    out[2]  = meta->mod_sec;
    out[3]  = (int64_t)meta->mod_nsec;
    out[4]  = meta->acc_sec;
    out[5]  = (int64_t)meta->acc_nsec;
    out[6]  = meta->birth_sec;
    out[7]  = (int64_t)meta->birth_nsec;
    out[8]  = (int64_t)meta->unix_mode;
    out[9]  = (int64_t)meta->unix_uid;
    out[10] = (int64_t)meta->unix_gid;
    out[11] = (int64_t)meta->unix_ino;
    out[12] = (int64_t)meta->unix_dev;
    out[13] = (int64_t)meta->is_readonly;
}

int32_t cfs_stat(const char* path, int32_t follow_symlinks, CFsMetadata* out_meta) {
    if (!path || !out_meta) return CFS_ERR_INVALID_PATH;

#if !defined(_WIN32)
    struct stat st;
    int rc = follow_symlinks ? stat(path, &st) : lstat(path, &st);
    if (rc < 0) return map_error(errno);
    fill_metadata(&st, out_meta);
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_fstat(int32_t fd, CFsMetadata* out_meta) {
    if (!out_meta) return CFS_ERR_GENERIC;

#if !defined(_WIN32)
    struct stat st;
    if (fstat(fd, &st) < 0) return map_error(errno);
    fill_metadata(&st, out_meta);
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_stat_raw(const char* path, int32_t follow_symlinks, int64_t* out_fields) {
    if (!path || !out_fields) return CFS_ERR_INVALID_PATH;
    CFsMetadata meta;
    int32_t rc = cfs_stat(path, follow_symlinks, &meta);
    if (rc != CFS_OK) return rc;
    fill_raw_fields(&meta, out_fields);
    return CFS_OK;
}

int32_t cfs_fstat_raw(int32_t fd, int64_t* out_fields) {
    if (!out_fields) return CFS_ERR_GENERIC;
    CFsMetadata meta;
    int32_t rc = cfs_fstat(fd, &meta);
    if (rc != CFS_OK) return rc;
    fill_raw_fields(&meta, out_fields);
    return CFS_OK;
}

int32_t cfs_canonical(const char* path, char* out_buf, int32_t max_len) {
    if (!path || !out_buf || max_len <= 0) return CFS_ERR_INVALID_PATH;
#if !defined(_WIN32)
    char resolved[1024];
    if (!realpath(path, resolved)) return map_error(errno);
    size_t len = strlen(resolved);
    if ((int32_t)len >= max_len) return CFS_ERR_NO_SPACE;
    memcpy(out_buf, resolved, len + 1);
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_readlink(const char* path, char* out_buf, int32_t max_len) {
    if (!path || !out_buf || max_len <= 0) return CFS_ERR_INVALID_PATH;
#if !defined(_WIN32)
    ssize_t n = readlink(path, out_buf, (size_t)(max_len - 1));
    if (n < 0) return map_error(errno);
    out_buf[n] = '\0';
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_symlink(const char* target, const char* link) {
    if (!target || !link) return CFS_ERR_INVALID_PATH;
#if !defined(_WIN32)
    if (symlink(target, link) < 0) return map_error(errno);
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

int32_t cfs_temp_dir(const char* prefix, char* out_buf, int32_t max_len) {
    if (!out_buf || max_len <= 0) return CFS_ERR_GENERIC;
#if !defined(_WIN32)
    const char* base = getenv("TMPDIR");
    if (!base || strlen(base) == 0) base = "/tmp";
    size_t base_len = strlen(base);
    char template_buf[1024];
    if (base[base_len - 1] == '/') {
        snprintf(template_buf, sizeof(template_buf), "%s%sXXXXXX", base, prefix ? prefix : "vertex_fs_");
    } else {
        snprintf(template_buf, sizeof(template_buf), "%s/%sXXXXXX", base, prefix ? prefix : "vertex_fs_");
    }
    char* res = mkdtemp(template_buf);
    if (!res) return map_error(errno);
    size_t len = strlen(template_buf);
    if ((int32_t)len >= max_len) return CFS_ERR_NO_SPACE;
    memcpy(out_buf, template_buf, len + 1);
    return CFS_OK;
#else
    return CFS_ERR_GENERIC;
#endif
}

} // extern "C"
