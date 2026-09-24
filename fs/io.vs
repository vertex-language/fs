package fs

import "io"

// A File is a stream as io means one: io.Copy, io.BufferedReader,
// io.ReadToEnd and the rest take it.
extension File: io.Reader, io.Writer, io.Seeker, io.Closer {}
