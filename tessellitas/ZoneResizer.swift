//
//  ZoneResizer.swift
//  tessellitas
//

import Foundation

/// Grows or shrinks one zone of a layout by sliding the edges it shares with its neighbours,
/// so every zone stays flush. Pure geometry, in fractions of the display: no windows involved.
enum ZoneResizer {
    /// Neighbours never shrink below this share of the display along the resized axis.
    static let minFraction = 0.10

    private static let epsilon = 0.001

    private struct Axis {
        let start: WritableKeyPath<Zone, Double>
        let length: WritableKeyPath<Zone, Double>
        let crossStart: WritableKeyPath<Zone, Double>
        let crossLength: WritableKeyPath<Zone, Double>

        static let horizontal = Axis(start: \.x, length: \.width, crossStart: \.y, crossLength: \.height)
        static let vertical = Axis(start: \.y, length: \.height, crossStart: \.x, crossLength: \.width)
    }

    enum Dimension { case width, height }

    /// Which dimension `resized` would change for this zone, or nil if it has no neighbours at all.
    static func dimension(of zones: [Zone], index: Int) -> Dimension? {
        guard zones.indices.contains(index) else { return nil }
        if hasNeighbour(zones, index, .horizontal) { return .width }
        if hasNeighbour(zones, index, .vertical) { return .height }
        return nil
    }

    /// Resizes zone `index` by `delta` (positive grows, negative shrinks), as a fraction of the display.
    ///
    /// The axis is the one the zone is split along: side by side (columns) resizes the width,
    /// stacked (rows) resizes the height; columns win when a zone has both kinds of neighbour.
    /// The growth is shared between both edges, or goes entirely to one edge when the zone
    /// touches the screen edge. Returns nil if nothing can move (no neighbours, or at the limit).
    static func resized(_ zones: [Zone], index: Int, by delta: Double) -> [Zone]? {
        guard zones.indices.contains(index), delta != 0 else { return nil }
        for axis in [Axis.horizontal, .vertical] where hasNeighbour(zones, index, axis) {
            return resize(zones, index, delta, axis)
        }
        return nil
    }

    private static func hasNeighbour(_ zones: [Zone], _ index: Int, _ axis: Axis) -> Bool {
        let zone = zones[index]
        let start = zone[keyPath: axis.start], end = start + zone[keyPath: axis.length]
        let crossStart = zone[keyPath: axis.crossStart], crossEnd = crossStart + zone[keyPath: axis.crossLength]
        return zones.indices.contains { other in
            guard other != index else { return false }
            let z = zones[other]
            let zStart = z[keyPath: axis.start], zEnd = zStart + z[keyPath: axis.length]
            let zCrossStart = z[keyPath: axis.crossStart], zCrossEnd = zCrossStart + z[keyPath: axis.crossLength]
            let touches = abs(zEnd - start) < epsilon || abs(zStart - end) < epsilon
            let overlaps = min(crossEnd, zCrossEnd) - max(crossStart, zCrossStart) > epsilon
            return touches && overlaps
        }
    }

    private static func resize(_ zones: [Zone], _ index: Int, _ delta: Double, _ axis: Axis) -> [Zone]? {
        let start = zones[index][keyPath: axis.start]
        let end = start + zones[index][keyPath: axis.length]
        let startMovable = start > epsilon
        let endMovable = end < 1 - epsilon
        guard startMovable || endMovable else { return nil }

        // How far each edge may travel in the direction of the change before something gets too small.
        let direction: Double = delta > 0 ? 1 : -1
        let total = abs(delta)
        let startCapacity = startMovable ? abs(clampedShift(zones, line: start, shift: -direction, axis)) : 0
        let endCapacity = endMovable ? abs(clampedShift(zones, line: end, shift: direction, axis)) : 0

        // Split evenly, then hand whatever one side couldn't take to the other.
        var startTravel = min(startMovable && endMovable ? total / 2 : total, startCapacity)
        var endTravel = min(startMovable && endMovable ? total / 2 : total, endCapacity)
        if startMovable && endMovable {
            var leftover = total - startTravel - endTravel
            let extraStart = min(leftover, startCapacity - startTravel)
            startTravel += extraStart
            leftover -= extraStart
            endTravel += min(leftover, endCapacity - endTravel)
        } else if startMovable {
            endTravel = 0
        } else {
            startTravel = 0
        }
        guard startTravel + endTravel > epsilon / 10 else { return nil }

        let newStart = start - direction * startTravel
        let newEnd = end + direction * endTravel

        func moved(_ value: Double) -> Double {
            if abs(value - start) < epsilon { return newStart }
            if abs(value - end) < epsilon { return newEnd }
            return value
        }

        return zones.map { zone in
            var zone = zone
            let zoneStart = moved(zone[keyPath: axis.start])
            let zoneEnd = moved(zone[keyPath: axis.start] + zone[keyPath: axis.length])
            zone[keyPath: axis.start] = Zone.round6(zoneStart)
            zone[keyPath: axis.length] = Zone.round6(zoneEnd - zoneStart)
            return zone
        }
    }

    /// Limits how far the shared edge at `line` may slide: zones ending there must stay at least
    /// `minFraction` wide, and so must zones starting there. Zero is always allowed.
    private static func clampedShift(_ zones: [Zone], line: Double, shift: Double, _ axis: Axis) -> Double {
        var lowest = -line
        var highest = 1 - line
        for zone in zones {
            let zoneStart = zone[keyPath: axis.start]
            let length = zone[keyPath: axis.length]
            if abs(zoneStart + length - line) < epsilon { lowest = max(lowest, minFraction - length) }
            if abs(zoneStart - line) < epsilon { highest = min(highest, length - minFraction) }
        }
        return min(max(shift, min(lowest, 0)), max(highest, 0))
    }
}
