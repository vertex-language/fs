# fs

[![package: stdlib](https://img.shields.io/badge/package-stdlib-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![storage: fs | memory](https://img.shields.io/badge/storage-fs%20%7C%20memory-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/fs)
[![runtime: async + sync](https://img.shields.io/badge/runtime-async%20%2B%20sync-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)

Standard file system library for the Vertex programming language, providing safe, high-performance file operations, capability directory handles, paths, metadata, and virtual file systems over direct operating system ABIs.

---

## Packages

- **`fs`**: Core file system operations (`fs.ReadFile`, `fs.WriteFile`, `fs.Path`, `fs.File`, `fs.Dir`, `fs.ReadDir`, `fs.Metadata`, `fs.FileSystem`).
- **`fs/memory`**: In-memory file system implementation (`memory.MemoryFileSystem`) for testing and virtual environments.
- **`fs/mmap`**: A file mapped into memory, read-only (`mmap.Map(path)` → `mmap.Mapping`). Its bytes are read in place and unmapped when the last reference goes. Model weights load through it. Built on `cfs_map` and `cfs_unmap` (`mmap` on POSIX, `MapViewOfFile` on Windows).

`fs.File` is an `io.Reader`, `io.Writer`, `io.Seeker` and `io.Closer`, so the `io` package's functions and adapters take it: `io.Copy(from: &file, to: &socket)`, `io.BufferedReader(file).ReadLine()`. `fs.SeekFrom` is `io.SeekFrom`.

---

## Quick Start

### Basic File Operations

```swift
package main

import "fs"

func main() -> int32 {
    let file = fs.Path("app.json")

    do {
        // Safe atomic writing (writes to temp file and renames)
        try fs.WriteText(file, "{\"name\": \"vertex-service\"}", atomic: true)

        // Reading text
        let content = try fs.ReadText(file)
        print("Read config: \(content)")

        // Metadata inspection
        let meta = try fs.Metadata(file)
        print("File size: \(meta.Size) bytes, modified: \(meta.Modified)")

        // Append
        var extra: [uint8] = []
        for b in "\n".utf8 { extra.append(b) }
        try fs.AppendFile(file, extra)
    } catch let err as fs.FsError {
        print("File error: \(err.Message)")
        return 1
    } catch {
        return 1
    }

    return 0
}
```

### Capability Directory Handles & Traversal

```swift
package main

import "fs"

func main() -> int32 {
    do {
        // Open a confined directory handle (prevents '..' path traversal)
        let dir = try fs.OpenDir("src", confined: true)
        defer { dir.Close() }

        // Read entries relative to the directory
        for entry in try dir.ReadDir() {
            print("Found \(entry.Name) [\(entry.Kind)]")
        }

        // Recursive tree walk
        try fs.Walk(fs.Path("src")) { entry in
            if entry.Name.hasPrefix(".") {
                return .skipDir
            }
            print("Walk: \(entry.Path.Value)")
            return .continue
        }
    } catch let err as fs.FsError {
        print("Directory error: \(err.Message)")
        return 1
    } catch {
        return 1
    }

    return 0
}
```

---

## Layout

```
fs/
├── package.vs                  # PackageDescription manifest
├── fs/                         # Public 'fs' package
│   ├── bindings.vs             # @_silgen_name C ABI bridges
│   ├── path.vs                 # Path type and lexical operations
│   ├── options.vs              # OpenOptions, FileKind, SeekFrom, CopyOptions
│   ├── file.vs                 # File handles, streaming & positional I/O
│   ├── dir.vs                  # Dir capability handles & confinement
│   ├── entries.vs              # DirEntry, ReadDir, Walk
│   ├── operations.vs           # Whole-file read/write, copy, move, symlink
│   ├── metadata.vs             # Metadata, UnixMetadata, Timestamp
│   ├── filesystem.vs           # FileSystem protocol & Local implementation
│   ├── error.vs                # FsError enum & error translation
│   └── cfs/                    # Native C ABI bridge
│       ├── include/cfs.h
│       └── cfs.cpp             # macOS (Darwin) / Linux / Windows implementation
├── memory/                     # Subpackage 'fs/memory'
├── mmap/                       # Subpackage 'fs/mmap'
│   └── memory_fs.vs            # MemoryFileSystem conforming to FileSystem
├── examples/
│   ├── cat/                    # File reader CLI
│   └── copy/                   # File & directory cloner
└── tests/
    └── check/                  # Test suite covering paths, files, dirs, errors, memory fs
```

---

## Running

Execute examples or the test suite directly with `vsc`:

```bash
# Run comprehensive check suite
vsc run check

# Run cat example
vsc run fs-cat

# Run copy example
vsc run fs-copy
```

---

## License

[MIT](LICENSE)
