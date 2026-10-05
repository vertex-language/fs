package main

import "fs"

func main() -> int32 {
    let src = fs.Path("vs.mod")
    let dst = fs.Path("vs.mod.copy")
    do {
        try fs.Copy(src, dst)
        let size = try fs.Metadata(dst).Size
        print("Successfully cloned \(src.Value) -> \(dst.Value) (\(size) bytes)")
        try fs.Remove(dst)
        print("Cleaned up temporary copy \(dst.Value)")
    } catch let err as fs.FsError {
        print("fs-copy: \(err.Message)")
        return 1
    } catch {
        return 1
    }
    return 0
}
