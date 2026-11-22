//
//  TileController.swift
//  tessellitas
//

import AppKit
import Carbon.HIToolbox
import OSLog

enum TileCommand {
    case zone(Int)   // zero-based index into the display's profile
    case next
    case previous
    case grow
    case shrink
    case maximize   // the display's whole usable area; not macOS full screen
}

/// Turns hotkeys into window moves.
///
/// **Assigning** (zone keys, ←/→, Return): hold the modifiers and press a key to see a ghost of the
/// target; more keys retarget it. Release the modifiers to apply, or press Escape to cancel.
/// Return targets the display's whole usable area, below the menu bar and beside the Dock.
///
/// **Resizing** (↑/↓): grows or shrinks the focused window's zone and slides its neighbours
/// so everything stays flush. Applies immediately. ↑ on a window that sits in no zone drops it into
/// the middle zone instead. The new sizes live only in memory: assigning
/// any window to a zone again goes back to the profile as configured.
@MainActor
final class TileController {
    private enum Target: Equatable {
        case zone(Int)
        case maximized
    }

    private struct Session {
        let window: AXUIElement
        let appName: String
        let profile: Profile
        let displayID: String
        let rects: [CGRect]            // Accessibility coordinates; the configured layout
        let maximizedRect: CGRect
        let startFrame: CGRect
        let requiredModifiers: NSEvent.ModifierFlags
        let modifierSymbols: [String]
        let carbonModifiers: Int
        let animationDuration: TimeInterval
        var target: Target

        var rect: CGRect {
            switch target {
            case .zone(let index): rects[index]
            case .maximized: maximizedRect
            }
        }

        var zoneIndex: Int? {
            if case .zone(let index) = target { index } else { nil }
        }
    }

    /// A temporarily resized version of a display's profile. Never written to the config.
    private struct DynamicLayout {
        let profileID: UUID
        var zones: [Zone]
    }

    /// Where the focused window lives: its display, profile and the layout currently in force.
    private struct Context {
        let app: NSRunningApplication
        let window: AXUIElement
        let frame: CGRect
        let display: Display
        let profile: Profile
        let zones: [Zone]              // the dynamic layout if one exists, else the profile's
        let rects: [CGRect]            // `zones` as Accessibility rects
    }

    /// Apps with size increments (Terminal) or minimum sizes never land exactly on the target.
    private static let zoneMatchTolerance: CGFloat = 60
    /// How much a window must look like a zone to count as sitting in it (intersection over union).
    private static let tiledOverlap: CGFloat = 0.65
    private static let ghostDuration: TimeInterval = 0.14

    private let hotKeys: HotKeyCenter
    private let ghost = GhostWindow()
    private let animator = WindowAnimator()
    private let osd = OSDWindow()
    private let log = Logger(subsystem: "com.sovrin.Tessellitas", category: "tiler")

    private var session: Session?
    private var watchTimer: Timer?
    private var sessionHotKeys: [UInt32] = []
    private var dynamicLayouts: [String: DynamicLayout] = [:]   // by display ID

    init(hotKeys: HotKeyCenter) {
        self.hotKeys = hotKeys
    }

    func handle(_ command: TileCommand, config: Config) {
        switch command {
        case .grow:
            resize(by: config.resizeStep, config: config)
        case .shrink:
            resize(by: -config.resizeStep, config: config)
        default:
            assign(command, config: config)
        }
    }

    /// Abandons a pending preview, e.g. because the hotkeys are about to be re-registered.
    func cancel() {
        finish(commit: false)
    }

    /// Forgets all temporary sizes, e.g. because the profiles they were derived from changed.
    func resetLayouts() {
        dynamicLayouts = [:]
    }

    // MARK: - Assigning a window to a zone

    private func assign(_ command: TileCommand, config: Config) {
        if var session {
            guard let target = Self.retarget(command, from: session.zoneIndex, count: session.rects.count) else { return }
            session.target = target
            self.session = session
            showGhost(for: session, from: nil)
            return
        }

        guard ensureTrusted() else { return }
        animator.finish()
        guard let context = makeContext(config: config) else { return }

        // The window's current zone comes from the layout it was last placed with (possibly resized),
        // but it always lands in the configured one.
        let current = Self.zoneIndex(of: context.frame, in: context.rects, tolerance: Self.zoneMatchTolerance)
        let configured = context.profile.zones.map { Self.rect(for: $0, in: context.display.visibleFrameAX, gap: config.gap) }
        guard let target = Self.retarget(command, from: current, count: configured.count) else { return }

        let wholeArea = Zone(x: 0, y: 0, width: 1, height: 1)
        let session = Session(
            window: context.window, appName: context.app.localizedName ?? "?", profile: context.profile,
            displayID: context.display.id, rects: configured,
            maximizedRect: Self.rect(for: wholeArea, in: context.display.visibleFrameAX, gap: config.gap),
            startFrame: context.frame,
            requiredModifiers: config.requiredModifierFlags, modifierSymbols: config.hotkeyModifiers.map(\.symbol),
            carbonModifiers: config.carbonModifiers, animationDuration: config.animationDuration, target: target
        )

        // A quick tap releases the modifiers before we get here: skip the ghost and just move.
        let stillHeld = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(session.requiredModifiers)
        if stillHeld {
            self.session = session
            showGhost(for: session, from: session.startFrame)
            beginWatching(session)
        } else {
            commit(session)
        }
    }

    private func finish(commit shouldCommit: Bool) {
        guard let session else { return }
        self.session = nil
        watchTimer?.invalidate()
        watchTimer = nil
        sessionHotKeys.forEach(hotKeys.unregister)
        sessionHotKeys = []
        ghost.hide(duration: Self.ghostDuration)
        if shouldCommit { commit(session) }
    }

    private func beginWatching(_ session: Session) {
        // The modifiers are still held, so Escape arrives as a modifier+Escape chord.
        if let id = hotKeys.register(keyCode: kVK_Escape, modifiers: session.carbonModifiers, handler: { [weak self] in
            self?.finish(commit: false)
        }) {
            sessionHotKeys.append(id)
        }

        // Releasing the modifiers applies the move.
        watchTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let session = self.session else { return }
                let held = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if !held.contains(session.requiredModifiers) { self.finish(commit: true) }
            }
        }
    }

    private func commit(_ session: Session) {
        // Placing a window in a zone means "the layout as configured": drop any temporary sizes.
        dynamicLayouts[session.displayID] = nil

        let current = session.window.frame ?? session.startFrame
        animator.animate(session.window, from: current, to: session.rect, duration: session.animationDuration)
        log.debug("\(session.appName) -> \(session.profile.name) \(String(describing: session.target))")
    }

    private func showGhost(for session: Session, from origin: CGRect?) {
        let target = Display.flip(session.rect)
        ghost.show(from: origin.map(Display.flip) ?? target, to: target,
                   number: session.zoneIndex.map { $0 + 1 },
                   name: session.zoneIndex == nil ? "Fill the screen" : session.profile.name,
                   modifiers: session.modifierSymbols, duration: Self.ghostDuration)
    }

    // MARK: - Growing and shrinking

    private func resize(by delta: Double, config: Config) {
        guard session == nil, ensureTrusted() else { return }
        animator.finish()
        guard let context = makeContext(config: config) else { return }

        let screen = context.display.visibleFrame
        let windowOnScreen = Display.flip(context.frame)

        guard let active = Self.zoneIndex(of: context.frame, in: context.rects, tolerance: Self.zoneMatchTolerance) else {
            // Growing a loose window drops it into the middle zone of the layout in force.
            if delta > 0 {
                let middle = Self.middleZone(of: context.zones)
                animator.animate(context.window, from: context.frame, to: context.rects[middle], duration: config.animationDuration)
                osd.show(OSDContent(zones: context.zones, aspect: context.display.aspectRatio, active: middle,
                                    title: "Zone \(middle + 1)", caption: context.profile.name),
                         near: Display.flip(context.rects[middle]), within: screen)
                log.debug("grow loose window -> zone \(middle + 1)")
                return
            }
            osd.show(.notice("Not in a zone", "Place this window in a zone first.", symbol: "rectangle.dashed"),
                     near: windowOnScreen, within: screen)
            return
        }
        guard let dimension = ZoneResizer.dimension(of: context.zones, index: active) else {
            osd.show(.notice("Nothing to resize", "This zone has no neighbours.", symbol: "rectangle.split.1x2"),
                     near: windowOnScreen, within: screen)
            return
        }
        guard let newZones = ZoneResizer.resized(context.zones, index: active, by: delta) else {
            let limit = delta > 0 ? "Can’t grow further" : "Can’t shrink further"
            osd.show(Self.content(zones: context.zones, active: active, dimension: dimension, display: context.display, caption: limit),
                     near: windowOnScreen, within: screen)
            return
        }

        let area = context.display.visibleFrameAX
        let newRects = newZones.map { Self.rect(for: $0, in: area, gap: config.gap) }

        var moves = [WindowAnimator.Move(window: context.window, from: context.frame, to: newRects[active])]
        for other in WindowAccessibility.otherWindows(excluding: context.window) {
            // Only windows sitting in a zone whose edges moved follow along; everything else is left alone.
            guard Self.overlap(other.frame, area) > 0,
                  let zone = Self.zoneIndex(of: other.frame, in: context.rects, minimumOverlap: Self.tiledOverlap),
                  newRects[zone] != context.rects[zone]
            else { continue }
            moves.append(.init(window: other.window, from: other.frame, to: newRects[zone]))
        }

        dynamicLayouts[context.display.id] = DynamicLayout(profileID: context.profile.id, zones: newZones)
        animator.animate(moves, duration: config.animationDuration)
        osd.show(Self.content(zones: newZones, active: active, dimension: dimension, display: context.display,
                              caption: nil),
                 near: Display.flip(newRects[active]), within: screen)
        log.debug("resize zone \(active + 1) by \(delta): \(moves.count) windows")
    }

    /// The size of the active zone along the resized axis, as a big number, with the layout beside it.
    private static func content(zones: [Zone], active: Int, dimension: ZoneResizer.Dimension,
                                display: Display, caption: String?) -> OSDContent {
        let fraction = dimension == .width ? zones[active].width : zones[active].height
        return OSDContent(
            zones: zones, aspect: display.aspectRatio, active: active,
            title: "\(Int((fraction * 100).rounded()))%",
            caption: caption ?? "Zone \(active + 1) \(dimension == .width ? "width" : "height")"
        )
    }

    // MARK: - Resolving the focused window

    private func ensureTrusted() -> Bool {
        guard AXIsProcessTrusted() else {
            WindowAccessibility.requestAccess()
            return false
        }
        return true
    }

    private func makeContext(config: Config) -> Context? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = WindowAccessibility.focusedWindow(of: app),
              let frame = window.frame
        else { return nil }

        guard let display = Display.all().max(by: { Self.overlap(frame, $0.frameAX) < Self.overlap(frame, $1.frameAX) }),
              let profile = config.profile(for: display),
              !profile.zones.isEmpty
        else { return nil }

        var zones = profile.zones
        if let dynamic = dynamicLayouts[display.id], dynamic.profileID == profile.id, dynamic.zones.count == zones.count {
            zones = dynamic.zones
        }
        let rects = zones.map { Self.rect(for: $0, in: display.visibleFrameAX, gap: config.gap) }
        return Context(app: app, window: window, frame: frame, display: display, profile: profile, zones: zones, rects: rects)
    }

    private static func retarget(_ command: TileCommand, from zone: Int?, count: Int) -> Target? {
        switch command {
        case .zone(let index): index < count ? .zone(index) : nil
        case .next: .zone(min((zone ?? -1) + 1, count - 1))
        case .previous: .zone(max((zone ?? count) - 1, 0))
        case .maximize: .maximized
        case .grow, .shrink: nil
        }
    }

    // MARK: - Geometry

    /// Edges are rounded individually so neighbouring zones share an edge with no 1px gap.
    /// `gap` is the space between windows; the screen edge gets the full gap, shared edges half each.
    private static func rect(for zone: Zone, in area: CGRect, gap: Double) -> CGRect {
        let g = CGFloat(gap)
        let epsilon = 0.0005
        let left = (area.minX + zone.x * area.width).rounded() + (zone.x < epsilon ? g : g / 2)
        let right = (area.minX + (zone.x + zone.width) * area.width).rounded() - (zone.x + zone.width > 1 - epsilon ? g : g / 2)
        let top = (area.minY + zone.y * area.height).rounded() + (zone.y < epsilon ? g : g / 2)
        let bottom = (area.minY + (zone.y + zone.height) * area.height).rounded() - (zone.y + zone.height > 1 - epsilon ? g : g / 2)
        return CGRect(x: left, y: top, width: max(right - left, 1), height: max(bottom - top, 1)).integral
    }

    /// The zone whose centre is closest to the display's centre; ties go to the first.
    private static func middleZone(of zones: [Zone]) -> Int {
        func offset(_ zone: Zone) -> Double {
            abs(zone.x + zone.width / 2 - 0.5) + abs(zone.y + zone.height / 2 - 0.5)
        }
        return zones.indices.min { offset(zones[$0]) < offset(zones[$1]) } ?? 0
    }

    /// The zone a frame was placed in: the closest one, if its edges are within `tolerance` points in total.
    private static func zoneIndex(of frame: CGRect, in rects: [CGRect], tolerance: CGFloat) -> Int? {
        rects.indices
            .min { distance(frame, rects[$0]) < distance(frame, rects[$1]) }
            .flatMap { distance(frame, rects[$0]) <= tolerance ? $0 : nil }
    }

    /// The zone a frame mostly coincides with (intersection over union of at least `minimumOverlap`).
    /// Looser than the tolerance match, because neighbours may sit in a layout that has since been reset.
    private static func zoneIndex(of frame: CGRect, in rects: [CGRect], minimumOverlap: CGFloat) -> Int? {
        let scored = rects.indices.map { ($0, intersectionOverUnion(frame, rects[$0])) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= minimumOverlap else { return nil }
        return best.0
    }

    private static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let shared = overlap(a, b)
        let union = a.width * a.height + b.width * b.height - shared
        return union > 0 ? shared / union : 0
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }
}
