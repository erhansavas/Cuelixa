// SPDX-License-Identifier: Apache-2.0
import Foundation

// The standalone database smoke reuses production FileSignature from
// LocalFileAccess.swift and supplies only the AVFoundation-free sort helper.
func naturalLess(_ a: String, _ b: String) -> Bool {
  a.localizedStandardCompare(b) == .orderedAscending
}
