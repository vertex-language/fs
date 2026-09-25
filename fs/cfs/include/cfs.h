#ifndef CFS_H
#define CFS_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Error codes returned by cfs operations
enum {
    CFS_OK                   = 0,
    CFS_ERR_GENERIC          = -1,
    CFS_ERR_NOT_FOUND        = -2,
    CFS_ERR_ALREADY_EXISTS   = -3,
    CFS_ERR_PERMISSION       = -4,
    CFS_ERR_NOT_DIR          = -5,
    CFS_ERR_IS_DIR           = -6,
    CFS_ERR_DIR_NOT_EMPTY    = -7,
    CFS_ERR_READ_ONLY        = -8,
    CFS_ERR_NO_SPACE         = -9,
    CFS_ERR_TOO_MANY_OPEN    = -10,
    CFS_ERR_XDEV             = -11,
    CFS_ERR_INVALID_PATH     = -12,
    CFS_ERR_INTERRUPTED      = -13
};

// Open flags
enum {
    CFS_OPEN_READ        = 1 << 0,
    CFS_OPEN_WRITE       = 1 << 1,
    CFS_OPEN_APPEND      = 1 << 2,
    CFS_OPEN_CREATE      = 1 << 3,
    CFS_OPEN_TRUNCATE    = 1 << 4,
    CFS_OPEN_EXCL        = 1 << 5
};

// File kind
enum {
    CFS_KIND_FILE        = 1,
    CFS_KIND_DIRECTORY   = 2,
    CFS_KIND_SYMLINK     = 3,
    CFS_KIND_OTHER       = 4
};

#pragma pack(push, 8)
typedef struct {
    uint32_t kind;             // CFS_KIND_*
    int64_t  size;
    int64_t  mod_sec;
    int32_t  mod_nsec;
    int64_t  acc_sec;
    int32_t  acc_nsec;
    int64_t  birth_sec;
    int32_t  birth_nsec;
    uint32_t unix_mode;
    uint32_t unix_uid;
    uint32_t unix_gid;
    uint64_t unix_ino;
    uint64_t unix_dev;
    uint32_t win_attrs;
    int32_t  is_readonly;
} CFsMetadata;
#pragma pack(pop)

// Last OS error code (errno or GetLastError)
int32_t cfs_last_error(void);
int64_t cfs_now(int32_t* nanos);

// Batched whole-file operations
int32_t cfs_read_file(const char* path, uint8_t** out_buf, int64_t* out_len);
int32_t cfs_read_file_into(const char* path, void* buf, int64_t max_len, int64_t* out_read);
void    cfs_free_buffer(uint8_t* buf);
int32_t cfs_write_file(const char* path, const uint8_t* data, int64_t len, int32_t atomic);
int32_t cfs_append_file(const char* path, const uint8_t* data, int64_t len);

// File handle operations
int32_t cfs_open(const char* path, int32_t flags, uint32_t mode);
int32_t cfs_close(int32_t fd);
int64_t cfs_read(int32_t fd, void* buf, int32_t count);
int64_t cfs_pread(int32_t fd, void* buf, int32_t count, int64_t offset);
int64_t cfs_write(int32_t fd, const void* buf, int32_t count);
int64_t cfs_pwrite(int32_t fd, const void* buf, int32_t count, int64_t offset);
int64_t cfs_seek(int32_t fd, int64_t offset, int32_t whence);
int32_t cfs_truncate(int32_t fd, int64_t length);
int32_t cfs_sync(int32_t fd, int32_t data_only);

// Directory & relative operations
int32_t cfs_open_dir(const char* path, int32_t confined);
int32_t cfs_read_dir_records(int32_t dir_fd, uint8_t* out_buf, int32_t max_bytes,
                            int32_t* out_record_count, int32_t* out_bytes_written);
int32_t cfs_mkdir(const char* path, uint32_t mode, int32_t recursive);
int32_t cfs_remove(const char* path);
int32_t cfs_remove_all(const char* path);
int32_t cfs_rename(const char* src, const char* dst, int32_t replace);
int32_t cfs_copy_file(const char* src, const char* dst, int32_t overwrite);

// Metadata & path operations
int32_t cfs_stat(const char* path, int32_t follow_symlinks, CFsMetadata* out_meta);
int32_t cfs_fstat(int32_t fd, CFsMetadata* out_meta);
int32_t cfs_stat_raw(const char* path, int32_t follow_symlinks, int64_t* out_fields);
int32_t cfs_fstat_raw(int32_t fd, int64_t* out_fields);
int32_t cfs_canonical(const char* path, char* out_buf, int32_t max_len);
int32_t cfs_readlink(const char* path, char* out_buf, int32_t max_len);
int32_t cfs_symlink(const char* target, const char* link);
int32_t cfs_temp_dir(const char* prefix, char* out_buf, int32_t max_len);

// Memory mapping: the first len bytes of the open file fd, read-only and
// private, at *out_addr. The mapping outlives fd. len must be above zero.
int32_t cfs_map(int32_t fd, int64_t len, void** out_addr);
int32_t cfs_unmap(void* addr, int64_t len);

#ifdef __cplusplus
}
#endif

#endif // CFS_H
