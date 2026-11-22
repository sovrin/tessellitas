//
//  MenuBarGlyph.swift
//  tessellitas
//

import AppKit
import SwiftUI

/// The app icon reduced to a template image: a display split 1 : 3 : 1, middle zone solid.
enum MenuBarGlyph {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 13), flipped: false) { rect in
            let gap: CGFloat = 1.5
            let unit = (rect.width - 2 * gap) / 5
            var x = rect.minX
            for (index, width) in [unit, unit * 3, unit].enumerated() {
                let tile = NSRect(x: x, y: rect.minY, width: width, height: rect.height)
                NSColor.black.withAlphaComponent(index == 1 ? 1 : 0.5).setFill()
                NSBezierPath(roundedRect: tile, xRadius: min(2.6, width / 2), yRadius: 2.6).fill()
                x += width + gap
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "tessellitas"
        return image
    }()
}

#Preview("Menu bar glyph") {
    HStack(spacing: 24) {
        Image(nsImage: MenuBarGlyph.image)
        Image(nsImage: MenuBarGlyph.image).scaleEffect(4).frame(width: 90, height: 60)
    }
    .padding(24)
}
