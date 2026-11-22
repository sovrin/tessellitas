//
//  Display.swift
//  tessellitas
//

import AppKit

struct Display: Identifiable {
    /// Stable per-monitor UUID (survives reboots and port changes).
    let id: String
    let name: String
    /// Usable area (excludes menu bar and Dock), in AppKit coordinates (origin bottom-left).
    let visibleFrame: CGRect
    /// Full frame, in AppKit coordinates.
    let frame: CGRect

    var aspectRatio: Double { frame.width / frame.height }

    /// Usable area in Accessibility coordinates (origin top-left of the primary display, y down).
    var visibleFrameAX: CGRect { Display.flip(visibleFrame) }
    var frameAX: CGRect { Display.flip(frame) }

    static func all() -> [Display] {
        NSScreen.screens.compactMap { Display(screen: $0) }
    }

    private init?(screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        id = string
        name = screen.localizedName
        frame = screen.frame
        visibleFrame = screen.visibleFrame
    }

    /// AppKit and Accessibility disagree on the origin: both are anchored to the primary
    /// display, but AppKit's y grows upward and Accessibility's grows downward. The
    /// conversion is its own inverse, so this maps in both directions.
    static func flip(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
