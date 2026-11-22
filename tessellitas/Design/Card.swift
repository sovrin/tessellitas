//
//  Card.swift
//  tessellitas
//

import SwiftUI

/// A grouped surface in the style of System Settings, with an optional title above and note below.
struct Card<Content: View>: View {
    var title: String?
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background.secondary))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.7)))

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Card") {
    Card(title: "Profile", note: "A note beneath the card.") {
        LabeledContent("Name", value: "Ultrawide 1-3-1")
        Divider()
        Toggle("Use automatically on wide displays", isOn: .constant(true))
    }
    .padding(24)
    .frame(width: 420)
}
