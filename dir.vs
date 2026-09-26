package fs

/// A capability handle representing an open directory.
public struct Dir {
    public let Fd: int32
    public let RootPath: Path
    public let Confined: bool

    public init(fd: int32, rootPath: Path, confined: bool = false) {
        self.Fd = fd
        self.RootPath = rootPath
        self.Confined = confined
    }

    func resolveChild(_ name: Path) throws -> Path {
        let norm = name.Lexically()
        if Confined {
            if norm.IsAbsolute() || norm.Value.hasPrefix("..") {
                throw FsError.permissionDenied("\(name.Value): confined path escape")
            }
        }
        return RootPath / norm
    }

    /// Opens a file relative to this directory.
    public func Open(_ name: Path, _ options: OpenOptions = OpenOptions()) throws -> File {
        let target = try resolveChild(name)
        return try fs_open(target, options)
    }

    /// Reads an entire file relative to this directory.
    public func ReadFile(_ name: Path) throws -> [uint8] {
        let target = try resolveChild(name)
        return try fs_read_file(target)
    }

    /// Writes data to a file relative to this directory.
    public func WriteFile(_ name: Path, _ data: borrowing [uint8], atomic: bool = false) throws {
        let target = try resolveChild(name)
        try fs_write_file(target, data, atomic: atomic)
    }

    /// Reads directory entries relative to this directory.
    public func ReadDir(_ name: Path = ".") throws -> [DirEntry] {
        let target = try resolveChild(name)
        return try fs_read_dir(target)
    }

    /// Creates a directory relative to this directory.
    public func CreateDir(_ name: Path, all: bool = false) throws {
        let target = try resolveChild(name)
        try fs_create_dir(target, all: all)
    }

    /// Removes a file or empty directory relative to this directory.
    public func Remove(_ name: Path) throws {
        let target = try resolveChild(name)
        try fs_remove(target)
    }

    /// Closes the directory descriptor.
    public func Close() {
        if Fd >= 0 {
            _ = cfs_close(Fd)
        }
    }
}

/// Opens a directory capability handle.
/// When confined is true, operations cannot escape the directory via '..' or absolute paths.
public func OpenDir(_ path: Path, confined: bool = false) throws -> Dir {
    var fd: int32 = -1
    path.Value.withCString { p in
        fd = cfs_open_dir(p, confined ? 1 : 0)
    }
    if fd < 0 {
        throw errorFor(fd, "opendir", path)
    }
    return Dir(fd: fd, rootPath: path, confined: confined)
}
