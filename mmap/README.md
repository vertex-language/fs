# fs/mmap

Maps a file into memory, read-only: its bytes are read in place, without copying, and pages come in from disk as they are touched.

```vertex
import "fs/mmap"
```

## Types

- **`MapError`** (enum): MapError is a mapping the operating system refused.
- **`Mapping`** (class): Mapping is a file's bytes in memory, valid until the last reference to it goes: then the pages are unmapped.

## Functions

- `func Anonymous(_ count: int) throws -> Mapping`: Anonymous maps count bytes of writable, zero-initialized anonymous memory.
- `func Map(_ path: fs.Path) throws -> Mapping`: Map maps the whole file at path, read-only.

Part of the [`fs`](https://github.com/vertex-language/fs) repository.
