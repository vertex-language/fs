package fs

/// A moment on the wall clock, measured in seconds and nanoseconds since the Unix epoch.
public struct Timestamp: Hashable, Comparable, CustomStringConvertible {
    public let UnixSeconds: int64
    public let Nanoseconds: int32

    public init(unixSeconds: int64, nanoseconds: int64 = 0) {
        var s = unixSeconds
        var ns = nanoseconds
        if ns >= 1000000000 {
            s += ns / 1000000000
            ns = ns % 1000000000
        } else if ns < 0 {
            let borrow = ((-ns) + 999999999) / 1000000000
            s -= borrow
            ns += borrow * 1000000000
        }
        self.UnixSeconds = s
        self.Nanoseconds = int32(ns)
    }

    public static let UnixEpoch = Timestamp(unixSeconds: 0)

    public static func Now() -> Timestamp {
        var nanos: int32 = 0
        let secs = cfs_now(&nanos)
        return Timestamp(unixSeconds: secs, nanoseconds: int64(nanos))
    }

    public var description: string {
        return "\(UnixSeconds)s"
    }

    public static func < (lhs: Timestamp, rhs: Timestamp) -> bool {
        if lhs.UnixSeconds != rhs.UnixSeconds {
            return lhs.UnixSeconds < rhs.UnixSeconds
        }
        return lhs.Nanoseconds < rhs.Nanoseconds
    }

    public static func == (lhs: Timestamp, rhs: Timestamp) -> bool {
        return lhs.UnixSeconds == rhs.UnixSeconds && lhs.Nanoseconds == rhs.Nanoseconds
    }
}

/// Platform-specific Unix metadata fields.
public struct UnixMetadata {
    public let Mode: uint32
    public let Uid: uint32
    public let Gid: uint32
    public let Inode: uint64
    public let Device: uint64

    public init(mode: uint32, uid: uint32, gid: uint32, inode: uint64, device: uint64) {
        self.Mode = mode
        self.Uid = uid
        self.Gid = gid
        self.Inode = inode
        self.Device = device
    }
}

/// File system item metadata.
public struct FileMetadata {
    public let Kind: FileKind
    public let Size: int64
    public let Modified: Timestamp
    public let Accessed: Timestamp
    public let Created: Timestamp?
    public let ReadOnly: bool
    public let Unix: UnixMetadata?

    public init(kind: FileKind, size: int64, modified: Timestamp, accessed: Timestamp,
                created: Timestamp?, readOnly: bool, unix: UnixMetadata?) {
        self.Kind = kind
        self.Size = size
        self.Modified = modified
        self.Accessed = accessed
        self.Created = created
        self.ReadOnly = readOnly
        self.Unix = unix
    }

    public func IsFile() -> bool { return Kind == .file }
    public func IsDir() -> bool { return Kind == .directory }
    public func IsSymlink() -> bool { return Kind == .symlink }
}

func unpackMetadata(_ fields: [int64]) -> FileMetadata {
    let rawKind = int32(fields[0])
    var kind: FileKind = .other
    if rawKind == KindCode.file { kind = .file }
    else if rawKind == KindCode.directory { kind = .directory }
    else if rawKind == KindCode.symlink { kind = .symlink }

    let size = fields[1]
    let mod = Timestamp(unixSeconds: fields[2], nanoseconds: fields[3])
    let acc = Timestamp(unixSeconds: fields[4], nanoseconds: fields[5])
    var created: Timestamp? = nil
    if fields[6] > 0 {
        created = Timestamp(unixSeconds: fields[6], nanoseconds: fields[7])
    }
    let mode = uint32(fields[8])
    let uid = uint32(fields[9])
    let gid = uint32(fields[10])
    let ino = uint64(fields[11])
    let dev = uint64(fields[12])
    let readOnly = fields[13] != 0

    let unix = UnixMetadata(mode: mode, uid: uid, gid: gid, inode: ino, device: dev)

    return FileMetadata(
        kind: kind,
        size: size,
        modified: mod,
        accessed: acc,
        created: created,
        readOnly: readOnly,
        unix: unix
    )
}
