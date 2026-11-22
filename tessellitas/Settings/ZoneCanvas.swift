//
//  ZoneCanvas.swift
//  tessellitas
//

import SwiftUI

/// A miniature display showing a profile's zones.
///
/// `.editor`: zones can be dragged, and resized with the handles on the selected zone.
/// Everything snaps to a 1/60 grid, the coarsest one that represents halves, thirds,
/// quarters, fifths and sixths exactly.
/// `.thumbnail`: a quiet, read-only tessellation, like the app icon.
struct ZoneCanvas: View {
    enum Style { case editor, thumbnail }

    @Binding var zones: [Zone]
    @Binding var selection: UUID?
    var aspect: Double
    var style: Style = .editor

    @State private var dragOrigin: Zone?

    private static let grid = 60.0
    private static let handleHit: CGFloat = 20

    private var isEditor: Bool { style == .editor }
    private var cornerRadius: CGFloat { isEditor ? 12 : 6 }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                background

                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    zoneView(zone, number: index + 1, size: size)
                        .zIndex(zone.id == selection ? 1 : 0)
                }

                if isEditor, let selected = zones.first(where: { $0.id == selection }) {
                    handle(at: CGPoint(x: selected.x * size.width, y: selected.y * size.height),
                           id: selected.id, size: size, topLeft: true)
                    handle(at: CGPoint(x: (selected.x + selected.width) * size.width,
                                       y: (selected.y + selected.height) * size.height),
                           id: selected.id, size: size, topLeft: false)
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            shape.fill(isEditor ? AnyShapeStyle(.background) : AnyShapeStyle(.quaternary))
            if isEditor {
                shape.fill(LinearGradient(colors: [Color.accentColor.opacity(0.10), Color.accentColor.opacity(0.02)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            shape.strokeBorder(.separator)
        }
    }

    @ViewBuilder
    private func zoneView(_ zone: Zone, number: Int, size: CGSize) -> some View {
        let inset: CGFloat = isEditor ? 3 : 1.5
        let frame = CGRect(x: zone.x * size.width, y: zone.y * size.height,
                           width: zone.width * size.width, height: zone.height * size.height)
            .insetBy(dx: inset, dy: inset)
        let isSelected = zone.id == selection

        if isEditor {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            ZStack {
                shape.fill(Color.accentColor.opacity(isSelected ? 0.30 : 0.15))
                shape.strokeBorder(Color.accentColor.opacity(isSelected ? 1 : 0.45), lineWidth: isSelected ? 2 : 1)
                VStack(spacing: 2) {
                    Text("\(number)")
                        .font(.system(size: min(30, max(10, min(frame.width, frame.height) / 3)), weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    if isSelected, frame.width > 90, frame.height > 64 {
                        Text("\(percent(zone.width)) × \(percent(zone.height))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: max(frame.width, 1), height: max(frame.height, 1))
            .contentShape(Rectangle())
            .position(x: frame.midX, y: frame.midY)
            .gesture(moveGesture(id: zone.id, size: size))
            .onTapGesture { selection = zone.id }
            .accessibilityElement()
            .accessibilityLabel("Zone \(number)")
        } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.accentColor.opacity(0.55))
                .frame(width: max(frame.width, 1), height: max(frame.height, 1))
                .position(x: frame.midX, y: frame.midY)
        }
    }

    private func percent(_ fraction: Double) -> String {
        "\((fraction * 100).formatted(.number.precision(.fractionLength(0...1))))%"
    }

    // MARK: Gestures

    private func moveGesture(id: UUID, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard let start = beginDrag(id) else { return }
                let x = snap(start.x + value.translation.width / size.width)
                let y = snap(start.y + value.translation.height / size.height)
                edit(id) {
                    $0.x = min(max(x, 0), 1 - start.width)
                    $0.y = min(max(y, 0), 1 - start.height)
                }
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func handle(at point: CGPoint, id: UUID, size: CGSize, topLeft: Bool) -> some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .frame(width: 11, height: 11)
            .frame(width: Self.handleHit, height: Self.handleHit)
            .contentShape(Rectangle())
            .position(point)
            .zIndex(2)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard let start = beginDrag(id) else { return }
                        let dx = value.translation.width / size.width
                        let dy = value.translation.height / size.height
                        edit(id) { zone in
                            if topLeft {
                                let right = start.x + start.width, bottom = start.y + start.height
                                zone.x = min(max(snap(start.x + dx), 0), right - Zone.minSize)
                                zone.y = min(max(snap(start.y + dy), 0), bottom - Zone.minSize)
                                zone.width = Zone.round6(right - zone.x)
                                zone.height = Zone.round6(bottom - zone.y)
                            } else {
                                let right = min(max(snap(start.x + start.width + dx), start.x + Zone.minSize), 1)
                                let bottom = min(max(snap(start.y + start.height + dy), start.y + Zone.minSize), 1)
                                zone.width = Zone.round6(right - start.x)
                                zone.height = Zone.round6(bottom - start.y)
                            }
                        }
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
    }

    // MARK: Helpers

    /// Remembers the zone as it was when the drag began, so snapping applies to the total translation.
    private func beginDrag(_ id: UUID) -> Zone? {
        selection = id
        if dragOrigin == nil { dragOrigin = zones.first { $0.id == id } }
        return dragOrigin
    }

    private func edit(_ id: UUID, _ change: (inout Zone) -> Void) {
        guard let index = zones.firstIndex(where: { $0.id == id }) else { return }
        change(&zones[index])
        zones[index].x = Zone.round6(zones[index].x)
        zones[index].y = Zone.round6(zones[index].y)
    }

    private func snap(_ value: Double) -> Double {
        Zone.round6((value * Self.grid).rounded() / Self.grid)
    }
}

#Preview("Editor") {
    @Previewable @State var zones = Zone.grid(columns: [1, 3, 1])
    @Previewable @State var selection: UUID?
    ZoneCanvas(zones: $zones, selection: $selection, aspect: 21.0 / 9)
        .padding(24)
        .frame(width: 640)
}

#Preview("Thumbnails") {
    HStack(alignment: .top, spacing: 16) {
        ZoneCanvas(zones: .constant(Zone.grid(columns: [1, 3, 1])), selection: .constant(nil),
                   aspect: 32.0 / 9, style: .thumbnail).frame(width: 160)
        ZoneCanvas(zones: .constant(Zone.grid(columns: [1, 1], rows: [1, 1])), selection: .constant(nil),
                   aspect: 16.0 / 9, style: .thumbnail).frame(width: 100)
    }
    .padding(24)
}
