// SPDX-License-Identifier: Apache-2.0
import CryptoKit
import Darwin
import Foundation

/// Descriptor checks apply to the object actually opened, including after a
/// path replacement. Nonblocking opens let us reject FIFOs/devices immediately.
enum LocalFileAccess {
  static func openRegularFile(_ url: URL, followSymlinks: Bool = true) throws -> FileHandle {
    guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
    let flags = O_RDONLY | O_CLOEXEC | O_NONBLOCK | (followSymlinks ? 0 : O_NOFOLLOW)
    let descriptor = open(url.path, flags)
    guard descriptor >= 0 else { throw posixError() }
    var attributes = stat()
    guard fstat(descriptor, &attributes) == 0 else {
      let error = posixError()
      close(descriptor)
      throw error
    }
    guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      close(descriptor)
      throw CocoaError(.fileReadUnsupportedScheme)
    }
    return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  }

  static func readData(
    at url: URL, maximumBytes: Int, followSymlinks: Bool = true
  ) throws -> Data {
    let handle = try openRegularFile(url, followSymlinks: followSymlinks)
    defer { try? handle.close() }
    var attributes = stat()
    guard fstat(handle.fileDescriptor, &attributes) == 0 else { throw posixError() }
    guard maximumBytes >= 0, attributes.st_size >= 0,
      attributes.st_size <= Int64(maximumBytes)
    else { throw CocoaError(.fileReadTooLarge) }

    var data = Data()
    while true {
      try Task.checkCancellation()
      // Read at most one byte beyond the budget to detect growth after fstat.
      let remaining = maximumBytes - data.count
      let count = remaining >= 64 * 1_024 ? 64 * 1_024 : remaining + 1
      guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { return data }
      guard chunk.count <= maximumBytes - data.count else { throw CocoaError(.fileReadTooLarge) }
      data.append(chunk)
    }
  }

  /// Application-owned directories contain private transcripts and listening
  /// state. Do not follow a replacement link or change source-library modes.
  static func ensurePrivateDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw posixError() }
    defer { close(descriptor) }
    var attributes = stat()
    guard fstat(descriptor, &attributes) == 0 else { throw posixError() }
    guard attributes.st_uid == geteuid() else { throw CocoaError(.fileWriteNoPermission) }
    guard fchmod(descriptor, 0o700) == 0 else { throw posixError() }
  }

  static func isRegularFile(_ url: URL) -> Bool {
    var attributes = stat()
    return url.isFileURL && lstat(url.path, &attributes) == 0
      && attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
  }

  /// Replaces the destination directory entry without following a final link.
  /// Both paths are expected to be on the same volume and the staged entry is
  /// removed by `rename` as part of the replacement.
  static func replaceAtomically(staged: URL, destination: URL) throws {
    guard staged.isFileURL, destination.isFileURL, isRegularFile(staged) else {
      throw CocoaError(.fileWriteUnsupportedScheme)
    }
    guard rename(staged.path, destination.path) == 0 else { throw posixError() }
    guard isRegularFile(destination) else { throw CocoaError(.fileWriteUnsupportedScheme) }
  }

  static func canonicalDirectoryURL(_ url: URL) throws -> URL {
    guard let path = realpath(url.path, nil) else { throw posixError() }
    defer { free(path) }
    return URL(fileURLWithPath: String(cString: path), isDirectory: true)
  }

  static func posixError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
}

func sha256File(_ url: URL) -> String? {
  try? sha256FileCheckingCancellation(url)
}

/// Synchronous hashing for actors that must remain non-reentrant while still
/// reacting to cancellation between bounded read chunks.
func sha256FileCheckingCancellation(_ url: URL, followSymlinks: Bool = true) throws -> String {
  try Task.checkCancellation()
  let input = try LocalFileAccess.openRegularFile(url, followSymlinks: followSymlinks)
  defer { try? input.close() }
  var hasher = SHA256()
  while true {
    try Task.checkCancellation()
    guard let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
    hasher.update(data: data)
  }
  try Task.checkCancellation()
  return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

/// Hashes a potentially large lesson file without blocking MainActor and with
/// cooperative cancellation between read chunks. The detached utility task is
/// deliberately owned and awaited by its caller; it is not fire-and-forget.
func sha256FileCancellable(_ url: URL) async throws -> String {
  let work = Task.detached(priority: .utility) {
    try sha256FileCheckingCancellation(url)
  }
  return try await withTaskCancellationHandler {
    try await work.value
  } onCancel: {
    work.cancel()
  }
}

/// Copy an audio file into stable staging while hashing it. On the normal
/// APFS home volume, FileManager creates a copy-on-write clone rather than
/// rewriting the whole lesson into the cache; the snapshot is then hashed in
/// cancellable chunks. Other file systems transparently fall back to a normal
/// copy through the same Foundation API.
func copyAndSHA256File(from source: URL, to destination: URL) async throws -> String {
  let work = Task.detached(priority: .utility) {
    try Task.checkCancellation()
    try FileManager.default.copyItem(at: source, to: destination)
    return try sha256FileCheckingCancellation(destination, followSymlinks: false)
  }

  return try await withTaskCancellationHandler {
    try await work.value
  } onCancel: {
    work.cancel()
  }
}

struct FileSignature: Equatable, Sendable {
  let size: Int64
  let mtimeNS: Int64
  let ctimeNS: Int64
}

func fileSignature(_ url: URL) -> FileSignature? {
  var st = stat()
  guard lstat(url.path, &st) == 0 else { return nil }
  #if os(macOS)
    let mt = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
    let ct = Int64(st.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(st.st_ctimespec.tv_nsec)
  #else
    let mt: Int64 = 0
    let ct: Int64 = 0
  #endif
  return .init(size: Int64(st.st_size), mtimeNS: mt, ctimeNS: ct)
}

/// A shared lease covers active imports; startup cleanup takes a nonblocking
/// exclusive lease. The filesystem lock also protects multiple app instances.
final class LibraryImportLease {
  private let descriptor: Int32

  private init(descriptor: Int32) { self.descriptor = descriptor }

  deinit {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }

  static func acquire(at library: URL, forCleanup: Bool = false) throws -> LibraryImportLease? {
    let url = library.appendingPathComponent(".cuelixa-import.lock")
    let descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
    guard descriptor >= 0 else { throw LocalFileAccess.posixError() }
    var attributes = stat()
    guard fstat(descriptor, &attributes) == 0,
      attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
      attributes.st_uid == geteuid(), attributes.st_nlink == 1
    else {
      close(descriptor)
      throw CocoaError(.fileWriteNoPermission)
    }
    if flock(descriptor, forCleanup ? LOCK_EX | LOCK_NB : LOCK_SH) != 0 {
      let error = LocalFileAccess.posixError()
      close(descriptor)
      if forCleanup, error.code == .EWOULDBLOCK { return nil }
      throw error
    }
    return LibraryImportLease(descriptor: descriptor)
  }
}
