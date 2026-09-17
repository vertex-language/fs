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
