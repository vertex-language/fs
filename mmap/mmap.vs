// Package mmap maps a file into memory, read-only: its bytes are read in
// place, without copying, and pages come in from disk as they are touched.
// What model weights are loaded through.
package mmap

import "fs"

@_silgen_name("cfs_map")
func cfs_map(_ fd: int32, _ len: int64, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> int32

@_silgen_name("cfs_unmap")
func cfs_unmap(_ addr: UnsafeMutableRawPointer?, _ len: int64) -> int32

/// MapError is a mapping the operating system refused.
public enum MapError: Error {
    case failed(code: int32, path: string)

    public var Message: string {
        switch self {
        case .failed(let code, let path):
            return "cannot map \(path) (cfs error \(code))"
        }
    }
}

/// Mapping is a file's bytes in memory, valid until the last reference to
/// it goes: then the pages are unmapped. An empty file maps to no bytes.
public final class Mapping {
    /// Count is how many bytes are mapped: the file's size.
    public let Count: int
    let _addr: UnsafeMutableRawPointer?

    init(_ addr: UnsafeMutableRawPointer?, _ count: int) {
        self._addr = addr
        self.Count = count
    }

    deinit {
        if _addr != nil {
            _ = cfs_unmap(_addr, int64(Count))
        }
    }

    /// Bytes is the first mapped byte, or nil for an empty file. Reading
    /// past Count is out of the mapping.
    public var Bytes: UnsafePointer<uint8>? {
        if _addr == nil { return nil }
        return UnsafePointer<uint8>(_addr!)
    }

    /// Copy is count bytes from offset, copied out; a range outside the
    /// mapping traps.
    public func Copy(from offset: int, count: int) -> [uint8] {
        precondition(offset >= 0 && count >= 0 && offset + count <= Count, "mmap: range out of the mapping")
        var out = [uint8](repeating: 0, count: count)
        if count == 0 { return out }
        let p = Bytes!
        var i = 0
        while i < count {
            out[i] = p[offset + i]
            i += 1
        }
        return out
    }
}

/// Map maps the whole file at path, read-only.
public func Map(_ path: fs.Path) throws -> Mapping {
    let f = try fs.Open(path)
    defer { try? f.Close() }
    let size = try f.Metadata().Size
    if size == 0 {
        return Mapping(nil, 0)
    }
    var addr: UnsafeMutableRawPointer? = nil
    let rc = cfs_map(f.Fd, size, &addr)
    if rc != 0 {
        throw MapError.failed(code: rc, path: path.Value)
    }
    return Mapping(addr, int(size))
}
