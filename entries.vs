package fs

/// A single entry within a directory.
public struct DirEntry {
    public let Path: Path
    public let Name: string
    public let Kind: FileKind

    public init(path: Path, name: string, kind: FileKind) {
        self.Path = path
        self.Name = name
        self.Kind = kind
    }

    /// Fetches full metadata for this entry.
    public func Metadata() throws -> FileMetadata {
        return try fs_metadata(Path)
    }

    public func Stat() throws -> FileMetadata {
        return try fs_metadata(Path)
    }
}

func parseDirRecords(dirPath: Path, buffer: [uint8], bytesWritten: int) -> [DirEntry] {
    var entries: [DirEntry] = []
    var offset = 0
    while offset + 3 <= bytesWritten {
        let b0 = int(buffer[offset])
        let b1 = int(buffer[offset + 1])
        let nameLen = (b1 << 8) | b0
        offset += 2
        if offset + nameLen + 1 > bytesWritten { break }
        let name = stringFromBytes(buffer, from: offset, to: offset + nameLen)
        offset += nameLen
        let rawKind = buffer[offset]
        offset += 1
        var kind: FileKind = .other
        if rawKind == 1 { kind = .file }
        else if rawKind == 2 { kind = .directory }
        else if rawKind == 3 { kind = .symlink }
        let entryPath = dirPath / name
        entries.append(DirEntry(path: entryPath, name: name, kind: kind))
    }
    return entries
}

func sortEntries(_ entries: inout [DirEntry]) {
    var i = 0
    while i < entries.count {
        var j = i + 1
        while j < entries.count {
            if entries[j].Name < entries[i].Name {
                let tmp = entries[i]
                entries[i] = entries[j]
                entries[j] = tmp
            }
            j += 1
        }
        i += 1
    }
}

func fs_read_dir(_ path: Path) throws -> [DirEntry] {
    var dirFd: int32 = -1
    path.Value.withCString { p in
        dirFd = cfs_open_dir(p, 0)
    }
    if dirFd < 0 {
        throw errorFor(dirFd, "readdir", path)
    }
    defer { _ = cfs_close(dirFd) }

    var buffer = [uint8](repeating: 0, count: 256 * 1024)
    var recordCount: int32 = 0
    var bytesWritten: int32 = 0

    let rc = buffer.withUnsafeMutableBufferPointer { ptr in
        cfs_read_dir_records(dirFd, ptr.baseAddress!, int32(ptr.count), &recordCount, &bytesWritten)
    }
    if rc != 0 {
        throw errorFor(rc, "readdir", path)
    }

    var entries = parseDirRecords(dirPath: path, buffer: buffer, bytesWritten: int(bytesWritten))
    sortEntries(&entries)
    return entries
}

/// Reads all entries in a directory, sorted lexicographically by name.
public func ReadDir(_ path: Path) throws -> [DirEntry] {
    return try fs_read_dir(path)
}

/// Control action for recursive directory traversal.
public enum WalkAction {
    case `continue`
    case skipDir
    case stop
}

/// Recursively walks a directory tree calling visit on each entry.
public func Walk(_ root: Path, _ visit: (DirEntry) throws -> WalkAction) throws {
    let entries = try fs_read_dir(root)
    var i = 0
    while i < entries.count {
        let entry = entries[i]
        let action = try visit(entry)
        switch action {
        case .stop:
            return
        case .skipDir:
            break
        case .continue:
            if entry.Kind == .directory {
                try Walk(entry.Path, visit)
            }
        }
        i += 1
    }
}
