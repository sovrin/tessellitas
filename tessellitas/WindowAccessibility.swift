//
//  WindowAccessibility.swift
//  tessellitas
//

import AppKit
import ApplicationServices

enum WindowAccessibility {
    static func requestAccess() {
        // The literal is kAXTrustedCheckOptionPrompt; the constant isn't concurrency-safe to reference.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                let window = value as! AXUIElement
                // A hung app must not freeze our main thread (and with it, every hotkey).
                AXUIElementSetMessagingTimeout(window, 0.25)
                return window
            }
        }
        return nil
    }
}

extension WindowAccessibility {
    /// Every ordinary, visible window of other apps on the current Space, except `excluded`.
    /// Minimised windows, panels and dialogs are skipped: only real windows get tiled.
    static func otherWindows(excluding excluded: AXUIElement) -> [(window: AXUIElement, frame: CGRect)] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var found: [(window: AXUIElement, frame: CGRect)] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != ownPID {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.15)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement]
            else { continue }
            for window in windows where !CFEqual(window, excluded) {
                guard window.isStandardWindow, !window.isMinimized, let frame = window.frame else { continue }
                AXUIElementSetMessagingTimeout(window, 0.15)
                found.append((window, frame))
            }
        }
        return found
    }
}

nonisolated extension AXUIElement {
    var isStandardWindow: Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXSubroleAttribute as CFString, &value) == .success else { return false }
        return (value as? String) == (kAXStandardWindowSubrole as String)
    }

    var isMinimized: Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXMinimizedAttribute as CFString, &value) == .success else { return false }
        return (value as? Bool) == true
    }

    /// Position and size in Accessibility coordinates (origin top-left of the primary display).
    var frame: CGRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard let p = axValue(kAXPositionAttribute), AXValueGetValue(p, .cgPoint, &position),
              let s = axValue(kAXSizeAttribute), AXValueGetValue(s, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Size, position, size again: moving across displays can clamp the first resize to the
    /// old display's bounds, and some apps adjust size after a move.
    func setFrame(_ rect: CGRect) {
        setSize(rect.size)
        setPosition(rect.origin)
        setSize(rect.size)
    }

    /// One pass, for animation frames: only touches what changed, in the order that keeps the
    /// in-between state closest to the frames either side of it (no flash outside the union of the two).
    func setFrameQuickly(from current: CGRect, to next: CGRect) {
        let sizeChanged = current.size != next.size
        let positionChanged = current.origin != next.origin
        switch (sizeChanged, positionChanged) {
        case (false, false):
            return
        case (true, false):
            setSize(next.size)
        case (false, true):
            setPosition(next.origin)
        case (true, true):
            let union = current.union(next)
            func excess(_ rect: CGRect) -> CGFloat {
                let outer = rect.union(union)
                return outer.width * outer.height - union.width * union.height
            }
            let positionFirst = excess(CGRect(origin: next.origin, size: current.size))
                < excess(CGRect(origin: current.origin, size: next.size))
            if positionFirst {
                setPosition(next.origin)
                setSize(next.size)
            } else {
                setSize(next.size)
                setPosition(next.origin)
            }
        }
    }

    private func axValue(_ name: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return (value as! AXValue)
    }

    private func setPosition(_ point: CGPoint) {
        var point = point
        if let value = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, value)
        }
    }

    private func setSize(_ size: CGSize) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, value)
        }
    }
}
