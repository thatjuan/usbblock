import Darwin
import Foundation

/// Replaces this process with `sudo <self> <args>` unless already root.
func requireRoot() throws {
    guard getuid() != 0 else { return }
    try replaceProcess("/usr/bin/sudo", arguments: [executablePath()] + CommandLine.arguments.dropFirst())
}

/// Resolves the running binary so sudo and daemon installs use the same file.
func executablePath() -> String {
    Bundle.main.executableURL!.resolvingSymlinksInPath().path
}

/// Supplies a null-terminated argv; successful exec never returns.
func replaceProcess(_ path: String, arguments: [String]) throws {
    let pointers = ([path] + arguments).map { strdup($0) }
    defer { pointers.forEach { free($0) } }
    var argv: [UnsafeMutablePointer<CChar>?] = pointers + [nil]
    let result = argv.withUnsafeMutableBufferPointer { execv(path, $0.baseAddress!) }
    if result == -1 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}

/// Writes beside the destination, sets ownership and permissions, then renames atomically.
func writeAtomic(_ data: Data, to path: String, mode: mode_t) throws {
    var template = Array((path + ".XXXXXX").utf8CString)
    let fd = mkstemp(&template)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let temporary = String(decoding: template.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
    defer {
        close(fd)
        unlink(temporary)
    }
    guard fchmod(fd, mode) == 0, fchown(fd, 0, 0) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: data)
    guard rename(temporary, path) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
