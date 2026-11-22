//
//  OSDWindow.swift
//  tessellitas
//

import AppKit
import Observation
import SwiftUI

/// What the on-screen display shows: either a layout with one zone lit and a size, or a short notice.
struct OSDContent: Equatable {
    var zones: [Zone] = []
    var aspect = 16.0 / 9
    var active: Int?
    var title: String
    var caption: String
    /// Shown instead of the layout when there is none.
    var symbol = "rectangle.split.3x1"

    static func notice(_ title: String, _ caption: String, symbol: String) -> OSDContent {
        OSDContent(title: title, caption: caption, symbol: symbol)
    }
}

@MainActor
@Observable
private final class OSDModel {
    var content = OSDContent(title: "", caption: "")
}

/// A brief, click-through heads-up display, like the system volume HUD.
/// Repeated calls update it in place and keep it up.
@MainActor
final class OSDWindow {
    private static let size = CGSize(width: 320, height: 96)
    private static let hold: TimeInterval = 1.2

    private let model = OSDModel()
    private var hideTimer: Timer?
    private var isShown = false
    private var generation = 0

    /// Built on first use: nothing exists on screen (or in memory) until the first show.
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // the system shadow draws a thin dark rim
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: OSDView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }()

    /// `anchor` and `bounds` are in AppKit coordinates. The OSD sits just above the bottom edge of
    /// the anchor (the window being resized), centred on it, and stays inside `bounds`.
    func show(_ content: OSDContent, near anchor: CGRect, within bounds: CGRect) {
        generation += 1

        withAnimation(.snappy(duration: 0.2)) { model.content = content }

        let size = Self.size
        var origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY + 90)
        let area = bounds.insetBy(dx: 12, dy: 12)
        origin.x = min(max(origin.x, area.minX), max(area.minX, area.maxX - size.width))
        origin.y = min(max(origin.y, area.minY), max(area.minY, area.maxY - size.height))
        let frame = CGRect(origin: origin, size: size)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            if !isShown {
                isShown = true
                panel.setFrame(frame.offsetBy(dx: 0, dy: -8), display: false)
                panel.alphaValue = 0
                panel.orderFrontRegardless()
            }
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.hold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func hide() {
        guard isShown else { return }
        isShown = false
        let expected = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // A newer show() must not be hidden by an older fade-out finishing.
            MainActor.assumeIsolated {
                if let self, self.generation == expected { self.panel.orderOut(nil) }
            }
        }
    }
}

private struct OSDView: View {
    let model: OSDModel

    var body: some View {
        let content = model.content
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        HStack(spacing: 18) {
            Group {
                if content.zones.isEmpty {
                    Image(systemName: content.symbol)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(width: 150)
                } else {
                    LayoutMeter(zones: content.zones, active: content.active)
                        .frame(width: 150, height: min(max(150 / content.aspect, 30), 64))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.system(size: content.zones.isEmpty ? 17 : 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(content.caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HUDBackground().clipShape(shape))
    }
}

/// The whole layout in miniature, with one zone lit. Zones animate as they grow and shrink.
struct LayoutMeter: View {
    let zones: [Zone]
    let active: Int?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.primary.opacity(0.06))
                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    let frame = CGRect(x: zone.x * size.width, y: zone.y * size.height,
                                       width: zone.width * size.width, height: zone.height * size.height)
                        .insetBy(dx: 1.5, dy: 1.5)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(index == active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary.opacity(0.22)))
                        .frame(width: max(frame.width, 1), height: max(frame.height, 1))
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: zones)
        .accessibilityHidden(true)
    }
}

#Preview("OSD") {
    @MainActor func model(_ content: OSDContent) -> OSDModel {
        let model = OSDModel()
        model.content = content
        return model
    }
    let zones = ZoneResizer.resized(Zone.grid(columns: [1, 3, 1]), index: 1, by: 0.05) ?? []
    return VStack(spacing: 20) {
        OSDView(model: model(OSDContent(zones: zones, aspect: 32.0 / 9, active: 1, title: "65%", caption: "Zone 2 width")))
        OSDView(model: model(OSDContent(zones: zones, aspect: 32.0 / 9, active: 1, title: "80%", caption: "Can’t grow further")))
        OSDView(model: model(.notice("Not in a zone", "Place this window in a zone first.", symbol: "rectangle.dashed")))
    }
    .frame(width: 320)
    .padding(40)
    .background(LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
}
