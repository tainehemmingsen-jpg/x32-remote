import Foundation
import os

/// Debug builds only: counts how often views redraw and logs the totals once a second, so
/// over-eager redraws show up (watch with: log stream --predicate 'subsystem == "nz.taine.x32remote"').
enum PerfProbe {
    #if DEBUG
    private static var counts: [String: Int] = [:]
    private static var started = false
    private static let log = Logger(subsystem: "nz.taine.x32remote", category: "perf")

    static func hit(_ name: String) {
        counts[name, default: 0] += 1
        if !started {
            started = true
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                let line = counts.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
                if !line.isEmpty { log.notice("redraws/s \(line, privacy: .public)") }
                counts.removeAll(keepingCapacity: true)
            }
        }
    }
    #else
    @inline(__always) static func hit(_ name: String) {}
    #endif
}
