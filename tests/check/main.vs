// fs comprehensive test suite.
package main

import "fs"
import "fs/memory"

var failures: int32 = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func testPaths() {
    let p1 = fs.Path("a/b/c.txt")
    check(p1.Name() == "c.txt", "path Name")
    check(p1.Parent()?.Value == "a/b", "path Parent")
    check(p1.Stem() == "c", "path Stem")
    check(p1.Extension() == "txt", "path Extension")
    check(p1.WithExtension("md").Value == "a/b/c.md", "path WithExtension")

    let p2 = fs.Path("/usr/local/bin")
    check(p2.IsAbsolute(), "path IsAbsolute")
    check(!p1.IsAbsolute(), "path relative IsAbsolute is false")

    let p3 = fs.Path("a/./b/../c")
    check(p3.Lexically().Value == "a/c", "path Lexically normalization")

    let p4 = fs.Path("/a/b/c/d")
    let base = fs.Path("/a/b")
    check(p4.Relative(to: base)?.Value == "c/d", "path Relative(to:)")

    let joined = fs.Path("src") / "main.vs"
    check(joined.Value == "src/main.vs", "path / operator")
    check(joined.StartsWith(fs.Path("src")), "path StartsWith")
}

func testFileOps(tmp: fs.Path) {
    let filePath = tmp / "test.txt"

    do {
        try fs.WriteText(filePath, "hello vertex fs")
        let readBack = try fs.ReadText(filePath)
        check(readBack == "hello vertex fs", "WriteText and ReadText round trip")

        // Atomic write
        try fs.WriteText(filePath, "hello atomic", atomic: true)
        let atomicRead = try fs.ReadText(filePath)
        check(atomicRead == "hello atomic", "WriteText atomic replace")

        // Append
        var appendData: [uint8] = []
        for b in " + appended".utf8 { appendData.append(b) }
        try fs.AppendFile(filePath, appendData)
        let appendedRead = try fs.ReadText(filePath)
        check(appendedRead == "hello atomic + appended", "AppendFile")

        // Metadata
        let meta = try fs.Metadata(filePath)
        check(meta.IsFile(), "Metadata IsFile")
        check(meta.Size > 0, "Metadata Size > 0")

        // File handle and streaming
        let file = try fs.Open(filePath, .read)
        var buf = [uint8](repeating: 0, count: 5)
        let n = try file.Read(into: &buf)
        check(n == 5, "File.Read read 5 bytes")

        let pos = try file.Seek(.start(0))
        check(pos == 0, "File.Seek to start")

        let all = try file.ReadToEnd()
        check(all.count == int(meta.Size), "File.ReadToEnd")
        try file.Close()
    } catch let err as fs.FsError {
        check(false, "FileOps error: \(err.Message)")
    } catch {
        check(false, "FileOps unknown error")
    }
}

func testDirOps(tmp: fs.Path) {
    let subDir = tmp / "sub" / "nested"
    do {
        try fs.CreateDir(subDir, all: true)
        check(true, "CreateDir recursive")

        let f1 = subDir / "file1.txt"
        let f2 = subDir / "file2.txt"
        try fs.WriteText(f1, "one")
        try fs.WriteText(f2, "two")

        let entries = try fs.ReadDir(subDir)
        check(entries.count == 2, "ReadDir count is 2")
        if entries.count == 2 {
            check(entries[0].Name == "file1.txt", "ReadDir sorted entry 0")
            check(entries[1].Name == "file2.txt", "ReadDir sorted entry 1")
        }

        // Walk
        var walkedCount = 0
        try fs.Walk(tmp) { entry in
            walkedCount += 1
            return .continue
        }
        check(walkedCount >= 3, "Walk traversed entries")

        // Dir capability handle
        let dir = try fs.OpenDir(subDir, confined: true)
        let relRead = try dir.ReadFile(fs.Path("file1.txt"))
        check(!relRead.isEmpty, "Dir.ReadFile relative read")

        // Test confinement rejection
        var escaped = false
        do {
            _ = try dir.ReadFile(fs.Path("../file1.txt"))
            escaped = true
        } catch {
            escaped = false
        }
        check(!escaped, "Confined Dir rejects '..' escape")
        dir.Close()

        // Copy
        let copyDest = tmp / "sub_copy"
        try fs.Copy(subDir, copyDest, fs.CopyOptions(overwrite: true, recursive: true))
        let copiedText = try fs.ReadText(copyDest / "file1.txt")
        check(copiedText == "one", "Recursive Copy verified")

        // Rename
        let moved = tmp / "sub_moved"
        try fs.Rename(copyDest, moved, replace: true)
        check(try fs.ReadText(moved / "file2.txt") == "two", "Rename directory")

        // Remove
        try fs.Remove(moved / "file1.txt")
        try fs.RemoveAll(moved)
        check(true, "Remove and RemoveAll")
    } catch let err as fs.FsError {
        check(false, "DirOps error: \(err.Message)")
    } catch {
        check(false, "DirOps unknown error")
    }
}

func testErrorHandling(tmp: fs.Path) {
    var caughtNotFound = false
    do {
        _ = try fs.ReadFile(tmp / "nonexistent_file_12345.txt")
    } catch let err as fs.FsError {
        switch err {
        case .notFound:
            caughtNotFound = true
        default:
            break
        }
    } catch {
        caughtNotFound = false
    }
    check(caughtNotFound, "ReadFile nonexistent throws FsError.notFound")
}

func bytesToText(_ bytes: [uint8]) -> string {
    var chars: [CChar] = []
    for b in bytes { chars.append(CChar(truncatingIfNeeded: b)) }
    chars.append(0)
    return string(cString: chars)
}

func testMemoryFileSystem() {
    let mem = memory.MemoryFileSystem()
    mem.AddText(fs.Path("/hello.txt"), text: "memory fs content")

    do {
        let content = try mem.ReadFile(fs.Path("/hello.txt"))
        let text = bytesToText(content)
        check(text == "memory fs content", "MemoryFileSystem ReadFile")

        let entries = try mem.ReadDir(fs.Path("/"))
        check(entries.count == 1, "MemoryFileSystem ReadDir count")
        if !entries.isEmpty {
            check(entries[0].Name == "hello.txt", "MemoryFileSystem ReadDir entry name")
        }
    } catch let err as fs.FsError {
        check(false, "MemoryFileSystem error: \(err.Message)")
    } catch {
        check(false, "MemoryFileSystem unknown error")
    }
}

func main() -> int32 {
    print("Running fs package check suite...")

    testPaths()

    do {
        let tmp = try fs.TempDir("vertex_test_")
        defer {
            try? fs.RemoveAll(tmp)
        }

        testFileOps(tmp: tmp)
        testDirOps(tmp: tmp)
        testErrorHandling(tmp: tmp)
    } catch let err as fs.FsError {
        print("TempDir setup error: \(err.Message)")
        return 1
    } catch {
        print("Unknown error during temp dir setup")
        return 1
    }

    testMemoryFileSystem()

    if failures == 0 {
        print("all fs checks passed")
        return 0
    } else {
        print("\(failures) fs checks failed")
        return failures
    }
}
