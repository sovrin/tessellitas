//
//  ProfileGlyph.swift
//  tessellitas
//

import SwiftUI

/// A profile drawn as a tiny tessellation, like the app icon: used wherever a profile needs an icon.
struct ProfileGlyph: View {
    let profile: Profile

    private var aspect: Double { (profile.minAspectRatio ?? 0) >= 2 ? 21.0 / 9 : 16.0 / 10 }

    var body: some View {
        Canvas { context, size in
            for zone in profile.zones {
                let rect = CGRect(x: zone.x * size.width, y: zone.y * size.height,
                                  width: zone.width * size.width, height: zone.height * size.height)
                    .insetBy(dx: 0.75, dy: 0.75)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .foreground)
            }
        }
        .frame(width: 20, height: 20 / aspect)
        .accessibilityHidden(true)
    }
}

#Preview("Profile glyphs") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(Config.default.profiles) { profile in
            Label { Text(profile.name) } icon: { ProfileGlyph(profile: profile) }
        }
    }
    .padding(24)
}
