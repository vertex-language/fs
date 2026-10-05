// Package ext4 makes and recognizes ext4 file systems in disk images:
// what mke2fs does, in Vertex, for tools that build disks for virtual
// machines (Android's userdata, a container's root).
//
// Format writes an empty file system: a root directory and lost+found,
// extents, 256-byte inodes, superblock copies in sparse groups, and a
// journal; Linux mounts it as ext4, and e2fsck finds it clean.
package ext4

import (
    "crypto/rand"
    "fs"
)

/// FormatError is a size or option Format can't make a file system of.
public enum FormatError: Error, CustomStringConvertible {
    case tooSmall(int64)
    case badOption(string)

    public var description: string {
        switch self {
        case .tooSmall(let n): return "\(n) bytes is too small for an ext4 file system"
        case .badOption(let s): return s
        }
    }
}

/// How Format lays the file system out.
public struct FormatOptions {
    /// Bytes a block: 1024, 2048 or 4096.
    public var BlockSize = 4096
    /// Bytes of disk for each inode (mke2fs's -i).
    public var BytesPerInode = 16384
    /// The volume's name, up to 16 bytes.
    public var Label = ""
    /// The share of blocks only root may use, in percent.
    public var ReservedPercent = 0
    /// A journal (ext3/ext4's), sized as mke2fs sizes it, so the file
    /// system comes back consistent after an unclean stop. File systems
    /// under 2048 blocks have none.
    public var Journal = true

    public init() {}
}

// Feature bits.
let compatHasJournal: uint32 = 0x4
let compatExtAttr: uint32 = 0x8
let incompatFiletype: uint32 = 0x2
let incompatExtents: uint32 = 0x40
let roCompatSparseSuper: uint32 = 0x1
let roCompatLargeFile: uint32 = 0x2
let roCompatDirNlink: uint32 = 0x20
let roCompatExtraIsize: uint32 = 0x40

let inodeSize = 256
let extraIsize = 32
let rootInode = 2
let journalInode = 8
let lostFoundInode = 11
let firstInode = 11

/// Whether the image at `path` holds an ext2, ext3 or ext4 file system.
public func IsExt(_ path: fs.Path) -> bool {
    guard let f = try? fs.Open(path) else { return false }
    defer { try? f.Close() }
    var b = [uint8](repeating: 0, count: 2)
    guard let n = try? f.Read(into: &b, at: 1024 + 0x38), n == 2 else { return false }
    return b[0] == 0x53 && b[1] == 0xEF
}

/// Makes `path` a `size`-byte disk image holding an empty ext4 file
/// system. Whatever the file held is discarded; the image is sparse.
public func Format(_ path: fs.Path, size: int64, _ o: FormatOptions = FormatOptions()) throws {
    let bs = o.BlockSize
    if bs != 1024 && bs != 2048 && bs != 4096 { throw FormatError.badOption("block size \(bs): it's 1024, 2048 or 4096") }
    if o.Label.utf8.count > 16 { throw FormatError.badOption("label \(o.Label) is longer than 16 bytes") }
    let blocks = int(size / int64(bs))
    let firstData = bs == 1024 ? 1 : 0
    let perGroup = bs * 8
    let groups = (blocks - firstData + perGroup - 1) / perGroup
    if blocks < 64 || groups < 1 { throw FormatError.tooSmall(size) }
    // Inodes: a whole number of inode-table blocks a group, a multiple of 8.
    let perBlock = bs / inodeSize
    var inodesPerGroup = max(16, int(size / int64(o.BytesPerInode)) / groups)
    inodesPerGroup = min(inodesPerGroup, bs * 8)
    inodesPerGroup = (inodesPerGroup + perBlock - 1) / perBlock * perBlock
    while inodesPerGroup % 8 != 0 { inodesPerGroup += perBlock }
    let tableBlocks = inodesPerGroup / perBlock
    let gdtBlocks = (groups * 32 + bs - 1) / bs

    // Where each group's metadata goes.
    var layout: [GroupLayout] = []
    for g in 0..<groups {
        let start = firstData + g * perGroup
        let count = min(perGroup, blocks - start)
        var at = start
        let backup = hasSuperblock(g)
        if backup { at += 1 + gdtBlocks }
        let l = GroupLayout(Start: start, Count: count, Backup: backup, BlockBitmap: at, InodeBitmap: at + 1, InodeTable: at + 2,
                            FirstFree: at + 2 + tableBlocks)
        if l.FirstFree >= start + count { throw FormatError.tooSmall(size) }
        layout.append(l)
    }
    // Blocks taken after each group's metadata: root's and lost+found's
    // one directory block each, first in group 0; then the journal, in
    // one run, in the first group with room for it.
    var taken = [int](repeating: 0, count: groups)
    let rootBlock = layout[0].FirstFree
    let lostFoundBlock = rootBlock + 1
    if lostFoundBlock >= layout[0].Start + layout[0].Count { throw FormatError.tooSmall(size) }
    taken[0] = 2
    let journalBlocks = o.Journal ? defaultJournalBlocks(blocks) : 0
    var journalStart = 0
    if journalBlocks > 0 {
        var found = -1
        for g in 0..<groups where layout[g].Start + layout[g].Count - (layout[g].FirstFree + taken[g]) >= journalBlocks {   // vsc_TODO #55
            found = g
            break
        }
        if found < 0 { throw FormatError.tooSmall(size) }
        journalStart = layout[found].FirstFree + taken[found]
        taken[found] += journalBlocks
    }

    let f = try fs.Create(path)
    defer { try? f.Close() }
    try f.SetLength(0)
    try f.SetLength(size)

    let now = uint32(truncatingIfNeeded: fs.Timestamp.Now().UnixSeconds)
    var totalFreeBlocks = 0
    var desc = Bytes(groups * 32)
    for (g, l) in layout.enumerated() {
        let used = l.FirstFree - l.Start + taken[g]
        let free = l.Count - used
        totalFreeBlocks += free
        // Block bitmap: metadata and what's taken after it; past the end of a short last group, set.
        var bb = Bytes(bs)
        for i in 0..<used { bb.SetBit(i) }
        for i in l.Count..<(bs * 8) { bb.SetBit(i) }
        try f.Write(bb.B, at: int64(l.BlockBitmap) * int64(bs))
        // Inode bitmap: the reserved inodes and lost+found; past inodesPerGroup, set.
        var ib = Bytes(bs)
        if g == 0 { for i in 0..<firstInode { ib.SetBit(i) } }
        for i in inodesPerGroup..<(bs * 8) { ib.SetBit(i) }
        try f.Write(ib.B, at: int64(l.InodeBitmap) * int64(bs))
        let d = g * 32
        desc.U32(d, uint32(l.BlockBitmap))
        desc.U32(d + 4, uint32(l.InodeBitmap))
        desc.U32(d + 8, uint32(l.InodeTable))
        desc.U16(d + 12, uint16(free))
        desc.U16(d + 14, uint16(inodesPerGroup - (g == 0 ? firstInode : 0)))
        desc.U16(d + 16, uint16(g == 0 ? 2 : 0))
    }

    // The two directories: inodes in group 0's table, one block each.
    try f.Write(inode(mode: 0x41ED, links: 3, block: rootBlock, count: 1, bs: bs, now: now).B,
                at: int64(layout[0].InodeTable) * int64(bs) + int64((rootInode - 1) * inodeSize))
    try f.Write(inode(mode: 0x41C0, links: 2, block: lostFoundBlock, count: 1, bs: bs, now: now).B,
                at: int64(layout[0].InodeTable) * int64(bs) + int64((lostFoundInode - 1) * inodeSize))
    var root = Bytes(bs)
    var at = root.Entry(0, inode: rootInode, name: ".", recLen: 12)
    at = root.Entry(at, inode: rootInode, name: "..", recLen: 12)
    _ = root.Entry(at, inode: lostFoundInode, name: "lost+found", recLen: bs - at)
    try f.Write(root.B, at: int64(rootBlock) * int64(bs))
    var lf = Bytes(bs)
    at = lf.Entry(0, inode: lostFoundInode, name: ".", recLen: 12)
    _ = lf.Entry(at, inode: rootInode, name: "..", recLen: bs - at)
    try f.Write(lf.B, at: int64(lostFoundBlock) * int64(bs))

    // The journal: a regular file of its own inode, its first block the
    // journal's superblock (big-endian), saying it's empty.
    var journal = Bytes(inodeSize)
    if journalBlocks > 0 {
        journal = inode(mode: 0x8180, links: 1, block: journalStart, count: journalBlocks, bs: bs, now: now)
        try f.Write(journal.B, at: int64(layout[0].InodeTable) * int64(bs) + int64((journalInode - 1) * inodeSize))
        var j = Bytes(bs)
        j.BE32(0x0, 0xC03B3998)      // magic
        j.BE32(0x4, 4)               // a version 2 superblock
        j.BE32(0xC, uint32(bs))
        j.BE32(0x10, uint32(journalBlocks))
        j.BE32(0x14, 1)              // the log starts after this block
        j.BE32(0x18, 1)              // the next transaction's number
        j.BE32(0x40, 1)              // one file system uses it
        try f.Write(j.B, at: int64(journalStart) * int64(bs))
    }

    // The superblock, and its copies with their group's number.
    let inodes = inodesPerGroup * groups
    var sb = Bytes(1024)
    sb.U32(0, uint32(inodes))
    sb.U32(4, uint32(blocks))
    sb.U32(8, uint32(blocks / 100 * o.ReservedPercent))
    sb.U32(12, uint32(totalFreeBlocks))
    sb.U32(16, uint32(inodes - firstInode))
    sb.U32(20, uint32(firstData))
    sb.U32(24, uint32(bs == 1024 ? 0 : (bs == 2048 ? 1 : 2)))
    sb.U32(28, uint32(bs == 1024 ? 0 : (bs == 2048 ? 1 : 2)))
    sb.U32(32, uint32(perGroup))
    sb.U32(36, uint32(perGroup))
    sb.U32(40, uint32(inodesPerGroup))
    sb.U32(48, now)
    sb.U16(54, 0xFFFF)          // no mount-count check
    sb.U16(56, 0xEF53)
    sb.U16(58, 1)               // clean
    sb.U16(60, 1)               // on errors: continue
    sb.U32(64, now)
    sb.U32(76, 1)               // dynamic revision
    sb.U32(84, uint32(firstInode))
    sb.U16(88, uint16(inodeSize))
    sb.U32(92, compatExtAttr | (journalBlocks > 0 ? compatHasJournal : 0))
    sb.U32(96, incompatFiletype | incompatExtents)
    sb.U32(100, roCompatSparseSuper | roCompatLargeFile | roCompatDirNlink | roCompatExtraIsize)
    let uuid = randomBytes(16)
    for i in 0..<16 { sb.B[104 + i] = uuid[i] }
    if journalBlocks > 0 {
        sb.U32(224, uint32(journalInode))
        // A copy of the journal inode's block map and size, for e2fsck.
        for i in 0..<15 { sb.U32(268 + i * 4, journal.LE32(40 + i * 4)) }
        sb.U32(268 + 15 * 4, 0)
        sb.U32(268 + 16 * 4, uint32(journalBlocks * bs))
        sb.B[253] = 1
    }
    for (i, c) in o.Label.utf8.enumerated() { sb.B[120 + i] = c }
    let seed = randomBytes(16)
    for i in 0..<16 { sb.B[236 + i] = seed[i] }
    sb.B[252] = 1               // half-MD4 directory hashes
    sb.U32(264, now)
    sb.U16(348, uint16(extraIsize))
    sb.U16(350, uint16(extraIsize))
    sb.U32(352, 0x2)            // signed directory hashes, as x86 and arm64 Linux write them
    for (g, l) in layout.enumerated() where l.Backup {
        sb.U16(90, uint16(g))
        let base = int64(l.Start) * int64(bs)
        try f.Write(sb.B, at: g == 0 ? 1024 : base)
        try f.Write(desc.B, at: (g == 0 ? int64(firstData + 1) * int64(bs) : base + int64(bs)))
    }
}

struct GroupLayout {
    let Start: int
    let Count: int
    let Backup: bool
    let BlockBitmap: int
    let InodeBitmap: int
    let InodeTable: int
    /// The first block after the group's metadata.
    let FirstFree: int
}

/// Whether group g keeps a superblock copy: 0, 1 and powers of 3, 5 and 7 (sparse_super).
func hasSuperblock(_ g: int) -> bool {
    if g <= 1 { return true }
    for p in [3, 5, 7] {
        var n = p
        while n < g { n *= p }
        if n == g { return true }
    }
    return false
}

/// How many blocks mke2fs gives a journal on a file system of `blocks`.
func defaultJournalBlocks(_ blocks: int) -> int {
    if blocks < 2048 { return 0 }
    if blocks < 32768 { return 1024 }
    if blocks < 256 * 1024 { return 4096 }
    if blocks < 512 * 1024 { return 8192 }
    if blocks < 4096 * 1024 { return 16384 }
    return 32768
}

/// An inode whose `count` blocks from `block` are mapped by one extent.
func inode(mode: uint16, links: uint16, block: int, count: int, bs: int, now: uint32) -> Bytes {
    var b = Bytes(inodeSize)
    b.U16(0, mode)
    b.U32(4, uint32(count * bs))
    b.U32(8, now)
    b.U32(12, now)
    b.U32(16, now)
    b.U16(26, links)
    b.U32(28, uint32(count * bs / 512))
    b.U32(32, 0x80000)          // extents
    b.U16(40, 0xF30A)           // extent header: magic, 1 entry, room for 4, depth 0
    b.U16(42, 1)
    b.U16(44, 4)
    b.U16(46, 0)
    b.U32(52, 0)                // the extent: file block 0, `count` blocks, at `block`
    b.U16(56, uint16(count))
    b.U16(58, 0)
    b.U32(60, uint32(block))
    b.U16(128, uint16(extraIsize))
    b.U32(144, now)             // creation time
    return b
}

func randomBytes(_ n: int) -> [uint8] {
    if let b = try? rand.Bytes(n) { return b }
    var out = [uint8](repeating: 0, count: n)
    let t = fs.Timestamp.Now()
    for i in 0..<n { out[i] = uint8(truncatingIfNeeded: (t.UnixSeconds >> int64(i % 8 * 8)) ^ int64(t.Nanoseconds) >> int64(i % 4 * 8)) }
    return out
}

/// Little-endian fields in a zeroed buffer.
struct Bytes {
    var B: [uint8]

    init(_ n: int) {
        B = [uint8](repeating: 0, count: n)
    }

    mutating func U16(_ at: int, _ v: uint16) {
        B[at] = uint8(v & 0xFF)
        B[at + 1] = uint8(v >> 8)
    }

    mutating func U32(_ at: int, _ v: uint32) {
        for i in 0..<4 { B[at + i] = uint8((v >> uint32(8 * i)) & 0xFF) }
    }

    mutating func BE32(_ at: int, _ v: uint32) {
        for i in 0..<4 { B[at + i] = uint8((v >> uint32(24 - 8 * i)) & 0xFF) }
    }

    func LE32(_ at: int) -> uint32 {
        return uint32(B[at]) | uint32(B[at + 1]) << 8 | uint32(B[at + 2]) << 16 | uint32(B[at + 3]) << 24
    }

    mutating func SetBit(_ i: int) {
        B[i / 8] |= uint8(1) << uint8(i % 8)
    }

    /// A directory entry at `at`; returns where the next one goes.
    mutating func Entry(_ at: int, inode: int, name: string, recLen: int) -> int {
        U32(at, uint32(inode))
        U16(at + 4, uint16(recLen))
        B[at + 6] = uint8(name.utf8.count)
        B[at + 7] = 2           // a directory
        for (i, c) in name.utf8.enumerated() { B[at + 8 + i] = c }
        return at + recLen
    }
}
