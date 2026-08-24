// SPDX-License-Identifier: Apache-2.0
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

    print("HARDENING_IMPORT_SCANNER_BATCH_ROLLBACK=PASS")
  }
}
