// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation

private enum SmokeFailure: Error { case failed(String) }

private actor SmokeHashCounter {
  private var count = 0

  func hash(_ url: URL) throws -> String {
    count += 1
    guard let hash = sha256File(url) else { throw SmokeFailure.failed("hash failed") }
    return hash
  }

  func value() -> Int { count }
  func reset() { count = 0 }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  guard condition() else { throw SmokeFailure.failed(message) }
}

@main
private struct HardeningSmoke {
  static func main() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(
      "CuelixaHardeningSmoke-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let legacy = root.appendingPathComponent("podcast")
    try Data("not a directory".utf8).write(to: legacy)
    let resolved = AppDirectories.resolve(home: root)
    try require(resolved.library != legacy, "legacy regular file was selected")
    try require(resolved.legacyLibraryIssue == .notDirectory, "legacy issue was not reported")

    let boundaryDirectories = AppDirectories.isolated(
      root: root.appendingPathComponent("symlink-boundary", isDirectory: true))
    try boundaryDirectories.ensure()
    let boundaryLibrary = boundaryDirectories.library
    let regular = boundaryLibrary.appendingPathComponent("regular.mp3")
    try Data("regular audio".utf8).write(to: regular)
    let nested = boundaryLibrary.appendingPathComponent("nested", isDirectory: true)
    try fm.createDirectory(at: nested, withIntermediateDirectories: true)
    let internalTarget = nested.appendingPathComponent("internal.wav")
    try Data("internal audio".utf8).write(to: internalTarget)
    try fm.createSymbolicLink(
      at: boundaryLibrary.appendingPathComponent("internal-link.wav"),
      withDestinationURL: internalTarget)
    try fm.createSymbolicLink(
      at: boundaryLibrary.appendingPathComponent("duplicate.mp3"),
      withDestinationURL: regular)

    let externalTarget = root.appendingPathComponent("external-target.mp3")
    try Data("external audio".utf8).write(to: externalTarget)
    try fm.createSymbolicLink(
      at: boundaryLibrary.appendingPathComponent("external-link.mp3"),
      withDestinationURL: externalTarget)
    try fm.createSymbolicLink(
      at: boundaryLibrary.appendingPathComponent("dangling.aac"),
      withDestinationURL: root.appendingPathComponent("missing.aac"))
    let fifo = root.appendingPathComponent("special.fifo")
    try require(mkfifo(fifo.path, 0o600) == 0, "FIFO fixture could not be created")
    try fm.createSymbolicLink(
      at: boundaryLibrary.appendingPathComponent("special.mp3"), withDestinationURL: fifo)

    let boundaryDatabase = LibraryDatabase(url: boundaryDirectories.database)
    let boundaryScanner = LibraryScanner(
      db: boundaryDatabase, directories: boundaryDirectories,
      metadataLoader: { _ in (duration: 1, title: nil) })
    await boundaryScanner.reconcileNow()
    let firstBoundaryRecords = boundaryDatabase.fileRecords() ?? [:]
    try require(
      Set(firstBoundaryRecords.keys) == Set([regular.path, internalTarget.path]),
      "scanner accepted an external/dangling/special link or failed canonical deduplication")
    let boundaryMetrics = await boundaryScanner.metrics()
    try require(
      boundaryMetrics.enumeratedFiles == 2, "scanner canonical target count was incorrect")

    let externalImportLink = root.appendingPathComponent("imported-alias.mp3")
    try fm.createSymbolicLink(at: externalImportLink, withDestinationURL: externalTarget)
    let externalImport = await ImportCoordinator(directories: boundaryDirectories).importFiles([
      externalImportLink
    ])
    try require(externalImport.count(.imported) == 1, "import through external symlink failed")
    await boundaryScanner.reconcileNow()
    let importedRecords = boundaryDatabase.fileRecords() ?? [:]
    try require(importedRecords.count == 3, "verified symlink import was not discovered")
    try require(
      importedRecords.keys.allSatisfy { $0.hasPrefix(boundaryLibrary.path + "/") },
      "scanner persisted a path outside the canonical library root")

    let directories = AppDirectories.isolated(root: root.appendingPathComponent("isolated"))
    try directories.ensure()
    let source = root.appendingPathComponent("lesson.mp3")
    try Data("safe import".utf8).write(to: source)
    let coordinator = ImportCoordinator(directories: directories)
    let firstImport = await coordinator.importFiles([source])
    let duplicateImport = await coordinator.importFiles([source])
    try require(firstImport.count(.imported) == 1, "verified import failed")
    try require(duplicateImport.count(.duplicate) == 1, "duplicate was not detected")

    for index in 0..<1_000 {
      try Data("audio-\(index)".utf8).write(
        to: directories.library.appendingPathComponent("\(index).mp3"))
    }
    let counter = SmokeHashCounter()
    let database = LibraryDatabase(url: directories.database)
    let scanner = LibraryScanner(
      db: database, directories: directories,
      hashFile: { url in try await counter.hash(url) },
      metadataLoader: { _ in (duration: 1, title: nil) })
    await scanner.reconcileNow()
    let initialHashCount = await counter.value()
    try require(initialHashCount == 1_001, "initial scan hash count was incorrect")

    await counter.reset()
    await scanner.reconcileNow()
    let unchangedMetrics = await scanner.metrics()
    let unchangedHashCount = await counter.value()
    try require(unchangedHashCount == 0, "unchanged scan rehashed files")
    try require(unchangedMetrics.databaseTransactions == 1, "scan used multiple transactions")

    try Data("changed payload".utf8).write(
      to: directories.library.appendingPathComponent("500.mp3"))
    await counter.reset()
    await scanner.reconcileNow()
    let changedHashCount = await counter.value()
    try require(changedHashCount == 1, "single change did not produce one hash")

    let rollbackDatabase = LibraryDatabase(
      url: root.appendingPathComponent("rollback/library.sqlite3"))
    let original = ScannedFileRecord(
      path: "/original.mp3", hash: "original",
      signature: .init(size: 1, mtimeNS: 1, ctimeNS: 1), title: "Original", duration: 1)
    let replacement = ScannedFileRecord(
      path: "/replacement.mp3", hash: "replacement",
      signature: .init(size: 2, mtimeNS: 2, ctimeNS: 2), title: "Replacement", duration: 2)
    try require(
      rollbackDatabase.applyScan([original], seenAt: 1, complete: true),
      "rollback fixture setup failed")
    try require(
      !rollbackDatabase.applyScan(
        [replacement], seenAt: 2, complete: true, failAfterRecordForTesting: 1),
      "injected transaction failure committed")
    try require(
      rollbackDatabase.fileRecords()?.keys.sorted() == [original.path],
      "failed transaction did not roll back")

    print("HARDENING_IMPORT_SCANNER_BOUNDARY_BATCH_ROLLBACK=PASS")
  }
}
