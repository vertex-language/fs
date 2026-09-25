// The 'fs' package: files, directories, metadata, paths, and change notification.
import PackageDescription

let package = Package(
    name: "fs",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "fs", targets: ["fs"]),
        .library(name: "fs/memory", targets: ["fs_memory"]),
        .library(name: "fs/mmap", targets: ["mmap"]),
        .executable(name: "test-mmap", targets: ["test_mmap"]),
        .executable(name: "check", targets: ["check"]),
        .executable(name: "fs-cat", targets: ["example_cat"]),
        .executable(name: "fs-copy", targets: ["example_copy"]),
    ],
    targets: [
        // The operating system's file system calls, as a C ABI.
        .target(
            name: "cfs",
            path: "fs/cfs",
            publicHeadersPath: "include"
        ),
        // The fs package: Vertex types over cfs.
        .target(
            name: "fs",
            dependencies: ["cfs"],
            path: "fs",
            exclude: ["cfs"]
        ),
        // In-memory file system for tests and virtual environments.
        .target(
            name: "fs_memory",
            dependencies: ["fs"],
            path: "memory"
        ),
        // Files mapped into memory, read in place.
        .target(
            name: "mmap",
            dependencies: ["fs", "cfs"],
            path: "mmap"
        ),
        .executableTarget(
            name: "test_mmap",
            dependencies: ["fs", "mmap"],
            path: "tests/mmap"
        ),
        // Comprehensive test suite.
        .executableTarget(
            name: "check",
            dependencies: ["fs", "fs_memory"],
            path: "tests/check"
        ),
        // Example: Cat
        .executableTarget(
            name: "example_cat",
            dependencies: ["fs"],
            path: "examples/cat"
        ),
        // Example: Copy
        .executableTarget(
            name: "example_copy",
            dependencies: ["fs"],
            path: "examples/copy"
        ),
    ],
    cxxLanguageStandard: "c++20"
)
