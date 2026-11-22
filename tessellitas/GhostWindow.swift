//
//  GhostWindow.swift
//  tessellitas
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
private final class GhostModel {
    var number: Int? = 1
    var name = ""
    var modifiers: [String] = []
}

/// A click-through translucent panel that shows where the window is about to land.
@MainActor
final class GhostWindow {
    private let model = GhostModel()
    private var isShown = false
    private var generation = 0

    /// Built on first use: nothing exists on screen (or in memory) until the first show.
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: GhostView(model: model))
        host.sizingOptions = []   // the panel's frame is ours; don't let SwiftUI resize it
        panel.contentView = host
        return panel
    }()

    /// Both frames in AppKit coordinates. The first call grows the ghost out of `origin`
    /// (the window's current frame); later calls glide it from zone to zone.
    func show(from origin: CGRect, to target: CGRect, number: Int?, name: String,
              modifiers: [String], duration: TimeInterval) {
        generation += 1
        model.number = number
        model.name = name
        model.modifiers = modifiers

        if !isShown {
            isShown = true
            panel.setFrame(origin, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide(duration: TimeInterval) {
        guard isShown else { return }
        isShown = false
        generation += 1
        let expected = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // A newer show() must not be hidden by an older fade-out finishing.
            MainActor.assumeIsolated {
                if let self, self.generation == expected { self.panel.orderOut(nil) }
            }
        }
    }
}

/// The system HUD material, forced active: a non-activating panel would otherwise render it flat grey.
struct HUDBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct GhostView: View {
    let model: GhostModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        GeometryReader { proxy in
            ZStack {
                HUDBackground().clipShape(shape)
                shape.fill(Color.accentColor.opacity(0.22))

                VStack(spacing: 2) {
                    Group {
                        if let number = model.number {
                            Text("\(number)")
                        } else {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")   // maximize
                        }
                    }
                    .font(.system(size: min(72, proxy.size.height / 3), weight: .light, design: .rounded))
                    Text(model.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .minimumScaleFactor(0.4)
                .padding(10)

                if proxy.size.height > 150, proxy.size.width > 300 {
                    HStack(spacing: 6) {
                        Text("Release").font(.caption)
                        KeyCombo(keys: model.modifiers)
                        Text("to apply").font(.caption)
                        KeyCap("esc").padding(.leading, 8)
                        Text("Cancel").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 14)
                }
            }
        }
    }
}

#Preview("Ghost") {
    let model = GhostModel()
    model.number = 2
    model.name = "Ultrawide 1-3-1"
    model.modifiers = ["⌃", "⌥"]
    return GhostView(model: model)
        .frame(width: 560, height: 340)
        .padding(40)
        .background(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
}

#Preview("Ghost, maximize") {
    let model = GhostModel()
    model.number = nil
    model.name = "Fill the screen"
    model.modifiers = ["⌃", "⌥"]
    return GhostView(model: model)
        .frame(width: 560, height: 340)
        .padding(40)
        .background(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
}
