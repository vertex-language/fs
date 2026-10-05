package fs

/// A read-only file system abstraction.
public protocol FileSystem {
    func ReadFile(_ path: Path) throws -> [uint8]
    func ReadDir(_ path: Path) throws -> [DirEntry]
    func Metadata(_ path: Path) throws -> FileMetadata
}

/// A FileSystem backed by the local operating system directory tree.
public struct Local: FileSystem {
    public let Root: Path

    public init(root: Path) {
        self.Root = root.Lexically()
    }

    func resolve(_ path: Path) -> Path {
        let norm = path.Lexically()
        return Root / norm
    }

    public func ReadFile(_ path: Path) throws -> [uint8] {
        return try fs_read_file(resolve(path))
    }

    public func ReadDir(_ path: Path) throws -> [DirEntry] {
        return try ReadDir(resolve(path))
    }

    public func Metadata(_ path: Path) throws -> FileMetadata {
        return try fs_metadata(resolve(path))
    }
}
