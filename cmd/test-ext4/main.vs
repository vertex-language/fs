// Formats images with fs/ext4 and checks them: by reading the superblock
// back, and with e2fsck where the machine has it (a test-only oracle).
//
//     vsc run test-ext4 [-- out-dir]
package main

import (
    "fs"
    "fs/ext4"
    "os/process"
)

var failures = 0

func check(_ ok: bool, _ what: string) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { failures += 1 }
}

/// e2fsck's verdict on an image (forced, changing nothing), or nil where there is no e2fsck.
func fsck(_ path: string) async -> bool? {
    for e2 in ["/opt/homebrew/opt/e2fsprogs/sbin/e2fsck", "/usr/local/opt/e2fsprogs/sbin/e2fsck", "/sbin/e2fsck", "/usr/sbin/e2fsck"]
        where fs.Exists(fs.Path(e2)) {
        guard let out = try? await process.Command(e2, ["-fn", path]).Output() else { return nil }
        return out.Status.Success
    }
    return nil
}

/// Whether the superblock's has_journal feature is set and names inode 8.
func hasJournal(_ path: fs.Path) -> bool {
    guard let f = try? fs.Open(path) else { return false }
    defer { try? f.Close() }
    var b = [uint8](repeating: 0, count: 1024)
    guard let n = try? f.Read(into: &b, at: 1024), n == 1024 else { return false }
    return b[92] & 0x4 != 0 && b[224] == 8
}

func main() async -> int32 {
    let dir = process.Args.count > 1 ? process.Args[1] : "/tmp"
    let sizes: [int64] = [64 << 20, 1 << 30, 6 << 30]
    for size in sizes {
        let path = fs.Path(dir + "/test-ext4-\(size >> 20)M.img")
        do {
            try ext4.Format(path, size: size)
        } catch {
            check(false, "format \(size >> 20) MiB: \(error)")
            continue
        }
        check(ext4.IsExt(path), "a \(size >> 20) MiB image has an ext superblock")
        let st = try? fs.Metadata(path)
        check(st?.Size == size, "and is \(size) bytes")
        if let clean = await fsck(path.description) { check(clean, "e2fsck finds it clean") }
        check(hasJournal(path), "it has a journal")
    }
    var small = ext4.FormatOptions()
    small.BlockSize = 1024
    small.Label = "tiny"
    do {
        try ext4.Format(fs.Path(dir + "/test-ext4-1k.img"), size: 8 << 20, small)
        check(ext4.IsExt(fs.Path(dir + "/test-ext4-1k.img")), "1 KiB blocks, labeled")
        if let clean = await fsck(dir + "/test-ext4-1k.img") { check(clean, "e2fsck finds it clean") }
    } catch {
        check(false, "1 KiB blocks: \(error)")
    }
    do {
        try ext4.Format(fs.Path(dir + "/test-ext4-none.img"), size: 4096)
        check(false, "a 4 KiB image is refused")
    } catch {
        check(true, "a 4 KiB image is refused (\(error))")
    }
    print(failures == 0 ? "all passed" : "\(failures) failed")
    return failures == 0 ? 0 : 1
}
