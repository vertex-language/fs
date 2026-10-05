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

/// A file's contents as debugfs reads them from an image, or nil where there is no debugfs.
func debugfsCat(_ image: string, _ file: string) async -> string? {
    for d in ["/opt/homebrew/opt/e2fsprogs/sbin/debugfs", "/usr/local/opt/e2fsprogs/sbin/debugfs", "/sbin/debugfs", "/usr/sbin/debugfs"]
        where fs.Exists(fs.Path(d)) {
        guard let out = try? await process.Command(d, ["-R", "cat \(file)", image]).Output(), out.Status.Success else { return nil }
        return string(decoding: out.Stdout, as: UTF8.self)
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
    // Files, in directories, on a file and in memory.
    var withFiles = ext4.FormatOptions()
    withFiles.BlockSize = 1024
    let big = [uint8](repeating: 0x61, count: 3000)
    withFiles.Files = [ext4.File("etc/permissions/feature.xml", [uint8]("<permissions />\n".utf8)),
                       ext4.File("etc/empty", []), ext4.File("bin/tool", big, mode: 0o755), ext4.File("readme", [uint8]("hi\n".utf8))]
    do {
        let path = dir + "/test-ext4-files.img"
        try ext4.Format(fs.Path(path), size: 4 << 20, withFiles)
        if let clean = await fsck(path) { check(clean, "with files, e2fsck finds it clean") }
        if let text = await debugfsCat(path, "/etc/permissions/feature.xml") { check(text == "<permissions />\n", "a file in a directory reads back") }
        if let text = await debugfsCat(path, "/bin/tool") { check(text.utf8.count == 3000, "a three-block file reads back whole") }
        let bytes = try ext4.FormatBytes(size: 4 << 20, withFiles)
        check(bytes.count == 4 << 20 && bytes[1024 + 0x38] == 0x53 && bytes[1024 + 0x39] == 0xEF, "FormatBytes makes one in memory")
        let mem = dir + "/test-ext4-memory.img"
        let f = try fs.Create(fs.Path(mem))
        try f.Write(bytes, at: 0)
        try f.Close()
        if let clean = await fsck(mem) { check(clean, "e2fsck finds that clean too") }
        if let text = await debugfsCat(mem, "/readme") { check(text == "hi\n", "and its files read back") }
    } catch {
        check(false, "with files: \(error)")
    }
    var twice = ext4.FormatOptions()
    twice.Files = [ext4.File("a", []), ext4.File("a/b", [])]
    do {
        _ = try ext4.FormatBytes(size: 1 << 20, twice)
        check(false, "a file used as a directory is refused")
    } catch {
        check(true, "a file used as a directory is refused (\(error))")
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
