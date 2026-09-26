// The operating system's file mapping, for package fs/mmap.
module;
#include <stdint.h>
#include <stddef.h>
#if defined(_WIN32)
    #define WIN32_LEAN_AND_MEAN
    #include <windows.h>
    #include <io.h>
#else
    #include <errno.h>
    #include <sys/mman.h>
#endif
export module fs.mmap;

// map maps len bytes of the file fd, read-only and shared, into *out:
// 0, or a negative errno (a Windows error on Windows).
export int32_t map(int32_t fd, int64_t len, void** out) noexcept {
    if (!out || len <= 0) return -1;
#if !defined(_WIN32)
    // Shared, not private: read-only either way, but a private mapping's
    // pages are copy-on-write, and a GPU reading them in place (model
    // weights) pays for it. The pages are asked for ahead of use, as
    // llama.cpp does.
    void* p = mmap(NULL, (size_t)len, PROT_READ, MAP_SHARED, fd, 0);
    if (p == MAP_FAILED) return -errno;
    posix_madvise(p, (size_t)len, POSIX_MADV_WILLNEED);
    *out = p;
    return 0;
#else
    HANDLE file = (HANDLE)_get_osfhandle(fd);
    if (file == INVALID_HANDLE_VALUE) return -1;
    HANDLE m = CreateFileMappingW(file, NULL, PAGE_READONLY, (DWORD)((uint64_t)len >> 32), (DWORD)len, NULL);
    if (!m) return -(int32_t)GetLastError();
    void* p = MapViewOfFile(m, FILE_MAP_READ, 0, 0, (SIZE_T)len);
    DWORD err = GetLastError();
    CloseHandle(m);
    if (!p) return -(int32_t)err;
    *out = p;
    return 0;
#endif
}

// unmap unmaps what map mapped.
export int32_t unmap(void* addr, int64_t len) noexcept {
    if (!addr) return 0;
#if !defined(_WIN32)
    if (munmap(addr, (size_t)len) < 0) return -errno;
#else
    (void)len;
    if (!UnmapViewOfFile(addr)) return -(int32_t)GetLastError();
#endif
    return 0;
}
