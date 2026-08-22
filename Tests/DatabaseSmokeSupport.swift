// SPDX-License-Identifier: Apache-2.0
import Foundation

// Minimal equivalents required to compile Database.swift in isolation. The
// production definitions live in Utilities.swift; this smoke intentionally
// avoids AVFoundation so database behavior can also be exercised on the host.
struct FileSignature: Equatable {
  let size: Int64
  let mtimeNS: Int64
  let ctimeNS: Int64
}

func naturalLess(_ a: String, _ b: String) -> Bool {
  a.localizedStandardCompare(b) == .orderedAscending
}
