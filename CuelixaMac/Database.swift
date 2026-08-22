// SPDX-License-Identifier: Apache-2.0
import Foundation
import SQLite3

private func sqliteTransientDestructor() -> sqlite3_destructor_type {
  unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

// SAFETY: SQLite connection state never escapes this type. Every public database
// operation is serialized through `queue`; the connection is opened with FULLMUTEX
// as a second line of defense. `@unchecked Sendable` documents that synchronization.
final class LibraryDatabase: @unchecked Sendable {
  private let url: URL
  private let queue = DispatchQueue(label: "io.github.erhansavas.Cuelixa.database")
  private var connection: OpaquePointer?
  private(set) var initializationError: String?

  init(url: URL = AppPaths.database) {
    self.url = url
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch {
      initializationError = error.localizedDescription
      return
    }
    let initialized = queue.sync {
      guard let db = openConnection() else { return false }
      if !createSchema(db) {
        let message = sqliteMessage(db)
        initializationError = message
        NSLog("Cuelixa: library database schema initialization failed: %@", message)
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
        url.path, &raw, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
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

  func existingTrack(hash: String) -> Track? { track(hash: hash) }

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
        var params = [String]()
        switch section {
        case .all: break
        case .continue: whereParts += ["t.completed = 0", "t.position>=10"]
        case .upNext: whereParts += ["t.completed = 0", "t.position<10"]
        case .completed: whereParts += ["t.completed = 1"]
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
          whereParts.append("LOWER(t.title) LIKE ?")
          params.append("%\(q.lowercased())%")
        }
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
        for (i, p) in params.enumerated() {
          sqlite3_bind_text(statement, Int32(i + 1), p, -1, sqliteTransientDestructor())
        }
        var out: [Track] = []
        while sqlite3_step(statement) == SQLITE_ROW { out.append(readTrack(statement)) }
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
    if !succeeded { NSLog("Cuelixa: failed to persist playback position") }
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
    if !succeeded { NSLog("Cuelixa: failed to persist completed state") }
    return succeeded
  }
  @discardableResult
  func resetPosition(hash: String) -> Bool {
    setPosition(hash: hash, position: 0, played: false)
  }
}
