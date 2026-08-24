// SPDX-License-Identifier: Apache-2.0
import Foundation
import OSLog

enum ImportDisposition: String, Sendable, Equatable {
  case imported, duplicate, unsupported, failed, cancelled
}

struct ImportFileResult: Sendable {
  let sourceName: String
  let disposition: ImportDisposition
  let destinationName: String?
  let detail: String?
}

struct ImportSummary: Sendable {
  let results: [ImportFileResult]
  func count(_ disposition: ImportDisposition) -> Int {
    results.lazy.filter { $0.disposition == disposition }.count
  }
  var hasProblems: Bool {
    count(.failed) > 0 || count(.unsupported) > 0 || count(.cancelled) > 0
  }
}

actor ImportCoordinator {
  private let logger = Logger(subsystem: "io.github.erhansavas.Cuelixa", category: "Import")
  private let directories: AppDirectories
  init(directories: AppDirectories) { self.directories = directories }

  func importFiles(_ urls: [URL]) -> ImportSummary {
    var results: [ImportFileResult] = []
    results.reserveCapacity(urls.count)
    do {
      try directories.ensure()
    } catch {
      return ImportSummary(
        results: urls.map {
          .init(
            sourceName: $0.lastPathComponent, disposition: .failed, destinationName: nil,
            detail: "The library folder could not be prepared: \(error.localizedDescription)")
        })
    }

    for (index, url) in urls.enumerated() {
      if Task.isCancelled {
        results.append(
          contentsOf: urls[index...].map {
            .init(
              sourceName: $0.lastPathComponent, disposition: .cancelled,
              destinationName: nil, detail: "Import was cancelled.")
          })
        break
      }
      results.append(importOne(url))
    }
    return ImportSummary(results: results)
  }

  private func importOne(_ originalURL: URL) -> ImportFileResult {
    let name = originalURL.lastPathComponent
    guard LibraryScanner.audioExtensions.contains(originalURL.pathExtension.lowercased()) else {
      return .init(
        sourceName: name, disposition: .unsupported, destinationName: nil,
        detail: "Unsupported audio extension.")
    }
    let fm = FileManager.default
    let source = originalURL.standardizedFileURL.resolvingSymlinksInPath()
    let root = directories.library.standardizedFileURL.resolvingSymlinksInPath()
    do {
      try Task.checkCancellation()
      let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
      guard values.isRegularFile == true, values.isReadable == true else {
        throw CocoaError(.fileReadNoPermission)
      }
      if source.path == root.path || source.path.hasPrefix(root.path + "/") {
        return .init(
          sourceName: name, disposition: .duplicate, destinationName: name,
          detail: "The file is already inside the Cuelixa library.")
      }

      guard let sourceSignature = fileSignature(source) else { throw ImportError.hashFailed }

      var destination = root.appendingPathComponent(source.lastPathComponent)
      if fm.fileExists(atPath: destination.path) {
        if try filesMatch(source, destination) {
          return .init(
            sourceName: name, disposition: .duplicate,
            destinationName: destination.lastPathComponent,
            detail: "An identical file is already in the library.")
        }
        destination = try availableDestination(for: source, root: root)
      }

      let temporary = root.appendingPathComponent(".cuelixa-import-\(UUID().uuidString).tmp")
      defer {
        if fm.fileExists(atPath: temporary.path) {
          do {
            try fm.removeItem(at: temporary)
          } catch {
            logger.error(
              "Could not remove import staging file: \(error.localizedDescription, privacy: .private)"
            )
          }
        }
      }
      try fm.copyItem(at: source, to: temporary)
      try Task.checkCancellation()
      guard fileSignature(source) == sourceSignature else { throw ImportError.sourceChanged }
      guard try filesMatch(source, temporary) else { throw ImportError.sourceChanged }
      while true {
        do {
          try fm.moveItem(at: temporary, to: destination)
          return .init(
            sourceName: name, disposition: .imported,
            destinationName: destination.lastPathComponent, detail: nil)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
          destination = try availableDestination(for: source, root: root)
        }
      }
    } catch is CancellationError {
      return .init(
        sourceName: name, disposition: .cancelled, destinationName: nil,
        detail: "Import was cancelled.")
    } catch {
      return .init(
        sourceName: name, disposition: .failed, destinationName: nil,
        detail: error.localizedDescription)
    }
  }

  private func filesMatch(_ first: URL, _ second: URL) throws -> Bool {
    guard let a = fileSignature(first), let b = fileSignature(second), a.size == b.size else {
      return false
    }
    try Task.checkCancellation()
    let firstHash = try sha256FileCheckingCancellation(first)
    let secondHash = try sha256FileCheckingCancellation(second)
    return firstHash == secondHash
  }

  private func availableDestination(for source: URL, root: URL) throws -> URL {
    let fm = FileManager.default
    let stem = source.deletingPathExtension().lastPathComponent
    let suffix = source.pathExtension
    for index in 2..<10_000 {
      try Task.checkCancellation()
      let name = suffix.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(suffix)"
      let candidate = root.appendingPathComponent(name)
      if !fm.fileExists(atPath: candidate.path) { return candidate }
    }
    throw ImportError.noDestination
  }
}

private enum ImportError: LocalizedError {
  case hashFailed, sourceChanged, noDestination
  var errorDescription: String? {
    switch self {
    case .hashFailed: "The copied file could not be verified."
    case .sourceChanged: "The source file changed while it was being imported."
    case .noDestination: "No safe destination filename was available."
    }
  }
}
