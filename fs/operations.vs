package fs

func fs_read_file(_ path: Path) throws -> [uint8] {
    var szFields = [int64](repeating: 0, count: 16)
    var rc: int32 = 0
    path.Value.withCString { p in
        szFields.withUnsafeMutableBufferPointer { ptr in
            rc = cfs_stat_raw(p, 1, ptr.baseAddress!)
        }
    }
    if rc != 0 {
        throw errorFor(rc, "readfile", path)
    }
    let fileSize = int(szFields[1])
    if fileSize == 0 {
        return []
    }
    var result = [uint8](repeating: 0, count: fileSize)
    var bytesRead: int64 = 0
    var readRc: int32 = 0
    path.Value.withCString { p in
        result.withUnsafeMutableBytes { raw in
            readRc = cfs_read_file_into(p, raw.baseAddress!, int64(fileSize), &bytesRead)
        }
    }
    if readRc != 0 {
        throw errorFor(readRc, "readfile", path)
    }
    return result
}

func fs_write_file(_ path: Path, _ data: borrowing [uint8], atomic: bool = false) throws {
    var rc: int32 = 0
    path.Value.withCString { p in
        if data.isEmpty {
            rc = cfs_write_file(p, nil, 0, atomic ? 1 : 0)
        } else {
            data.withUnsafeBytes { raw in
                rc = cfs_write_file(p, raw.baseAddress!, int64(data.count), atomic ? 1 : 0)
            }
        }
    }
    if rc != 0 {
        throw errorFor(rc, "writefile", path)
    }
}

func fs_append_file(_ path: Path, _ data: borrowing [uint8]) throws {
    var rc: int32 = 0
    path.Value.withCString { p in
        if data.isEmpty {
            rc = cfs_append_file(p, nil, 0)
        } else {
            data.withUnsafeBytes { raw in
                rc = cfs_append_file(p, raw.baseAddress!, int64(data.count))
            }
        }
    }
    if rc != 0 {
        throw errorFor(rc, "appendfile", path)
    }
}

func fs_create_dir(_ path: Path, all: bool = false) throws {
    var rc: int32 = 0
    path.Value.withCString { p in
        rc = cfs_mkdir(p, 0o777, all ? 1 : 0)
    }
    if rc != 0 {
        throw errorFor(rc, "mkdir", path)
    }
}

func fs_remove(_ path: Path) throws {
    var rc: int32 = 0
    path.Value.withCString { p in
        rc = cfs_remove(p)
    }
    if rc != 0 {
        throw errorFor(rc, "remove", path)
    }
}

func fs_metadata(_ path: Path, followSymlinks: bool = true) throws -> FileMetadata {
    var fields = [int64](repeating: 0, count: 16)
    var rc: int32 = 0
    path.Value.withCString { p in
        fields.withUnsafeMutableBufferPointer { ptr in
            rc = cfs_stat_raw(p, followSymlinks ? 1 : 0, ptr.baseAddress!)
        }
    }
    if rc != 0 {
        throw errorFor(rc, "stat", path)
    }
    return unpackMetadata(fields)
}

/// Reads an entire file into memory as bytes.
public func ReadFile(_ path: Path) throws -> [uint8] {
    return try fs_read_file(path)
}

/// Reads an entire UTF-8 text file.
public func ReadText(_ path: Path) throws -> string {
    let bytes = try fs_read_file(path)
    return stringFromBytes(bytes, from: 0, to: bytes.count)
}

/// Writes byte data to a file. If atomic is true, writes to a temporary file and renames it.
public func WriteFile(_ path: Path, _ data: borrowing [uint8], atomic: bool = false) throws {
    try fs_write_file(path, data, atomic: atomic)
}

/// Writes a string to a file as UTF-8.
public func WriteText(_ path: Path, _ text: string, atomic: bool = false) throws {
    let b = bytesFromString(text)
    try fs_write_file(path, b, atomic: atomic)
}

/// Appends bytes to the end of an existing file or creates it.
public func AppendFile(_ path: Path, _ data: borrowing [uint8]) throws {
    try fs_append_file(path, data)
}

/// Creates a new directory. If all is true, creates parent directories as needed.
public func CreateDir(_ path: Path, all: bool = false) throws {
    try fs_create_dir(path, all: all)
}

/// Removes a file, symlink, or empty directory.
public func Remove(_ path: Path) throws {
    try fs_remove(path)
}

/// Recursively removes a path and all of its contents.
public func RemoveAll(_ path: Path) throws {
    var rc: int32 = 0
    path.Value.withCString { p in
        rc = cfs_remove_all(p)
    }
    if rc != 0 {
        throw errorFor(rc, "removeall", path)
    }
}

/// Renames or moves a file or directory from one path to another.
public func Rename(_ from: Path, _ to: Path, replace: bool = true) throws {
    var rc: int32 = 0
    from.Value.withCString { f in
        to.Value.withCString { t in
            rc = cfs_rename(f, t, replace ? 1 : 0)
        }
    }
    if rc != 0 {
        throw errorFor(rc, "rename", from)
    }
}

/// Copies a file or directory.
public func Copy(_ from: Path, _ to: Path, _ options: CopyOptions = CopyOptions()) throws {
    let meta = try fs_metadata(from, followSymlinks: true)
    if meta.IsDir() {
        if !options.Recursive {
            throw FsError.isADirectory("\(from.Value): copy requires recursive: true for directories")
        }
        try fs_create_dir(to, all: true)
        let entries = try ReadDir(from)
        var i = 0
        while i < entries.count {
            let entry = entries[i]
            let destChild = to / entry.Name
            try Copy(entry.Path, destChild, options)
            i += 1
        }
        return
    }

    var rc: int32 = 0
    from.Value.withCString { f in
        to.Value.withCString { t in
            rc = cfs_copy_file(f, t, options.Overwrite ? 1 : 0)
        }
    }
    if rc != 0 {
        throw errorFor(rc, "copy", from)
    }
}

/// Fetches metadata for a path.
public func Metadata(_ path: Path, followSymlinks: bool = true) throws -> FileMetadata {
    return try fs_metadata(path, followSymlinks: followSymlinks)
}

/// Convenience alias for Metadata, matching standard POSIX/Go terminology.
public func Stat(_ path: Path, followSymlinks: bool = true) throws -> FileMetadata {
    return try fs_metadata(path, followSymlinks: followSymlinks)
}

/// Resolves all symlinks and relative path components to produce a canonical absolute path.
public func Canonical(_ path: Path) throws -> Path {
    var chars = [CChar](repeating: 0, count: 1024)
    var rc: int32 = 0
    path.Value.withCString { p in
        chars.withUnsafeMutableBufferPointer { ptr in
            rc = cfs_canonical(p, ptr.baseAddress!, int32(ptr.count))
        }
    }
    if rc != 0 {
        throw errorFor(rc, "canonical", path)
    }
    return Path(string(cString: chars))
}

/// Reads the target path of a symbolic link.
public func ReadLink(_ path: Path) throws -> Path {
    var chars = [CChar](repeating: 0, count: 1024)
    var rc: int32 = 0
    path.Value.withCString { p in
        chars.withUnsafeMutableBufferPointer { ptr in
            rc = cfs_readlink(p, ptr.baseAddress!, int32(ptr.count))
        }
    }
    if rc != 0 {
        throw errorFor(rc, "readlink", path)
    }
    return Path(string(cString: chars))
}

/// Creates a symbolic link pointing to target at link path.
public func Symlink(_ target: Path, at link: Path) throws {
    var rc: int32 = 0
    target.Value.withCString { t in
        link.Value.withCString { l in
            rc = cfs_symlink(t, l)
        }
    }
    if rc != 0 {
        throw errorFor(rc, "symlink", link)
    }
}

/// Creates a unique temporary directory with the given prefix.
public func TempDir(prefix: string = "vertex_fs_") throws -> Path {
    var chars = [CChar](repeating: 0, count: 1024)
    var rc: int32 = 0
    prefix.withCString { pre in
        chars.withUnsafeMutableBufferPointer { ptr in
            rc = cfs_temp_dir(pre, ptr.baseAddress!, int32(ptr.count))
        }
    }
    if rc != 0 {
        throw errorFor(rc, "tempdir", Path(prefix))
    }
    return Path(string(cString: chars))
}
