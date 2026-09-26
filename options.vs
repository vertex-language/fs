package fs

import "io"

/// The kind of file system entry.
public enum FileKind: Hashable, Equatable, CustomStringConvertible {
    case file
    case directory
    case symlink
    case other

    public var description: string {
        switch self {
        case .file: return "file"
        case .directory: return "directory"
        case .symlink: return "symlink"
        case .other: return "other"
        }
    }
}

/// When a file should be created during an open operation.
public enum CreateMode: Hashable, Equatable {
    case never
    case ifMissing
    case always
    case new
}

/// Options configuring how a file is opened.
public struct OpenOptions {
    public var Read: bool = true
    public var Write: bool = false
    public var Append: bool = false
    public var Create: CreateMode = .never
    public var Truncate: bool = false
    public var Mode: uint32 = 0

    public init() {}

    public static var read: OpenOptions {
        var opt = OpenOptions()
        opt.Read = true
        opt.Write = false
        return opt
    }

    public static var write: OpenOptions {
        var opt = OpenOptions()
        opt.Read = false
        opt.Write = true
        opt.Create = .always
        opt.Truncate = true
        return opt
    }

    public static var append: OpenOptions {
        var opt = OpenOptions()
        opt.Read = false
        opt.Write = true
        opt.Append = true
        opt.Create = .ifMissing
        return opt
    }

    func toFlags() -> int32 {
        var f: int32 = 0
        if Read { f |= OpenFlag.read }
        if Write { f |= OpenFlag.write }
        if Append { f |= OpenFlag.append }
        if Truncate { f |= OpenFlag.truncate }
        switch Create {
        case .never:
            break
        case .ifMissing:
            f |= OpenFlag.create
        case .always:
            f |= OpenFlag.create
            f |= OpenFlag.truncate
        case .new:
            f |= OpenFlag.create
            f |= OpenFlag.excl
        }
        return f
    }
}

/// The reference position for a file seek operation: io's, so a File
/// seeks as any io.Seeker does.
public typealias SeekFrom = io.SeekFrom

/// Options controlling file and directory copy behavior.
public struct CopyOptions {
    public var Overwrite: bool = true
    public var Recursive: bool = false

    public init(overwrite: bool = true, recursive: bool = false) {
        self.Overwrite = overwrite
        self.Recursive = recursive
    }
}
