package memory

import "fs"

func hasSlash(_ s: string) -> bool {
    for b in s.utf8 {
        if b == 47 { return true }
    }
    return false
}

struct MemEntry {
    var path: string
    var isDir: bool
    var data: [uint8]
}

/// An in-memory mock file system implementing fs.FileSystem.
public class MemoryFileSystem: fs.FileSystem {
    var entries: [MemEntry] = []

    public init() {
        entries.append(MemEntry(path: "/", isDir: true, data: []))
    }

    /// Adds or replaces a file in the in-memory file system.
    public func AddFile(_ path: fs.Path, data: [uint8]) {
        let norm = path.Lexically().Value
        var i = 0
        while i < entries.count {
            if entries[i].path == norm {
                entries[i] = MemEntry(path: norm, isDir: false, data: data)
                return
            }
            i += 1
        }
        entries.append(MemEntry(path: norm, isDir: false, data: data))
    }

    /// Adds or replaces a text file in the in-memory file system.
    public func AddText(_ path: fs.Path, text: string) {
        var b: [uint8] = []
        for byte in text.utf8 {
            b.append(byte)
        }
        AddFile(path, data: b)
    }

    public func ReadFile(_ path: fs.Path) throws -> [uint8] {
        let norm = path.Lexically().Value
        var i = 0
        while i < entries.count {
            if entries[i].path == norm {
                if entries[i].isDir {
                    throw fs.FsError.isADirectory(path.Value)
                }
                return entries[i].data
            }
            i += 1
        }
        throw fs.FsError.notFound(path.Value)
    }

    public func ReadDir(_ path: fs.Path) throws -> [fs.DirEntry] {
        let norm = path.Lexically().Value
        var foundDir = false
        if norm == "/" || norm == "." || norm == "" {
            foundDir = true
        } else {
            var i = 0
            while i < entries.count {
                if entries[i].path == norm && entries[i].isDir {
                    foundDir = true
                    break
                }
                i += 1
            }
        }
        if !foundDir {
            throw fs.FsError.notFound(path.Value)
        }

        var results: [fs.DirEntry] = []
        var prefix = norm
        if prefix != "/" && !prefix.isEmpty {
            prefix += "/"
        }

        var i = 0
        while i < entries.count {
            let p = entries[i].path
            if p != norm && p.hasPrefix(prefix) {
                let rest = fs.Path(p).Relative(to: fs.Path(norm))?.Value ?? ""
                if !rest.isEmpty && !hasSlash(rest) {
                    let k: fs.FileKind = entries[i].isDir ? .directory : .file
                    results.append(fs.DirEntry(path: fs.Path(p), name: rest, kind: k))
                }
            }
            i += 1
        }
        return results
    }

    public func Metadata(_ path: fs.Path) throws -> fs.FileMetadata {
        let norm = path.Lexically().Value
        var i = 0
        while i < entries.count {
            if entries[i].path == norm {
                let k: fs.FileKind = entries[i].isDir ? .directory : .file
                let sz = int64(entries[i].data.count)
                let now = fs.Timestamp.Now()
                return fs.FileMetadata(
                    kind: k,
                    size: sz,
                    modified: now,
                    accessed: now,
                    created: now,
                    readOnly: false,
                    unix: nil
                )
            }
            i += 1
        }
        throw fs.FsError.notFound(path.Value)
    }
}
