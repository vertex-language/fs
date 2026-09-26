// fs/mmap: a file's bytes mapped, read in place, the same as reading it.
package main

import (
    "fs"
    "fs/mmap"
)

var failures = 0

func check(_ ok: bool, _ what: string) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { failures += 1 }
}

let dir = fs.Path("/tmp/vertex_fs_mmap_test")
try? fs.RemoveAll(dir)
try fs.CreateDir(dir)
var data: [uint8] = []
for i in 0..<10000 { data.append(uint8(truncatingIfNeeded: i * 7 + 3)) }
let path = dir.Join(fs.Path("data.bin"))
try fs.WriteFile(path, data)

let m = try mmap.Map(path)
check(m.Count == 10000, "Count is the file's size")
let p = m.Bytes!
var same = true
for i in 0..<10000 { if p[i] != data[i] { same = false } }
check(same, "every mapped byte is the file's")
check(m.Copy(from: 9990, count: 10) == Array(data[9990..<10000]), "Copy of the last ten bytes")

let empty = dir.Join(fs.Path("empty.bin"))
try fs.WriteFile(empty, [])
let e = try mmap.Map(empty)
check(e.Count == 0 && e.Bytes == nil, "an empty file maps to no bytes")

do {
    _ = try mmap.Map(dir.Join(fs.Path("missing.bin")))
    check(false, "a missing file throws")
} catch {
    check(true, "a missing file throws")
}

try? fs.RemoveAll(dir)
print(failures == 0 ? "all passed" : "\(failures) failed")
