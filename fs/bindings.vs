package fs

enum Code {
    static let ok: int32 = 0
    static let generic: int32 = -1
    static let notFound: int32 = -2
    static let alreadyExists: int32 = -3
    static let permissionDenied: int32 = -4
    static let notDir: int32 = -5
    static let isDir: int32 = -6
    static let dirNotEmpty: int32 = -7
    static let readOnly: int32 = -8
    static let noSpace: int32 = -9
    static let tooManyOpen: int32 = -10
    static let xdev: int32 = -11
    static let invalidPath: int32 = -12
    static let interrupted: int32 = -13
}

enum OpenFlag {
    static let read: int32 = 1
    static let write: int32 = 2
    static let append: int32 = 4
    static let create: int32 = 8
    static let truncate: int32 = 16
    static let excl: int32 = 32
}

enum KindCode {
    static let file: int32 = 1
    static let directory: int32 = 2
    static let symlink: int32 = 3
    static let other: int32 = 4
}

@_silgen_name("cfs_last_error")
func cfs_last_error() -> int32

@_silgen_name("cfs_now")
func cfs_now(_ nanos: UnsafeMutablePointer<int32>?) -> int64

@_silgen_name("cfs_read_file")
func cfs_read_file(_ path: UnsafePointer<CChar>, _ outBuf: UnsafeMutablePointer<UnsafeMutablePointer<uint8>?>,
                   _ outLen: UnsafeMutablePointer<int64>) -> int32

@_silgen_name("cfs_read_file_into")
func cfs_read_file_into(_ path: UnsafePointer<CChar>, _ buf: UnsafeMutableRawPointer,
                        _ maxLen: int64, _ outRead: UnsafeMutablePointer<int64>) -> int32

@_silgen_name("cfs_free_buffer")
func cfs_free_buffer(_ buf: UnsafeMutablePointer<uint8>?)

@_silgen_name("cfs_write_file")
func cfs_write_file(_ path: UnsafePointer<CChar>, _ data: UnsafeRawPointer?,
                    _ len: int64, _ atomic: int32) -> int32

@_silgen_name("cfs_append_file")
func cfs_append_file(_ path: UnsafePointer<CChar>, _ data: UnsafeRawPointer?,
                     _ len: int64) -> int32

@_silgen_name("cfs_open")
func cfs_open(_ path: UnsafePointer<CChar>, _ flags: int32, _ mode: uint32) -> int32

@_silgen_name("cfs_close")
func cfs_close(_ fd: int32) -> int32

@_silgen_name("cfs_read")
func cfs_read(_ fd: int32, _ buf: UnsafeMutableRawPointer, _ count: int32) -> int64

@_silgen_name("cfs_pread")
func cfs_pread(_ fd: int32, _ buf: UnsafeMutableRawPointer, _ count: int32, _ offset: int64) -> int64

@_silgen_name("cfs_write")
func cfs_write(_ fd: int32, _ buf: UnsafeRawPointer, _ count: int32) -> int64

@_silgen_name("cfs_pwrite")
func cfs_pwrite(_ fd: int32, _ buf: UnsafeRawPointer, _ count: int32, _ offset: int64) -> int64

@_silgen_name("cfs_seek")
func cfs_seek(_ fd: int32, _ offset: int64, _ whence: int32) -> int64

@_silgen_name("cfs_truncate")
func cfs_truncate(_ fd: int32, _ length: int64) -> int32

@_silgen_name("cfs_sync")
func cfs_sync(_ fd: int32, _ dataOnly: int32) -> int32

@_silgen_name("cfs_open_dir")
func cfs_open_dir(_ path: UnsafePointer<CChar>, _ confined: int32) -> int32

@_silgen_name("cfs_read_dir_records")
func cfs_read_dir_records(_ dirFd: int32, _ outBuf: UnsafeMutablePointer<uint8>, _ maxBytes: int32,
                         _ outRecordCount: UnsafeMutablePointer<int32>,
                         _ outBytesWritten: UnsafeMutablePointer<int32>) -> int32

@_silgen_name("cfs_mkdir")
func cfs_mkdir(_ path: UnsafePointer<CChar>, _ mode: uint32, _ recursive: int32) -> int32

@_silgen_name("cfs_remove")
func cfs_remove(_ path: UnsafePointer<CChar>) -> int32

@_silgen_name("cfs_remove_all")
func cfs_remove_all(_ path: UnsafePointer<CChar>) -> int32

@_silgen_name("cfs_rename")
func cfs_rename(_ src: UnsafePointer<CChar>, _ dst: UnsafePointer<CChar>, _ replace: int32) -> int32

@_silgen_name("cfs_copy_file")
func cfs_copy_file(_ src: UnsafePointer<CChar>, _ dst: UnsafePointer<CChar>, _ overwrite: int32) -> int32

@_silgen_name("cfs_stat_raw")
func cfs_stat_raw(_ path: UnsafePointer<CChar>, _ follow: int32, _ outFields: UnsafeMutablePointer<int64>) -> int32

@_silgen_name("cfs_fstat_raw")
func cfs_fstat_raw(_ fd: int32, _ outFields: UnsafeMutablePointer<int64>) -> int32

@_silgen_name("cfs_canonical")
func cfs_canonical(_ path: UnsafePointer<CChar>, _ outBuf: UnsafeMutablePointer<CChar>, _ maxLen: int32) -> int32

@_silgen_name("cfs_readlink")
func cfs_readlink(_ path: UnsafePointer<CChar>, _ outBuf: UnsafeMutablePointer<CChar>, _ maxLen: int32) -> int32

@_silgen_name("cfs_symlink")
func cfs_symlink(_ target: UnsafePointer<CChar>, _ link: UnsafePointer<CChar>) -> int32

@_silgen_name("cfs_temp_dir")
func cfs_temp_dir(_ prefix: UnsafePointer<CChar>, _ outBuf: UnsafeMutablePointer<CChar>, _ maxLen: int32) -> int32
