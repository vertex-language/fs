package main

import "fs"

func main() -> int32 {
    let file = fs.Path("package.vs")
    do {
        let text = try fs.ReadText(file)
        print(text)
    } catch let err as fs.FsError {
        print("fs-cat: \(err.Message)")
        return 1
    } catch {
        return 1
    }
    return 0
}
