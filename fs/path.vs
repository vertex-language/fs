package fs

func bytesFromString(_ text: string) -> [uint8] {
    var out: [uint8] = []
    for b in text.utf8 {
        out.append(b)
    }
    return out
}

func stringFromBytes(_ bytes: [uint8], from start: int, to end: int) -> string {
    if start >= end { return "" }
    var chars: [CChar] = []
    var i = start
    while i < end {
        chars.append(CChar(truncatingIfNeeded: bytes[i]))
        i += 1
    }
    chars.append(0)
    return string(cString: chars)
}

/// A strongly-typed representation of a file system path.
public struct Path: Hashable, CustomStringConvertible, Equatable {
    public let Value: string

    public init(_ text: string) {
        self.Value = text
    }

    public init(stringLiteral value: string) {
        self.Value = value
    }

    public init(bytes: [uint8]) {
        self.Value = stringFromBytes(bytes, from: 0, to: bytes.count)
    }

    public var description: string {
        return Value
    }

    public func String() -> string {
        return Value
    }

    public var Bytes: [uint8] {
        return bytesFromString(Value)
    }

    public func IsAbsolute() -> bool {
        let b = Bytes
        if b.isEmpty { return false }
        if b[0] == 47 { return true } // '/'
        // Check Windows drive letter: "C:/" or "C:\"
        if b.count >= 2 && b[1] == 58 { // ':'
            return true
        }
        return false
    }

    /// The trailing name component of the path.
    public func Name() -> string? {
        let b = Bytes
        if b.isEmpty { return nil }
        var end = b.count
        // Trim trailing slashes
        while end > 1 && b[end - 1] == 47 {
            end -= 1
        }
        var i = end - 1
        while i >= 0 {
            if b[i] == 47 {
                return stringFromBytes(b, from: i + 1, to: end)
            }
            i -= 1
        }
        return stringFromBytes(b, from: 0, to: end)
    }

    /// The parent directory component of the path.
    public func Parent() -> Path? {
        let b = Bytes
        if b.isEmpty { return nil }
        var end = b.count
        while end > 1 && b[end - 1] == 47 {
            end -= 1
        }
        var i = end - 1
        while i >= 0 {
            if b[i] == 47 {
                if i == 0 {
                    return Path("/")
                }
                return Path(stringFromBytes(b, from: 0, to: i))
            }
            i -= 1
        }
        return nil
    }

    /// The file extension, excluding the leading dot.
    public func Extension() -> string? {
        guard let name = Name() else { return nil }
        let b = bytesFromString(name)
        var i = b.count - 1
        while i > 0 {
            if b[i] == 46 { // '.'
                return stringFromBytes(b, from: i + 1, to: b.count)
            }
            i -= 1
        }
        return nil
    }

    /// The file stem: the Name excluding its Extension.
    public func Stem() -> string? {
        guard let name = Name() else { return nil }
        let b = bytesFromString(name)
        var i = b.count - 1
        while i > 0 {
            if b[i] == 46 { // '.'
                return stringFromBytes(b, from: 0, to: i)
            }
            i -= 1
        }
        return name
    }

    /// Returns a new Path with the extension replaced or appended.
    public func WithExtension(_ ext: string) -> Path {
        let stem = Stem() ?? ""
        let parent = Parent()
        let dot = ext.isEmpty ? "" : (bytesFromString(ext).first == 46 ? "" : ".")
        let newName = "\(stem)\(dot)\(ext)"
        if let p = parent {
            return p / newName
        }
        return Path(newName)
    }

    /// Joins another Path to this one.
    public func Join(_ other: Path) -> Path {
        if other.IsAbsolute() {
            return other
        }
        if Value.isEmpty || Value == "." {
            return other
        }
        if other.Value.isEmpty || other.Value == "." {
            return self
        }
        let b = Bytes
        if b.last == 47 { // '/'
            return Path("\(Value)\(other.Value)")
        }
        return Path("\(Value)/\(other.Value)")
    }

    /// Lexically normalizes the path without touching the disk.
    public func Lexically() -> Path {
        let b = Bytes
        if b.isEmpty { return Path(".") }

        let isAbs = IsAbsolute()
        var parts: [string] = []
        var i = 0
        while i < b.count {
            while i < b.count && b[i] == 47 {
                i += 1
            }
            if i >= b.count { break }
            let start = i
            while i < b.count && b[i] != 47 {
                i += 1
            }
            let part = stringFromBytes(b, from: start, to: i)
            if part == "." {
                continue
            } else if part == ".." {
                if !parts.isEmpty && parts.last != ".." {
                    _ = parts.removeLast()
                } else if !isAbs {
                    parts.append("..")
                }
            } else {
                parts.append(part)
            }
        }

        if parts.isEmpty {
            return isAbs ? Path("/") : Path(".")
        }

        var res = isAbs ? "/" : ""
        var idx = 0
        while idx < parts.count {
            if idx > 0 || isAbs {
                if !res.hasSuffix("/") { res += "/" }
            }
            res += parts[idx]
            idx += 1
        }
        return Path(res)
    }

    /// Computes the relative path from base to this path.
    public func Relative(to base: Path) -> Path? {
        let normSelf = Lexically()
        let normBase = base.Lexically()

        if normSelf.IsAbsolute() != normBase.IsAbsolute() {
            return nil
        }

        let selfParts = normSelf.componentsList()
        let baseParts = normBase.componentsList()

        var common = 0
        while common < selfParts.count && common < baseParts.count && selfParts[common] == baseParts[common] {
            common += 1
        }

        var resultParts: [string] = []
        var up = common
        while up < baseParts.count {
            resultParts.append("..")
            up += 1
        }
        var down = common
        while down < selfParts.count {
            resultParts.append(selfParts[down])
            down += 1
        }

        if resultParts.isEmpty {
            return Path(".")
        }

        var out = resultParts[0]
        var i = 1
        while i < resultParts.count {
            out += "/\(resultParts[i])"
            i += 1
        }
        return Path(out)
    }

    /// Checks if this path starts with the given prefix path.
    public func StartsWith(_ prefix: Path) -> bool {
        let selfParts = Lexically().componentsList()
        let preParts = prefix.Lexically().componentsList()
        if preParts.count > selfParts.count { return false }
        var i = 0
        while i < preParts.count {
            if selfParts[i] != preParts[i] { return false }
            i += 1
        }
        return true
    }

    func componentsList() -> [string] {
        let b = Bytes
        var list: [string] = []
        var i = 0
        while i < b.count {
            while i < b.count && b[i] == 47 { i += 1 }
            if i >= b.count { break }
            let start = i
            while i < b.count && b[i] != 47 { i += 1 }
            list.append(stringFromBytes(b, from: start, to: i))
        }
        return list
    }

    public static func / (lhs: Path, rhs: string) -> Path {
        return lhs.Join(Path(rhs))
    }

    public static func / (lhs: Path, rhs: Path) -> Path {
        return lhs.Join(rhs)
    }

    public static func == (lhs: Path, rhs: Path) -> bool {
        return lhs.Value == rhs.Value
    }
}
