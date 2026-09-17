package fs

// FsError represents every way a file system operation can fail.
public enum FsError: Error {
    case notFound(string)
    case alreadyExists(string)
    case permissionDenied(string)
    case notADirectory(string)
    case isADirectory(string)
    case directoryNotEmpty(string)
    case readOnly(string)
    case noSpace(string)
    case tooManyOpenFiles(string)
    case crossesDevices(string)
    case invalidPath(string)
    case interrupted(string)
    case generic(string)
    case systemError(code: int32, context: string)

    /// Formatted message describing what failed and why.
    public var Message: string {
        switch self {
        case .notFound(let what):
            return "no such file or directory: \(what)"
        case .alreadyExists(let what):
            return "file already exists: \(what)"
        case .permissionDenied(let what):
            return "permission denied: \(what)"
        case .notADirectory(let what):
            return "not a directory: \(what)"
        case .isADirectory(let what):
            return "is a directory: \(what)"
        case .directoryNotEmpty(let what):
            return "directory not empty: \(what)"
        case .readOnly(let what):
            return "read-only file system: \(what)"
        case .noSpace(let what):
            return "no space left on device: \(what)"
        case .tooManyOpenFiles(let what):
            return "too many open files: \(what)"
        case .crossesDevices(let what):
            return "cross-device link: \(what)"
        case .invalidPath(let what):
            return "invalid path: \(what)"
        case .interrupted(let what):
            return "operation interrupted: \(what)"
        case .generic(let what):
            return "operation failed: \(what)"
        case .systemError(let code, let what):
            return "system error \(code): \(what)"
        }
    }
}

// Maps a negative cfs return code to an FsError
func errorFor(_ code: int32, _ op: string, _ path: Path? = nil) -> FsError {
    let what = path != nil ? "\(op) \(path!.Value)" : op
    switch code {
    case Code.notFound:
        return .notFound(what)
    case Code.alreadyExists:
        return .alreadyExists(what)
    case Code.permissionDenied:
        return .permissionDenied(what)
    case Code.notDir:
        return .notADirectory(what)
    case Code.isDir:
        return .isADirectory(what)
    case Code.dirNotEmpty:
        return .directoryNotEmpty(what)
    case Code.readOnly:
        return .readOnly(what)
    case Code.noSpace:
        return .noSpace(what)
    case Code.tooManyOpen:
        return .tooManyOpenFiles(what)
    case Code.xdev:
        return .crossesDevices(what)
    case Code.invalidPath:
        return .invalidPath(what)
    case Code.interrupted:
        return .interrupted(what)
    default:
        let osCode = cfs_last_error()
        return .systemError(code: osCode, context: what)
    }
}
