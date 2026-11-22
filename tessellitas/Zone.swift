//
//  Zone.swift
//  tessellitas
//

import Foundation

/// A tile, as fractions (0...1) of a display's usable area. Origin is top-left.
struct Zone: Codable, Hashable, Identifiable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// Runtime-only identity so editors can track zones across edits and reordering.
    var id = UUID()

    private enum CodingKeys: String, CodingKey { case x, y, width, height }

    static let minSize = 1.0 / 60

    /// Keeps the zone inside the display and at least `minSize` big.
    func clamped() -> Zone {
        var zone = self
        zone.x = min(max(x, 0), 1 - Zone.minSize)
        zone.y = min(max(y, 0), 1 - Zone.minSize)
        zone.width = min(max(width, Zone.minSize), 1 - zone.x)
        zone.height = min(max(height, Zone.minSize), 1 - zone.y)
        return zone
    }

    /// Row-major grid (zone 1 is top-left) from relative column and row weights,
    /// e.g. columns [1, 3, 1] gives 1/5, 3/5, 1/5.
    static func grid(columns: [Double], rows: [Double] = [1]) -> [Zone] {
        let xs = edges(columns)
        let ys = edges(rows)
        var zones: [Zone] = []
        for row in 0..<(ys.count - 1) {
            for column in 0..<(xs.count - 1) {
                zones.append(Zone(x: xs[column], y: ys[row],
                                  width: round6(xs[column + 1] - xs[column]),
                                  height: round6(ys[row + 1] - ys[row])))
            }
        }
        return zones
    }

    private static func edges(_ weights: [Double]) -> [Double] {
        let positive = weights.filter { $0 > 0 }
        let weights = positive.isEmpty ? [1] : positive
        let total = weights.reduce(0, +)
        var running = 0.0
        var edges = [0.0]
        for weight in weights {
            running += weight
            edges.append(round6(running / total))
        }
        edges[edges.count - 1] = 1
        return edges
    }

    static func round6(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }
}
