package fs

/// An open file handle.
public struct File {
    public let Fd: int32
    public let Path: Path

    public init(fd: int32, path: Path) {
        self.Fd = fd
        self.Path = path
    }

    /// Reads up to buffer.count bytes into buffer. Returns number of bytes read (0 at EOF).
    public func Read(into buffer: inout [uint8]) throws -> int {
        if buffer.isEmpty { return 0 }
        let count = int32(buffer.count)
        let n = buffer.withUnsafeMutableBytes { raw in
            cfs_read(Fd, raw.baseAddress!, count)
        }
        if n < 0 {
            throw errorFor(int32(n), "read", Path)
        }
        return int(n)
    }

    /// Reads up to buffer.count bytes starting at offset without changing the file position.
    public func Read(into buffer: inout [uint8], at offset: int64) throws -> int {
        if buffer.isEmpty { return 0 }
        let count = int32(buffer.count)
        let n = buffer.withUnsafeMutableBytes { raw in
            cfs_pread(Fd, raw.baseAddress!, count, offset)
        }
        if n < 0 {
            throw errorFor(int32(n), "pread", Path)
        }
        return int(n)
    }

    /// Reads all remaining bytes from the file up to limit.
    public func ReadToEnd(limit: int = 100 * 1024 * 1024) throws -> [uint8] {
        var out: [uint8] = []
        var buf = [uint8](repeating: 0, count: 65536)
        while true {
            let n = try Read(into: &buf)
            if n == 0 { break }
            if out.count + n > limit {
                throw FsError.noSpace("\(Path.Value): read limit exceeded")
            }
            var i = 0
            while i < n {
                out.append(buf[i])
                i += 1
            }
        }
        return out
    }

    /// Writes every byte of data to the file.
    public func Write(_ data: borrowing [uint8]) throws {
        if data.isEmpty { return }
        var written = 0
        while written < data.count {
            let chunk = int32(data.count - written)
            let n = data.withUnsafeBytes { raw in
                cfs_write(Fd, raw.baseAddress! + written, chunk)
            }
            if n < 0 {
                throw errorFor(int32(n), "write", Path)
            }
            if n == 0 {
                throw FsError.generic("write to \(Path.Value)")
            }
            written += int(n)
        }
    }

    /// Writes data starting at offset without changing the file position.
    public func Write(_ data: borrowing [uint8], at offset: int64) throws {
        if data.isEmpty { return }
        var written = 0
        while written < data.count {
            let chunk = int32(data.count - written)
            let curOffset = offset + int64(written)
            let n = data.withUnsafeBytes { raw in
                cfs_pwrite(Fd, raw.baseAddress! + written, chunk, curOffset)
            }
            if n < 0 {
                throw errorFor(int32(n), "pwrite", Path)
            }
            if n == 0 {
                throw FsError.generic("pwrite to \(Path.Value)")
            }
            written += int(n)
        }
    }

    /// Writes text as UTF-8.
    public func WriteText(_ text: string) throws {
        let b = bytesFromString(text)
        try Write(b)
    }

    /// Seeks to a new position.
    public func Seek(_ to: SeekFrom) throws -> int64 {
        var offset: int64 = 0
        var whence: int32 = 0
        switch to {
        case .start(let pos):
            offset = pos
            whence = 0
        case .current(let pos):
            offset = pos
            whence = 1
        case .end(let pos):
            offset = pos
            whence = 2
        }
        let pos = cfs_seek(Fd, offset, whence)
        if pos < 0 {
            throw errorFor(int32(pos), "seek", Path)
        }
        return pos
    }

    /// Truncates or extends the file to length bytes.
    public func SetLength(_ length: int64) throws {
        let rc = cfs_truncate(Fd, length)
        if rc != 0 {
            throw errorFor(rc, "truncate", Path)
        }
    }

    /// Flushes unwritten data and metadata to disk.
    public func Sync(dataOnly: bool = false) throws {
        let rc = cfs_sync(Fd, dataOnly ? 1 : 0)
        if rc != 0 {
            throw errorFor(rc, "sync", Path)
        }
    }

    /// Inspects file metadata from the open file descriptor.
    public func Metadata() throws -> FileMetadata {
        var fields = [int64](repeating: 0, count: 16)
        let rc = fields.withUnsafeMutableBufferPointer { ptr in
            cfs_fstat_raw(Fd, ptr.baseAddress!)
        }
        if rc != 0 {
            throw errorFor(rc, "fstat", Path)
        }
        return unpackMetadata(fields)
    }

    public func Stat() throws -> FileMetadata {
        return try Metadata()
    }

    /// Closes the open file handle.
    public func Close() throws {
        let rc = cfs_close(Fd)
        if rc != 0 {
            throw errorFor(rc, "close", Path)
        }
    }
}

func fs_open(_ path: Path, _ options: OpenOptions = OpenOptions()) throws -> File {
    let flags = options.toFlags()
    let mode = options.Mode
    var fd: int32 = -1
    path.Value.withCString { p in
        fd = cfs_open(p, flags, mode)
    }
    if fd < 0 {
        throw errorFor(fd, "open", path)
    }
    return File(fd: fd, path: path)
}

/// Opens a file at path with options.
public func Open(_ path: Path, _ options: OpenOptions = OpenOptions()) throws -> File {
    return try fs_open(path, options)
}

/// Creates or truncates a file at path for writing.
public func Create(_ path: Path) throws -> File {
    var opt = OpenOptions()
    opt.Read = false
    opt.Write = true
    opt.Create = .always
    opt.Truncate = true
    return try Open(path, opt)
}
