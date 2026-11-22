//
//  KeyCap.swift
//  tessellitas
//

import SwiftUI

/// A small keyboard key, for showing shortcuts.
struct KeyCap: View {
    let label: String

    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.background.secondary)
                    .shadow(color: .black.opacity(0.14), radius: 0, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.separator))
    }
}

/// A row of keys, e.g. ⌃ ⌥ 1–9.
struct KeyCombo: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { KeyCap($1) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

/// A large, toggleable modifier key (⌃ control, ⌥ option, …) that lights up in the accent colour.
struct ModifierKeyToggle: View {
    let key: ModifierKey
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: 1) {
                Text(key.symbol).font(.system(size: 19, weight: .regular))
                Text(key.title.lowercased()).font(.system(size: 10, weight: .medium))
            }
            .frame(width: 64, height: 48)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.background.secondary))
                    .shadow(color: .black.opacity(isOn ? 0 : 0.14), radius: 0, y: 1.5)
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isOn ? AnyShapeStyle(.clear) : AnyShapeStyle(.separator)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview("Keys") {
    @Previewable @State var control = true
    @Previewable @State var shift = false
    VStack(alignment: .leading, spacing: 16) {
        KeyCombo(keys: ["⌃", "⌥", "1–9"])
        KeyCombo(keys: ["⌃", "⌥", "←", "→"])
        HStack {
            ModifierKeyToggle(key: .control, isOn: $control)
            ModifierKeyToggle(key: .shift, isOn: $shift)
        }
    }
    .padding(24)
}
