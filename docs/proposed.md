# Vertex File System (`fs`): Architecture, Repository Layout, and Usage Specification

[![package: stdlib](https://img.shields.io/badge/package-stdlib-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![storage: fs | memory](https://img.shields.io/badge/storage-fs%20%7C%20memory-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/fs)
[![runtime: async + sync](https://img.shields.io/badge/runtime-async%20%2B%20sync-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)

This proposal establishes the architecture, repository layout, API design, and end usage patterns for `vertex-language/fs`. It synthesizes the Vertex standard library package flow established across `net`, `time`, and `ui`, adheres to the core packaging tenets in `package_design/best_practice.md`, and incorporates the design decisions laid out in the `fs.md` architectural blueprint.

---

## 1. Design Principles & Vertex Package Flow

`fs` is a **Core Bedrock Package** in the Vertex runtime and standard library ecosystem. Every other package—parsers, configuration loaders, webview asset managers, compilation engines, loggers, and database drivers—stands on it.

### Core Tenets

1. **The Zero-Dependency Mandate**:
   - Zero vendoring of third-party C/C++ libraries (no `libuv`, `boost::filesystem`, `sqlite`, etc.).
   - Directly binds to verified, hyper-optimized first-party operating system ABIs via Vertex's in-tree native compilers (`vcc`, `v++`, `objv`).
2. **Platform-Agnostic Top Layer (Go Packaging Principle)**:
   - Named strictly for what it provides: `fs` (with subpackages `fs/memory`, and later `fs/mmap`).
   - Absolute zero platform leakage to caller code: developers never import `darwin`, `posix`, or `win32`.
3. **Three-Tier Architecture**:
   - **Tier 1 (Public Surface)**: 100% pure Vertex (`.vs`), value types (`Path`), non-copyable RAII resource handles (`File`, `Dir`), borrowing semantics (`borrowing [uint8]`), and typed errors (`FsError`).
   - **Tier 2 (Engine / Dispatch Contract)**: Internal protocol-driven driver contracts managing cross-platform normalization and runtime offloading.
   - **Tier 3 (In-Tree Native Bridge `cfs`)**: Flat scalar C ABI (`cfs/include/cfs.h`) compiled via `v++` (C++20) with target-specific files (`cfs_darwin.cpp`, `cfs_linux.cpp`, `cfs_windows.cpp`).
4. **Context-Sensitive Duality ("One Name, Two Forms")**:
   - Disk operations have fundamentally different needs in scripts vs. servers.
   - Operations that can wait (`ReadFile`, `WriteFile`, `Open`, `ReadDir`, `Metadata`) are available in both **synchronous (blocking)** and **asynchronous (cooperative)** forms sharing the same function name.
   - In an `async` context, the compiler selects the `async` overload and enforces `await`. Calling blocking functions inside an `async` context is a compile-time error.
   - Async operations are offloaded in batched units to the runtime worker pool (`vertex_task_offload`), posting completion events back to the executor event loop via kqueue/epoll/IOCP.
5. **Capability Handles and Path Safety**:
   - Directory operations and traversals are anchored on `Dir` handles using relative file-descriptor calls (`openat`, `unlinkat`, `renameat`).
   - Sandboxing via `confined: true` prevents directory traversal (`..`) and symlink escapes (Go 1.24 `os.Root` / `cap-std` model).
6. **Abstract File System Protocol**:
   - Read-only `FileSystem` protocol inspired by Go's `io/fs.FS`, allowing consumers (e.g. web servers, template engines) to work interchangeably with physical disks, in-memory mock systems (`fs/memory`), and embedded assets.

---

## 2. Complete Repository Layout

Following the exact structure of `net`, `time`, and `ui`, the `vertex-language/fs` repository is laid out as follows:

```
fs/
├── package.vs                  # PackageDescription manifest (targets, products, C++20)
├── README.md                   # Public documentation, badges, quick starts, commands
├── LICENSE                     # MIT license
├── docs/                       # Architectural specifications & proposals
│   └── proposed.md             # This document
│
├── fs/                         # [Tier 1 & 2] Top-level 'fs' library target
│   ├── bindings.vs             # @_silgen_name bindings to cfs native bridge
│   ├── path.vs                 # Path struct, normalization, component parsing
│   ├── options.vs              # OpenOptions, CopyOptions, FileKind, Permissions
│   ├── file.vs                 # File (~Copyable handle, pread/pwrite, Sync, Lock)
│   ├── dir.vs                  # Dir (~Copyable capability handle, openat relative ops)
│   ├── entries.vs              # DirEntry, DirEntries (lazy iteration), Walk
│   ├── filesystem.vs           # FileSystem protocol, Local fs, Sub fs
│   ├── metadata.vs             # Metadata struct (portable + Unix/Windows extensions)
│   ├── operations.vs           # ReadFile, WriteFile (atomic), Remove, Rename, Copy
│   ├── offload.vs              # fs.Offload { } block helper for runtime worker pool
│   ├── watch.vs                # Watcher (AsyncSequence), FsChange, ChangeKind
│   ├── error.vs                # FsError enum, context formatting, error translation
│   │
│   └── cfs/                    # [Tier 3] In-tree Native C ABI Bridge
│       ├── include/
│       │   └── cfs.h           # Pure C header (extern "C"), scalar handles & structs
│       ├── cfs_common.cpp      # Shared utility, path conversions, error mapping
│       ├── cfs_darwin.cpp      # macOS: getattrlistbulk, clonefile, renameatx_np, fsevents
│       ├── cfs_linux.cpp       # Linux: openat2 (RESOLVE_BENEATH), statx, copy_file_range, inotify
│       └── cfs_windows.cpp     # Windows: NtCreateFile, CreateFileW, ReplaceFileW, ReadDirectoryChangesW
│
├── memory/                     # [Subpackage] 'fs/memory' library product
│   ├── memory_fs.vs            # MemoryFileSystem conforming to FileSystem protocol
│   └── node.vs                 # In-memory virtual file/directory nodes
│
├── examples/                   # Practical usage examples
│   ├── cat/                    # Whole-file and streaming reader CLI
│   │   └── main.vs
│   ├── copy/                   # Safe atomic directory cloning & file copying
│   │   └── main.vs
│   ├── watcher/                # Live file-watcher daemon (AsyncSequence)
│   │   └── main.vs
│   └── server_assets/          # Static HTTP asset server using confined Dir & FileSystem
│       └── main.vs
│
└── tests/                      # Automated test suite (runnable via 'vsc run')
    ├── check/                  # Comprehensive suite (Path parsing, whole-file, errors)
    │   └── main.vs
    ├── dir/                    # Lazy directory iteration, large dirs, Walk benchmarks
    │   └── main.vs
    ├── security/               # openat symlink race tests, confined Dir escapes
    │   └── main.vs
    ├── concurrency/            # Sync vs Async parity checks, task offload stress
    │   └── main.vs
    └── memory/                 # fs/memory unit tests against FileSystem protocol
        └── main.vs
```

---

## 3. Package Manifest (`package.vs`)

The manifest configures the in-tree native C++ bridge, the public Vertex libraries, example executables, and test harnesses:

```swift
// The 'fs' package: files, directories, metadata, paths, and change notification.
import PackageDescription

let package = Package(
    name: "fs",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        // Core libraries
        .library(name: "fs", targets: ["fs"]),
        .library(name: "fs/memory", targets: ["fs_memory"]),

        // Examples
        .executable(name: "fs-cat", targets: ["example_cat"]),
        .executable(name: "fs-copy", targets: ["example_copy"]),
        .executable(name: "fs-watch", targets: ["example_watch"]),
        .executable(name: "fs-server-assets", targets: ["example_server_assets"]),

        // Test suites
        .executable(name: "fs-check", targets: ["test_check"]),
        .executable(name: "fs-dir-test", targets: ["test_dir"]),
        .executable(name: "fs-security-test", targets: ["test_security"]),
        .executable(name: "fs-concurrency-test", targets: ["test_concurrency"]),
        .executable(name: "fs-memory-test", targets: ["test_memory"]),
    ],
    targets: [
        // Tier 3: In-tree C ABI bridge over OS filesystem system calls
        .target(
            name: "cfs",
            path: "fs/cfs",
            publicHeadersPath: "include"
        ),

        // Tier 1 & 2: Public Vertex 'fs' module
        .target(
            name: "fs",
            dependencies: ["cfs"],
            path: "fs",
            exclude: ["cfs"]
        ),

        // Subpackage: In-memory filesystem for tests and mock environments
        .target(
            name: "fs_memory",
            dependencies: ["fs"],
            path: "memory"
        ),

        // Examples
        .executableTarget(
            name: "example_cat",
            dependencies: ["fs"],
            path: "examples/cat"
        ),
        .executableTarget(
            name: "example_copy",
            dependencies: ["fs"],
            path: "examples/copy"
        ),
        .executableTarget(
            name: "example_watch",
            dependencies: ["fs"],
            path: "examples/watcher"
        ),
        .executableTarget(
            name: "example_server_assets",
            dependencies: ["fs"],
            path: "examples/server_assets"
        ),

        // Tests
        .executableTarget(
            name: "test_check",
            dependencies: ["fs"],
            path: "tests/check"
        ),
        .executableTarget(
            name: "test_dir",
            dependencies: ["fs"],
            path: "tests/dir"
        ),
        .executableTarget(
            name: "test_security",
            dependencies: ["fs"],
            path: "tests/security"
        ),
        .executableTarget(
            name: "test_concurrency",
            dependencies: ["fs"],
            path: "tests/concurrency"
        ),
        .executableTarget(
            name: "test_memory",
            dependencies: ["fs", "fs_memory"],
            path: "tests/memory"
        ),
    ],
    cxxLanguageStandard: "c++20"
)
```

---

## 4. Native Bridge Interface (`fs/cfs/include/cfs.h`)

The native bridge exposes a strict C ABI without C++ templates or mangled symbols:

```c
#ifndef CFS_H
#define CFS_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Error codes (CFS_ERR_*)
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

typedef struct {
    uint32_t kind;             // 1=file, 2=dir, 3=symlink, 4=other
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
    bool     is_readonly;
} CFsMetadata;

// Batched whole-file operations (one thread-hop)
int32_t cfs_read_file(const char* path, size_t path_len, uint8_t** out_buf, size_t* out_len);
int32_t cfs_write_file(const char* path, size_t path_len, const uint8_t* data, size_t len, bool atomic);
void    cfs_free_buffer(uint8_t* buf);

// File handle operations
int32_t cfs_open(const char* path, size_t path_len, int32_t flags, uint32_t mode);
int32_t cfs_close(int32_t fd);
int64_t cfs_read(int32_t fd, void* buf, size_t count);
int64_t cfs_pread(int32_t fd, void* buf, size_t count, int64_t offset);
int64_t cfs_write(int32_t fd, const void* buf, size_t count);
int64_t cfs_pwrite(int32_t fd, const void* buf, size_t count, int64_t offset);
int64_t cfs_seek(int32_t fd, int64_t offset, int32_t whence);
int32_t cfs_truncate(int32_t fd, int64_t length);
int32_t cfs_sync(int32_t fd, bool data_only);
int32_t cfs_lock(int32_t fd, int32_t kind, bool wait);

// Directory & relative operations (Dir capability)
int32_t cfs_open_dir(const char* path, size_t path_len, bool confined);
int32_t cfs_openat(int32_t dir_fd, const char* name, size_t name_len, int32_t flags, uint32_t mode);
int32_t cfs_read_dir_entries(int32_t dir_fd, uint8_t* out_records, size_t buf_len, size_t* out_count);
int32_t cfs_unlinkat(int32_t dir_fd, const char* name, size_t name_len, bool is_dir);
int32_t cfs_renameat(int32_t src_dir_fd, const char* src, size_t src_len,
                     int32_t dst_dir_fd, const char* dst, size_t dst_len, bool replace);

// Metadata & attributes
int32_t cfs_stat(const char* path, size_t path_len, bool follow_symlinks, CFsMetadata* out_meta);
int32_t cfs_fstat(int32_t fd, CFsMetadata* out_meta);
int32_t cfs_set_permissions(const char* path, size_t path_len, uint32_t mode);
int32_t cfs_set_times(const char* path, size_t path_len, int64_t mod_sec, int32_t mod_nsec,
                      int64_t acc_sec, int32_t acc_nsec);

// Cloning, links, paths
int32_t cfs_clone_file(const char* src, size_t src_len, const char* dst, size_t dst_len);
int32_t cfs_readlink(const char* path, size_t path_len, char* out_buf, size_t* out_len);
int32_t cfs_canonical(const char* path, size_t path_len, char* out_buf, size_t* out_len);

// Watching
int32_t cfs_watch_init(const char* path, size_t path_len, bool recursive);
int32_t cfs_watch_poll(int32_t watcher_fd, void* out_events, size_t max_events);
void    cfs_watch_close(int32_t watcher_fd);

#ifdef __cplusplus
}
#endif

#endif // CFS_H
```

---

## 5. Public API Specification & Types

### 5.1 The `Path` Type

A path is a distinct, strongly-typed abstraction over file system identifiers—never a raw string. It maintains lossless bytes on Unix systems and WTF-8 representations on Windows.

```swift
package fs

public struct Path: Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public init(_ text: string)
    public init(bytes: [uint8])

    // Decomposition
    public func Parent() -> Path?
    public func Name() -> string?
    public func Stem() -> string?
    public func Extension() -> string?
    public func WithExtension(_ ext: string) -> Path
    public func Components() -> [Path.Component]

    // Lexical operations (no disk I/O)
    public func Join(_ other: Path) -> Path
    public func Lexically() -> Path                     // "a/./b/../c" -> "a/c"
    public func Relative(to base: Path) -> Path?
    public func StartsWith(_ prefix: Path) -> bool
    public func IsAbsolute() -> bool

    // Representations
    public var Bytes: [uint8] { get }
    public func String() -> string
    public var description: string { return String() }

    // Operator overloads
    public static func / (lhs: Path, rhs: string) -> Path
    public static func / (lhs: Path, rhs: Path) -> Path
}
```

### 5.2 Whole-File Convenience Operations

Whole-file operations provide safe, convenient one-liners. Each function is dual-formed (blocking in sync code, task-parked in async code).

```swift
package fs

/// Reads an entire file into a byte buffer.
public func ReadFile(_ path: Path) throws -> [uint8]
public func ReadFile(_ path: Path) async throws -> [uint8]

/// Reads an entire UTF-8 encoded text file.
public func ReadText(_ path: Path) throws -> string
public func ReadText(_ path: Path) async throws -> string

/// Writes an entire buffer to a file.
/// If atomic is true, writes to a temporary file in the same directory and renames it over the target.
public func WriteFile(_ path: Path, _ data: borrowing [uint8], atomic: bool = false) throws
public func WriteFile(_ path: Path, _ data: borrowing [uint8], atomic: bool = false) async throws

/// Writes a string to a file as UTF-8.
public func WriteText(_ path: Path, _ text: string, atomic: bool = false) throws
public func WriteText(_ path: Path, _ text: string, atomic: bool = false) async throws

/// Appends a byte buffer to the end of an existing file.
public func AppendFile(_ path: Path, _ data: borrowing [uint8]) throws
public func AppendFile(_ path: Path, _ data: borrowing [uint8]) async throws
```

### 5.3 Non-Copyable Handles: `File`

`File` is a non-copyable RAII resource (`~Copyable`) representing an open OS file descriptor.

```swift
package fs

public struct OpenOptions {
    public var Read: bool = true
    public var Write: bool = false
    public var Append: bool = false
    public var Create: CreateMode = .never
    public var Permissions: Permissions? = nil

    public init() {}
    public static let read = OpenOptions()
    public static let write: OpenOptions
    public static let append: OpenOptions
}

public struct File: ~Copyable {
    public let Fd: int32

    // Streaming I/O
    public func Read(into buffer: inout [uint8]) throws -> int
    public func Read(into buffer: inout [uint8]) async throws -> int
    public func ReadToEnd() throws -> [uint8]
    public func ReadToEnd() async throws -> [uint8]
    public func Write(_ data: borrowing [uint8]) throws
    public func Write(_ data: borrowing [uint8]) async throws

    // Positional I/O (pread/pwrite: safe without cursor races)
    public func Read(into buffer: inout [uint8], at offset: int64) throws -> int
    public func Read(into buffer: inout [uint8], at offset: int64) async throws -> int
    public func Write(_ data: borrowing [uint8], at offset: int64) throws
    public func Write(_ data: borrowing [uint8], at offset: int64) async throws

    // Control & Metadata
    public func Seek(_ to: SeekFrom) throws -> int64
    public func SetLength(_ length: int64) throws
    public func Metadata() throws -> Metadata
    public func Metadata() async throws -> Metadata
    public func Sync(dataOnly: bool = false) throws
    public func Sync(dataOnly: bool = false) async throws
    public func Lock(_ kind: LockKind, wait: bool = true) throws

    // Explicit resource release
    public consuming func Close() throws
    deinit
}

public func Open(_ path: Path, _ options: OpenOptions = .read) throws -> File
public func Open(_ path: Path, _ options: OpenOptions = .read) async throws -> File
public func Create(_ path: Path) throws -> File
public func Create(_ path: Path) async throws -> File
```

### 5.4 Capability Handles: `Dir`

`Dir` represents an open directory file descriptor. Every operation performed on `Dir` executes relative to that open descriptor (`openat`, `unlinkat`, `renameat`), immune to race conditions and symlink swap attacks.

```swift
package fs

public struct Dir: ~Copyable {
    public let Fd: int32
    public let IsConfined: bool

    public func Open(_ name: Path, _ options: OpenOptions = .read) throws -> File
    public func Open(_ name: Path, _ options: OpenOptions = .read) async throws -> File

    public func ReadFile(_ name: Path) throws -> [uint8]
    public func ReadFile(_ name: Path) async throws -> [uint8]

    public func WriteFile(_ name: Path, _ data: borrowing [uint8], atomic: bool = false) throws
    public func WriteFile(_ name: Path, _ data: borrowing [uint8], atomic: bool = false) async throws

    public func OpenDir(_ name: Path) throws -> Dir
    public func Metadata(_ name: Path = ".", followSymlinks: bool = true) throws -> Metadata
    public func ReadDir(_ name: Path = ".") throws -> [DirEntry]
    public func CreateDir(_ name: Path, all: bool = false) throws
    public func Remove(_ name: Path) throws
    public func Rename(_ from: Path, to: Path, in targetDir: borrowing Dir) throws

    public consuming func Close()
    deinit
}

/// Opens a directory.
/// If confined is true, paths cannot escape via '..' or symlinks (Go os.Root model).
public func OpenDir(_ path: Path, confined: bool = false) throws -> Dir
public func OpenDir(_ path: Path, confined: bool = false) async throws -> Dir
```

### 5.5 Directory Traversal & Management

```swift
package fs

public struct DirEntry {
    public let Path: Path
    public let Name: string
    public let Kind: FileKind
    public func Metadata() throws -> Metadata
    public func Metadata() async throws -> Metadata
}

/// Returns all entries in a directory, sorted lexicographically.
public func ReadDir(_ path: Path) throws -> [DirEntry]
public func ReadDir(_ path: Path) async throws -> [DirEntry]

/// Lazy directory iterator for massive directory trees.
public func Entries(_ path: Path) throws -> DirEntries
public func Entries(_ path: Path) async throws -> DirEntries

/// Recursive directory walk with prune controls.
public enum WalkAction {
    case `continue`
    case skipDir
    case stop
}
public func Walk(_ root: Path, _ visit: (DirEntry) throws -> WalkAction) throws
public func Walk(_ root: Path, _ visit: (DirEntry) async throws -> WalkAction) async throws

// Directory structure manipulation
public func CreateDir(_ path: Path, all: bool = false) throws
public func CreateDir(_ path: Path, all: bool = false) async throws
public func Remove(_ path: Path) throws
public func Remove(_ path: Path) async throws
public func RemoveAll(_ path: Path) throws
public func RemoveAll(_ path: Path) async throws
public func Rename(_ from: Path, _ to: Path, replace: bool = true) throws
public func Rename(_ from: Path, _ to: Path, replace: bool = true) async throws
public func Copy(_ from: Path, _ to: Path, _ options: CopyOptions = .init()) throws
public func Copy(_ from: Path, _ to: Path, _ options: CopyOptions = .init()) async throws
```

### 5.6 Metadata & Attributes

```swift
package fs

public struct Metadata {
    public let Kind: FileKind
    public let Size: int64
    public let Modified: Timestamp
    public let Accessed: Timestamp
    public let Created: Timestamp?
    public let ReadOnly: bool

    // Platform-specific detail payloads
    public let Unix: UnixMetadata?
    public let Windows: WindowsMetadata?
}

public struct UnixMetadata {
    public let Mode: uint32
    public let Uid: uint32
    public let Gid: uint32
    public let Inode: uint64
    public let Device: uint64
}

public struct WindowsMetadata {
    public let Attributes: uint32
    public let FileIndex: uint64
    public let VolumeSerial: uint32
}

public func Metadata(_ path: Path, followSymlinks: bool = true) throws -> Metadata
public func Metadata(_ path: Path, followSymlinks: bool = true) async throws -> Metadata
```

### 5.7 The `FileSystem` Protocol & In-Memory Implementation

A decoupled, read-only interface equivalent to Go's `io/fs.FS`. Enables mock testing, bundle assets, and archive mounting.

```swift
package fs

public protocol FileSystem {
    func ReadFile(_ path: Path) throws -> [uint8]
    func ReadDir(_ path: Path) throws -> [DirEntry]
    func Metadata(_ path: Path) throws -> Metadata
}

/// Standard OS implementation confined to a root path.
public struct Local: FileSystem {
    public init(root: Path)
    public func ReadFile(_ path: Path) throws -> [uint8]
    public func ReadDir(_ path: Path) throws -> [DirEntry]
    public func Metadata(_ path: Path) throws -> Metadata
}

/// Returns a sub-tree of an existing FileSystem.
public func Sub(_ fs: some FileSystem, _ dir: Path) -> some FileSystem
```

In `fs/memory`:
```swift
package memory

import "fs"

public final class MemoryFileSystem: fs.FileSystem {
    public init()
    public func AddFile(_ path: fs.Path, data: [uint8])
    public func AddText(_ path: fs.Path, text: string)
    public func ReadFile(_ path: fs.Path) throws -> [uint8]
    public func ReadDir(_ path: fs.Path) throws -> [fs.DirEntry]
    public func Metadata(_ path: fs.Path) throws -> fs.Metadata
}
```

### 5.8 File System Watching

Watching is an inherently unbounded wait and is exclusively `async`, modeled as an `AsyncSequence`.

```swift
package fs

public enum ChangeKind {
    case created
    case modified
    case removed
    case renamed
    case overflow   // Kernel dropped events; caller must rescan
}

public struct FsChange {
    public let Path: Path
    public let Kind: ChangeKind
}

public func Watch(_ path: Path, recursive: bool = true) throws -> Watcher
```

### 5.9 Typed Errors: `FsError`

```swift
package fs

public enum FsError: Error {
    case notFound(Path, op: string)
    case alreadyExists(Path, op: string)
    case permissionDenied(Path, op: string)
    case notADirectory(Path, op: string)
    case isADirectory(Path, op: string)
    case directoryNotEmpty(Path, op: string)
    case readOnly(Path, op: string)
    case noSpace(Path, op: string)
    case tooManyOpenFiles(op: string)
    case crossesDevices(from: Path, to: Path)
    case invalidPath(Path, reason: string)
    case interrupted(op: string)
    case system(code: int32, op: string, path: Path?)

    public var Message: string {
        switch self {
        case .notFound(let path, let op):
            return "\(op) \(path): no such file or directory"
        case .alreadyExists(let path, let op):
            return "\(op) \(path): file already exists"
        case .permissionDenied(let path, let op):
            return "\(op) \(path): permission denied"
        case .notADirectory(let path, let op):
            return "\(op) \(path): not a directory"
        case .isADirectory(let path, let op):
            return "\(op) \(path): is a directory"
        case .directoryNotEmpty(let path, let op):
            return "\(op) \(path): directory not empty"
        case .readOnly(let path, let op):
            return "\(op) \(path): read-only file system"
        case .noSpace(let path, let op):
            return "\(op) \(path): no space left on device"
        case .tooManyOpenFiles(let op):
            return "\(op): too many open files"
        case .crossesDevices(let from, let to):
            return "rename \(from) to \(to): invalid cross-device link"
        case .invalidPath(let path, let reason):
            return "invalid path \(path): \(reason)"
        case .interrupted(let op):
            return "\(op): operation interrupted"
        case .system(let code, let op, let path):
            if let p = path {
                return "\(op) \(p): system error \(code)"
            }
            return "\(op): system error \(code)"
        }
    }
}
```

---

## 6. End Usage Scenarios

### 6.1 Synchronous Script / Tool Usage

In synchronous contexts (such as a CLI tool or a build script), file operations run directly on the calling thread without requiring `await`:

```swift
package main

import "fs"

func main() -> int32 {
    let configPath = fs.Path("build.json")

    do {
        // Simple synchronous text reading
        let text = try fs.ReadText(configPath)
        print("Loaded config: \(text)")

        // Safe atomic file update
        try fs.WriteText("build/out.txt", "compilation successful\n", atomic: true)

        // Read directory contents synchronously
        for entry in try fs.ReadDir("src") {
            print("Found source file: \(entry.Name) (\(entry.Kind))")
        }
    } catch let e as fs.FsError {
        print("File error: \(e.Message)")
        return 1
    } catch {
        print("Unknown error")
        return 1
    }

    return 0
}
```

### 6.2 High-Throughput Async Server

In asynchronous tasks, operations automatically switch to the non-blocking thread-offloaded variant. The compiler requires `await`, ensuring executor threads are never blocked.

```swift
package main

import "fs"
import "net/tcp"
import "net/http"

func handleStaticAssets(client: consuming tcp.TcpStream, assetDir: borrowing fs.Dir) async {
    defer { client.Close() }

    await http.ServeConn(stream: client) { req in
        var res = http.ResponseWriter()
        let requestedPath = fs.Path(req.Path).Lexically()

        do {
            // Confined Dir handles prevent directory traversal attacks
            let data = try await assetDir.ReadFile(requestedPath)
            res.SetStatus(http.Status.OK)
            res.SetHeader("Content-Type", "text/html")
            res.Write(data)
        } catch let e as fs.FsError {
            switch e {
            case .notFound:
                res.SetStatus(http.Status.NotFound)
                res.WriteText("404 Not Found")
            default:
                res.SetStatus(http.Status.InternalServerError)
                res.WriteText("500 Internal Server Error: \(e.Message)")
            }
        } catch {
            res.SetStatus(http.Status.InternalServerError)
            res.WriteText("500 Internal Server Error")
        }
        return res
    }
}

func main() async -> int32 {
    // Open a sandboxed, confined directory for static assets
    let publicDir = try fs.OpenDir("public", confined: true)
    let listener = try tcp.Listen(":8080")
    print("Serving public/ on http://localhost:8080")

    while true {
        let client = try await listener.Accept()
        Task {
            await handleStaticAssets(client: client, assetDir: publicDir)
        }
    }
    return 0
}
```

### 6.3 Live Directory Watching Daemon

Change monitoring modeled cleanly as an `AsyncSequence`:

```swift
package main

import "fs"

func main() async -> int32 {
    let watchRoot = fs.Path("src")
    print("Watching directory \(watchRoot) for modifications...")

    do {
        let watcher = try fs.Watch(watchRoot, recursive: true)
        for try await change in watcher {
            switch change.Kind {
            case .created:
                print("Created: \(change.Path)")
            case .modified:
                print("Modified: \(change.Path)")
            case .removed:
                print("Deleted: \(change.Path)")
            case .renamed:
                print("Renamed: \(change.Path)")
            case .overflow:
                print("Warning: Kernel buffer overflowed. Re-scanning workspace...")
            }
        }
    } catch let err as fs.FsError {
        print("Watcher failed: \(err.Message)")
        return 1
    } catch {
        return 1
    }

    return 0
}
```

### 6.4 Safe Unit Testing with `fs/memory`

Components accepting `fs.FileSystem` can be tested purely in-memory without creating temporary files on physical disk:

```swift
package main

import "fs"
import "fs/memory"

func parseManifest(from fileSystem: some fs.FileSystem) throws -> string {
    let raw = try fileSystem.ReadFile(fs.Path("manifest.json"))
    return string(decoding: raw, as: UTF8.self)
}

func testManifestParser() -> bool {
    let mem = memory.MemoryFileSystem()
    mem.AddText("manifest.json", "{\"name\": \"vertex-app\"}")

    do {
        let manifest = try parseManifest(from: mem)
        return manifest.contains("vertex-app")
    } catch {
        return false
    }
}
```

---

## 7. Platform Verification Matrix

Following the patterns in `net/tcp` (BSD sockets/kqueue/IOCP) and `ui/window` (Cocoa/Win32), `fs` will target the platform primitives directly without intermediate wrappers:

| Operation | macOS (Darwin) | Linux | Windows |
|---|---|---|---|
| **Whole File Read/Write** | `open` + `fstat` + `read` | `open` + `fstat` + `read` | `CreateFileW` + `ReadFile` |
| **Atomic Write** | `renamex_np` | `renameat2(RENAME_EXCHANGE)` | `ReplaceFileW` |
| **Fast Cloning** | `clonefile(2)` (APFS copy-on-write) | `copy_file_range(2)` / `FICLONE` | `CopyFile2` |
| **Directory Read** | `getattrlistbulk` (metadata in 1 syscall) | `getdents64` | `GetFileInformationByHandleEx` |
| **Confinement** | Lexical + component `openat` resolution | `openat2(RESOLVE_BENEATH)` | `NtCreateFile` relative handle |
| **Stat / Metadata** | `stat64` + `st_birthtime` | `statx(2)` (Btime + extended attr) | `GetFileInformationByHandleEx` |
| **Watch Notifications** | `FSEvents` / `kqueue(EVFILT_VNODE)` | `inotify` / `fanotify` | `ReadDirectoryChangesW` |
| **Offloaded Pool** | `vertex_task_offload` $\to$ kqueue user evt | `vertex_task_offload` $\to$ epoll eventfd | `vertex_task_offload` $\to$ IOCP port |

---

## 8. Test Suite Strategy

In alignment with Vertex standard library testing guidelines:
1. **Real Scratch Directories**: Tests in `tests/check` and `tests/dir` create dedicated temporary test folders under the OS temp path, perform real disk operations, and clean up afterwards.
2. **Deterministic Output & Failure Codes**: Tests are executable targets built via `vsc run <target>`. They report `ok <check>` or `FAIL <check>` and exit with the count of failed assertions (0 on complete success).
3. **Symlink Race Mitigation**: Specific regression test cases in `tests/security` simulate concurrent symlink swaps during recursive deletions (`RemoveAll`) and verify that `Dir(confined: true)` cannot escape outside the root via `..` or relative symlink chains.
4. **Dual-Form Parity Verification**: Table-driven tests execute every operation synchronously and asynchronously over identical file sets, validating identical byte outputs and error codes.
