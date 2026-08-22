// SPDX-License-Identifier: Apache-2.0
import Foundation

@main
struct DatabaseSmoke {
  static func main() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("cuelixa-db-smoke-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let db = LibraryDatabase(url: root.appendingPathComponent("library.sqlite3"))
    precondition(db.initializationError == nil)

    let p1 = root.appendingPathComponent("one.mp3").path
    let p2 = root.appendingPathComponent("two.mp3").path
    let s1 = FileSignature(size: 100, mtimeNS: 10, ctimeNS: 11)
    let s2 = FileSignature(size: 200, mtimeNS: 20, ctimeNS: 21)

    precondition(
      db.upsertFile(path: p1, hash: "h1", signature: s1, title: "Alpha", duration: 60, seenAt: 1))
    precondition(
      db.upsertFile(path: p2, hash: "h2", signature: s2, title: "Beta", duration: 90, seenAt: 1))
    precondition(db.fileSignature(path: p1)?.0 == "h1")
    precondition(db.counts().all == 2)
    precondition(db.counts().upNext == 2)

    precondition(db.setPosition(hash: "h1", position: 25))
    precondition(db.counts().continue == 1)
    precondition(db.tracks(section: .continue, query: "").map(\.contentHash) == ["h1"])
    precondition(db.tracks(section: .all, query: "alp").map(\.contentHash) == ["h1"])

    precondition(db.markCompleted(hash: "h1", completed: true))
    precondition(db.counts().completed == 1)
    precondition(db.track(hash: "h1")?.completed == true)
    precondition(db.track(hash: "h1")?.position == 0)

    precondition(db.markCompleted(hash: "h1", completed: false))
    precondition(db.resetPosition(hash: "h1"))
    precondition(db.track(hash: "h1")?.completed == false)

    precondition(db.reconcile(seenPaths: [p1]))
    precondition(db.counts().all == 1)
    precondition(db.track(hash: "h2")?.missing == true)

    print("DATABASE_STATE_AND_RECONCILIATION=PASS")
  }
}
