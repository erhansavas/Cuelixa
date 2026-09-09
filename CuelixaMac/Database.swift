// SPDX-License-Identifier: Apache-2.0
import Foundation
import OSLog
import SQLite3

struct StoredFileRecord: Sendable {
  let hash: String
  let signature: FileSignature
  let title: String
  let duration: Double
}

struct ScannedFileRecord: Sendable {
  let path: String
  let hash: String
  let signature: FileSignature
  let title: String
  let duration: Double
}

private func sqliteTransientDestructor() -> sqlite3_destructor_type {
  unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

// SAFETY: SQLite connection state never escapes this type. Every public database
// operation is serialized through `queue`; the connection is opened with FULLMUTEX
// as a second line of defense. `@unchecked Sendable` documents that synchronization.
final class LibraryDatabase: @unchecked Sendable {
  private let logger = Logger(subsystem: "io.github.erhansavas.Cuelixa", category: "Database")
  private let url: URL
  private let queue = DispatchQueue(label: "io.github.erhansavas.Cuelixa.database")
  private var connection: OpaquePointer?
  private(set) var initializationError: String?

  init(url: URL = AppPaths.current.database) {
    let directory = url.deletingLastPathComponent()
    let canonicalDirectory: URL
    do {
      try LocalFileAccess.ensurePrivateDirectory(directory)
      canonicalDirectory = try LocalFileAccess.canonicalDirectoryURL(directory)
    } catch {
      self.url = url
      initializationError = error.localizedDescription
      return
    }
    // SQLite's NOFOLLOW checks ancestors too. Canonicalize the validated
    // directory using POSIX realpath: Foundation shortens /private/var back to
    // the /var symlink. Retain the filename so database links remain rejected.
    self.url = canonicalDirectory.appendingPathComponent(url.lastPathComponent)
    let initialized = queue.sync {
      guard let db = openConnection() else { return false }
      if !createSchema(db) {
        let message = sqliteMessage(db)
        initializationError = message
        logger.error("Library database schema initialization failed: \(message, privacy: .private)")
        return false
      }
      return true
    }
    if !initialized, initializationError == nil {
      initializationError = "The library database could not be opened."
    }
  }

  private func openConnection() -> OpaquePointer? {
    if let connection { return connection }
    var raw: OpaquePointer?
    guard
      sqlite3_open_v2(
        url.path, &raw,
        SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW,
        nil)
        == SQLITE_OK, let db = raw
    else {
      if let raw { sqlite3_close(raw) }
      return nil
    }
    guard sqlite3_busy_timeout(db, 30_000) == SQLITE_OK,
      sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil) == SQLITE_OK,
      sqlite3_exec(db, "PRAGMA synchronous = NORMAL", nil, nil, nil) == SQLITE_OK,
      sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil) == SQLITE_OK
    else {
      initializationError = "SQLite runtime configuration failed: \(sqliteMessage(db))"
      sqlite3_close(db)
      return nil
    }
    connection = db
    return db
  }

  private func withDB<T>(_ body: (OpaquePointer) -> T) -> T? {
    guard let db = connection ?? openConnection() else { return nil }
    return body(db)
  }

  deinit {
    if let connection { sqlite3_close_v2(connection) }
  }

  private func sqliteMessage(_ db: OpaquePointer) -> String {
    String(cString: sqlite3_errmsg(db))
  }

  @discardableResult
  private func execute(_ sql: String, on db: OpaquePointer) -> Bool {
    sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
  }

  private func filesHasColumn(_ name: String, db: OpaquePointer) -> Bool {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "PRAGMA table_info(files)", -1, &statement, nil) == SQLITE_OK
    else { return false }
    defer { sqlite3_finalize(statement) }
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let rawName = sqlite3_column_text(statement, 1) else { continue }
      if String(cString: rawName) == name { return true }
    }
    return false
  }

  /// Upgrade the 0.1.0-dev database in place before any scanner statement can
  /// reference ctime_ns. The migration is transactional so a failed upgrade
  /// never leaves a partially changed schema behind.
  private func createSchema(_ db: OpaquePointer) -> Bool {
    guard execute("BEGIN IMMEDIATE", on: db) else { return false }
    var committed = false
    defer {
      if !committed { _ = execute("ROLLBACK", on: db) }
    }

    guard
      execute(
        """
        CREATE TABLE IF NOT EXISTS tracks (
          content_hash TEXT PRIMARY KEY, title TEXT NOT NULL, duration REAL NOT NULL DEFAULT 0,
          position REAL NOT NULL DEFAULT 0, completed INTEGER NOT NULL DEFAULT 0 CHECK(completed IN (0,1)),
          completed_at REAL, last_played_at REAL, added_at REAL NOT NULL, last_seen_at REAL NOT NULL,
          missing INTEGER NOT NULL DEFAULT 0 CHECK(missing IN (0,1))
        );
        """, on: db),
      execute(
        """
        CREATE TABLE IF NOT EXISTS files (
          path TEXT PRIMARY KEY, content_hash TEXT NOT NULL REFERENCES tracks(content_hash) ON DELETE CASCADE,
          size INTEGER NOT NULL, mtime_ns INTEGER NOT NULL, ctime_ns INTEGER NOT NULL, last_seen_at REAL NOT NULL
        );
        """, on: db)
    else { return false }

    if !filesHasColumn("ctime_ns", db: db),
      !execute("ALTER TABLE files ADD COLUMN ctime_ns INTEGER NOT NULL DEFAULT 0", on: db)
    {
      return false
    }

    guard execute("CREATE INDEX IF NOT EXISTS idx_files_hash ON files(content_hash)", on: db),
      execute(
        "CREATE INDEX IF NOT EXISTS idx_tracks_completed ON tracks(completed,missing)", on: db),
      execute("PRAGMA user_version = 1", on: db),
      execute("COMMIT", on: db)
    else { return false }
    committed = true
    return true
  }

  func fileSignature(path: String) -> (String, FileSignature)? {
    queue.sync {
      withDB { db in
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard
          sqlite3_prepare_v2(
            db, "SELECT content_hash,size,mtime_ns,ctime_ns FROM files WHERE path = ?", -1, &stmt,
            nil) == SQLITE_OK
        else { return nil }
        sqlite3_bind_text(stmt, 1, path, -1, sqliteTransientDestructor())
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let hash = String(cString: sqlite3_column_text(stmt, 0))
        return (
          hash,
          .init(
            size: sqlite3_column_int64(stmt, 1), mtimeNS: sqlite3_column_int64(stmt, 2),
            ctimeNS: sqlite3_column_int64(stmt, 3))
        )
      } ?? nil
    }
  }

  func fileRecords() -> [String: StoredFileRecord]? {
    queue.sync {
      withDB { db -> [String: StoredFileRecord]? in
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard
          sqlite3_prepare_v2(
            db,
            """
            SELECT f.path,f.content_hash,f.size,f.mtime_ns,f.ctime_ns,t.title,t.duration
            FROM files f JOIN tracks t ON t.content_hash = f.content_hash
            """, -1, &statement, nil) == SQLITE_OK
        else { return nil }
        var records: [String: StoredFileRecord] = [:]
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
          let path = String(cString: sqlite3_column_text(statement, 0))
          let hash = String(cString: sqlite3_column_text(statement, 1))
          let title = String(cString: sqlite3_column_text(statement, 5))
          records[path] = StoredFileRecord(
            hash: hash,
            signature: .init(
              size: sqlite3_column_int64(statement, 2),
              mtimeNS: sqlite3_column_int64(statement, 3),
              ctimeNS: sqlite3_column_int64(statement, 4)),
            title: title, duration: sqlite3_column_double(statement, 6))
          step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { return nil }
        return records
      } ?? nil
    }
  }

  /// Applies one complete scanner pass with one SQLite transaction. A partial
  /// pass may publish verified discoveries but never marks unseen paths missing.
  @discardableResult
  func applyScan(
    _ records: [ScannedFileRecord], seenAt: Double, complete: Bool,
    failAfterRecordForTesting: Int? = nil
  ) -> Bool {
    queue.sync {
      withDB { db in
        guard execute("BEGIN IMMEDIATE", on: db) else { return false }
        var committed = false
        defer { if !committed { _ = execute("ROLLBACK", on: db) } }

        var trackStatement: OpaquePointer?
        var fileStatement: OpaquePointer?
        var selectStatement: OpaquePointer?
        var deleteStatement: OpaquePointer?
        defer {
          sqlite3_finalize(trackStatement)
          sqlite3_finalize(fileStatement)
          sqlite3_finalize(selectStatement)
          sqlite3_finalize(deleteStatement)
        }
        guard
          sqlite3_prepare_v2(
            db,
            """
            INSERT INTO tracks(content_hash,title,duration,added_at,last_seen_at,missing)
            VALUES(?,?,?,?,?,0)
            ON CONFLICT(content_hash) DO UPDATE SET title = excluded.title,
              duration = CASE WHEN excluded.duration>0 THEN excluded.duration ELSE tracks.duration END,
              last_seen_at = excluded.last_seen_at, missing = 0
            """, -1, &trackStatement, nil) == SQLITE_OK,
          sqlite3_prepare_v2(
            db,
            """
            INSERT INTO files(path,content_hash,size,mtime_ns,ctime_ns,last_seen_at)
            VALUES(?,?,?,?,?,?)
            ON CONFLICT(path) DO UPDATE SET content_hash = excluded.content_hash,
              size = excluded.size,mtime_ns = excluded.mtime_ns,
              ctime_ns = excluded.ctime_ns,last_seen_at = excluded.last_seen_at
            """, -1, &fileStatement, nil) == SQLITE_OK
        else { return false }

        for (index, record) in records.enumerated() {
          sqlite3_reset(trackStatement)
          sqlite3_clear_bindings(trackStatement)
          sqlite3_bind_text(trackStatement, 1, record.hash, -1, sqliteTransientDestructor())
          sqlite3_bind_text(trackStatement, 2, record.title, -1, sqliteTransientDestructor())
          sqlite3_bind_double(trackStatement, 3, record.duration)
          sqlite3_bind_double(trackStatement, 4, seenAt)
          sqlite3_bind_double(trackStatement, 5, seenAt)
          guard sqlite3_step(trackStatement) == SQLITE_DONE else { return false }

          sqlite3_reset(fileStatement)
          sqlite3_clear_bindings(fileStatement)
          sqlite3_bind_text(fileStatement, 1, record.path, -1, sqliteTransientDestructor())
          sqlite3_bind_text(fileStatement, 2, record.hash, -1, sqliteTransientDestructor())
          sqlite3_bind_int64(fileStatement, 3, record.signature.size)
          sqlite3_bind_int64(fileStatement, 4, record.signature.mtimeNS)
          sqlite3_bind_int64(fileStatement, 5, record.signature.ctimeNS)
          sqlite3_bind_double(fileStatement, 6, seenAt)
          guard sqlite3_step(fileStatement) == SQLITE_DONE else { return false }
          if failAfterRecordForTesting == index + 1 { return false }
        }

        if complete {
          let seenPaths = Set(records.map(\.path))
          guard
            sqlite3_prepare_v2(db, "SELECT path FROM files", -1, &selectStatement, nil)
              == SQLITE_OK
          else { return false }
          var stale: [String] = []
          var selectStep = sqlite3_step(selectStatement)
          while selectStep == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(selectStatement, 0))
            if !seenPaths.contains(path) { stale.append(path) }
            selectStep = sqlite3_step(selectStatement)
          }
          guard selectStep == SQLITE_DONE else { return false }
          guard
            sqlite3_prepare_v2(
              db, "DELETE FROM files WHERE path = ?", -1,
              &deleteStatement, nil) == SQLITE_OK
          else { return false }
          for path in stale {
            sqlite3_reset(deleteStatement)
            sqlite3_clear_bindings(deleteStatement)
            sqlite3_bind_text(deleteStatement, 1, path, -1, sqliteTransientDestructor())
            guard sqlite3_step(deleteStatement) == SQLITE_DONE else { return false }
          }
          guard
            execute(
              "UPDATE tracks SET missing = CASE WHEN EXISTS(SELECT 1 FROM files f WHERE f.content_hash = tracks.content_hash) THEN 0 ELSE 1 END",
              on: db)
          else { return false }
        }

        guard execute("COMMIT", on: db) else { return false }
        committed = true
        return true
      } ?? false
    }
  }

  @discardableResult
  func upsertFile(
    path: String, hash: String, signature: FileSignature, title: String, duration: Double,
    seenAt: Double
  ) -> Bool {
    queue.sync {
      withDB { db in
        guard execute("BEGIN IMMEDIATE", on: db) else { return false }
        var committed = false
        defer {
          if !committed { _ = execute("ROLLBACK", on: db) }
        }
        var st: OpaquePointer?
        guard
          sqlite3_prepare_v2(
            db,
            """
            INSERT INTO tracks(content_hash,title,duration,added_at,last_seen_at,missing) VALUES(?,?,?,?,?,0)
            ON CONFLICT(content_hash) DO UPDATE SET title = excluded.title,
              duration = CASE WHEN excluded.duration>0 THEN excluded.duration ELSE tracks.duration END,
              last_seen_at = excluded.last_seen_at, missing = 0
            """, -1, &st, nil) == SQLITE_OK
        else { return false }
        sqlite3_bind_text(st, 1, hash, -1, sqliteTransientDestructor())
        sqlite3_bind_text(st, 2, title, -1, sqliteTransientDestructor())
        sqlite3_bind_double(st, 3, duration)
        sqlite3_bind_double(st, 4, seenAt)
        sqlite3_bind_double(st, 5, seenAt)
        guard sqlite3_step(st) == SQLITE_DONE else {
          sqlite3_finalize(st)
          return false
        }
        sqlite3_finalize(st)
        st = nil
        guard
          sqlite3_prepare_v2(
            db,
            """
            INSERT INTO files(path,content_hash,size,mtime_ns,ctime_ns,last_seen_at) VALUES(?,?,?,?,?,?)
            ON CONFLICT(path) DO UPDATE SET content_hash = excluded.content_hash,size = excluded.size,
              mtime_ns = excluded.mtime_ns,ctime_ns = excluded.ctime_ns,last_seen_at = excluded.last_seen_at
            """, -1, &st, nil) == SQLITE_OK
        else { return false }
        sqlite3_bind_text(st, 1, path, -1, sqliteTransientDestructor())
        sqlite3_bind_text(st, 2, hash, -1, sqliteTransientDestructor())
        sqlite3_bind_int64(st, 3, signature.size)
        sqlite3_bind_int64(st, 4, signature.mtimeNS)
        sqlite3_bind_int64(st, 5, signature.ctimeNS)
        sqlite3_bind_double(st, 6, seenAt)
        guard sqlite3_step(st) == SQLITE_DONE else {
          sqlite3_finalize(st)
          return false
        }
        sqlite3_finalize(st)
        guard execute("COMMIT", on: db) else { return false }
        committed = true
        return true
      } ?? false
    }
  }

  @discardableResult
  func reconcile(seenPaths: Set<String>) -> Bool {
    queue.sync {
      withDB { db in
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT path FROM files", -1, &st, nil) == SQLITE_OK
        else { return false }
        var stale: [String] = []
        while sqlite3_step(st) == SQLITE_ROW {
          let p = String(cString: sqlite3_column_text(st, 0))
          if !seenPaths.contains(p) { stale.append(p) }
        }
        sqlite3_finalize(st)
        guard execute("BEGIN IMMEDIATE", on: db) else { return false }
        var committed = false
        defer {
          if !committed { _ = execute("ROLLBACK", on: db) }
        }
        for p in stale {
          var d: OpaquePointer?
          guard
            sqlite3_prepare_v2(db, "DELETE FROM files WHERE path = ?", -1, &d, nil)
              == SQLITE_OK
          else { return false }
          sqlite3_bind_text(d, 1, p, -1, sqliteTransientDestructor())
          guard sqlite3_step(d) == SQLITE_DONE else {
            sqlite3_finalize(d)
            return false
          }
          sqlite3_finalize(d)
        }
        guard
          execute(
            "UPDATE tracks SET missing = CASE WHEN EXISTS(SELECT 1 FROM files f WHERE f.content_hash = tracks.content_hash) THEN 0 ELSE 1 END",
            on: db),
          execute("COMMIT", on: db)
        else { return false }
        committed = true
        return true
      } ?? false
    }
  }

  private func readTrack(_ stmt: OpaquePointer) -> Track {
    func text(_ i: Int32) -> String {
      guard let p = sqlite3_column_text(stmt, i) else { return "" }
      return String(cString: p)
    }
    func optionalDouble(_ i: Int32) -> Double? {
      sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i)
    }
    return Track(
      contentHash: text(0), title: text(1), duration: sqlite3_column_double(stmt, 2),
      position: sqlite3_column_double(stmt, 3), completed: sqlite3_column_int(stmt, 4) != 0,
      completedAt: optionalDouble(5), lastPlayedAt: optionalDouble(6),
      addedAt: sqlite3_column_double(stmt, 7), lastSeenAt: sqlite3_column_double(stmt, 8),
      missing: sqlite3_column_int(stmt, 9) != 0, path: text(10))
  }

  func track(hash: String) -> Track? {
    queue.sync {
      withDB { db in
        var rawStatement: OpaquePointer?
        guard
          sqlite3_prepare_v2(
            db,
            """
            SELECT t.content_hash,t.title,t.duration,t.position,t.completed,t.completed_at,t.last_played_at,t.added_at,t.last_seen_at,t.missing,
              COALESCE((SELECT MIN(path) FROM files f WHERE f.content_hash = t.content_hash),'')
            FROM tracks t WHERE t.content_hash = ?
            """, -1, &rawStatement, nil) == SQLITE_OK,
          let statement = rawStatement
        else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, hash, -1, sqliteTransientDestructor())
        return sqlite3_step(statement) == SQLITE_ROW ? readTrack(statement) : nil
      } ?? nil
    }
  }

  func tracks(section: LibrarySection, query: String) -> [Track] {
    queue.sync {
      withDB { db -> [Track] in
        var whereParts = ["t.missing = 0"]
        switch section {
        case .all: break
        case .continue: whereParts += ["t.completed = 0", "t.position>=10"]
        case .upNext: whereParts += ["t.completed = 0", "t.position<10"]
        case .completed: whereParts += ["t.completed = 1"]
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql = """
          SELECT t.content_hash,t.title,t.duration,t.position,t.completed,t.completed_at,t.last_played_at,t.added_at,t.last_seen_at,t.missing,
            COALESCE((SELECT MIN(path) FROM files f WHERE f.content_hash = t.content_hash),'')
          FROM tracks t WHERE \(whereParts.joined(separator:" AND "))
          """
        var rawStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &rawStatement, nil) == SQLITE_OK,
          let statement = rawStatement
        else { return [] }
        defer { sqlite3_finalize(statement) }
        var out: [Track] = []
        while sqlite3_step(statement) == SQLITE_ROW {
          let track = readTrack(statement)
          // SQLite LOWER/LIKE fold ASCII only and treat '%'/'_' as wildcards.
          // Finder-style search handles Unicode titles and literal input.
          if q.isEmpty || track.title.localizedStandardContains(q) { out.append(track) }
        }
        switch section {
        case .continue:
          out.sort {
            ($0.lastPlayedAt ?? 0) == ($1.lastPlayedAt ?? 0)
              ? naturalLess(
                $0.path.isEmpty ? $0.title : $0.path, $1.path.isEmpty ? $1.title : $1.path)
              : ($0.lastPlayedAt ?? 0) > ($1.lastPlayedAt ?? 0)
          }
        case .completed:
          out.sort {
            ($0.completedAt ?? 0) == ($1.completedAt ?? 0)
              ? naturalLess(
                $0.path.isEmpty ? $0.title : $0.path, $1.path.isEmpty ? $1.title : $1.path)
              : ($0.completedAt ?? 0) > ($1.completedAt ?? 0)
          }
        default:
          out.sort {
            naturalLess($0.path.isEmpty ? $0.title : $0.path, $1.path.isEmpty ? $1.title : $1.path)
          }
        }
        return out
      } ?? []
    }
  }

  func counts() -> LibraryCounts {
    queue.sync {
      withDB { db in
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        guard
          sqlite3_prepare_v2(
            db,
            """
            SELECT
              SUM(CASE WHEN missing = 0 THEN 1 ELSE 0 END),
              SUM(CASE WHEN missing = 0 AND completed = 0 AND position>=10 THEN 1 ELSE 0 END),
              SUM(CASE WHEN missing = 0 AND completed = 0 AND position<10 THEN 1 ELSE 0 END),
              SUM(CASE WHEN missing = 0 AND completed = 1 THEN 1 ELSE 0 END)
            FROM tracks
            """, -1, &st, nil) == SQLITE_OK
        else { return LibraryCounts() }
        guard sqlite3_step(st) == SQLITE_ROW else { return LibraryCounts() }
        return LibraryCounts(
          all: Int(sqlite3_column_int(st, 0)), continue: Int(sqlite3_column_int(st, 1)),
          upNext: Int(sqlite3_column_int(st, 2)), completed: Int(sqlite3_column_int(st, 3)))
      } ?? LibraryCounts()
    }
  }

  @discardableResult
  func setPosition(hash: String, position: Double, played: Bool = true) -> Bool {
    let succeeded = queue.sync {
      self.withDB { db in
        var st: OpaquePointer?
        guard
          sqlite3_prepare_v2(
            db,
            "UPDATE tracks SET position = ?,last_played_at = COALESCE(?,last_played_at) WHERE content_hash = ?",
            -1, &st, nil) == SQLITE_OK
        else { return false }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_double(st, 1, max(0, position))
        if played {
          sqlite3_bind_double(st, 2, Date().timeIntervalSince1970)
        } else {
          sqlite3_bind_null(st, 2)
        }
        sqlite3_bind_text(st, 3, hash, -1, sqliteTransientDestructor())
        return sqlite3_step(st) == SQLITE_DONE
      } ?? false
    }
    if !succeeded { logger.error("Failed to persist playback position") }
    return succeeded
  }
  @discardableResult
  func markCompleted(hash: String, completed: Bool) -> Bool {
    let succeeded = queue.sync {
      withDB { db in
        var st: OpaquePointer?
        guard
          sqlite3_prepare_v2(
            db,
            "UPDATE tracks SET completed = ?,completed_at = ?,position = CASE WHEN ? THEN 0 ELSE position END WHERE content_hash = ?",
            -1, &st, nil) == SQLITE_OK
        else { return false }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int(st, 1, completed ? 1 : 0)
        if completed {
          sqlite3_bind_double(st, 2, Date().timeIntervalSince1970)
        } else {
          sqlite3_bind_null(st, 2)
        }
        sqlite3_bind_int(st, 3, completed ? 1 : 0)
        sqlite3_bind_text(st, 4, hash, -1, sqliteTransientDestructor())
        return sqlite3_step(st) == SQLITE_DONE
      } ?? false
    }
    if !succeeded { logger.error("Failed to persist completed state") }
    return succeeded
  }
  @discardableResult
  func resetPosition(hash: String) -> Bool {
    setPosition(hash: hash, position: 0, played: false)
  }
}
