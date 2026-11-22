//
//  MenuContent.swift
//  tessellitas
//

import Paritas
import SwiftUI

/// Menu bar panel, built from the shared Paritas components.
struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var displays = Display.all()

    var body: some View {
        let store = model.store
        let modifiers = store.config.hotkeyModifiers.map(\.symbol)

        MenuPanel {
            // Blue like the middle zone of the app icon.
            PanelHeader("tessellitas", status: status(modifiers), icon: Image(nsImage: MenuBarGlyph.image),
                        colors: [Color(red: 0.30, green: 0.62, blue: 1.0), Color(red: 0.12, green: 0.43, blue: 0.95)])
            if !model.isTrusted {
                WarningCard("Allow Accessibility access", message: "tessellitas needs it to move other apps’ windows.") {
                    Button("Allow…", action: model.requestAccess)
                }
            }
            PanelDivider()
            PanelSection("Displays") {
                ForEach(displays) { display in
                    DisplayRow(display: display, store: store)
                        .padding(.horizontal, PanelMetrics.rowInset)
                }
            }
            PanelDivider()
            PanelSection("Shortcuts") {
                VStack(alignment: .leading, spacing: 6) {
                    hint("Preview a zone", keys: modifiers + ["1–9"])
                    hint("Step through zones", keys: modifiers + ["←", "→"])
                    hint("Grow or shrink", keys: modifiers + ["↑", "↓"])
                    hint("Fill the screen", keys: modifiers + ["↩"])
                }
                .padding(.horizontal, PanelMetrics.inset)
            }
            PanelDivider()
            PanelFooter(appName: "tessellitas", showsLaunchAtLogin: false) { openWindow(id: "settings") }
        }
        .onAppear { displays = Display.all() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = Display.all()
        }
    }

    private func status(_ modifiers: [String]) -> String {
        if !model.isTrusted { return "Not tiling · needs Accessibility" }
        let count = displays.count
        return "\(count) \(count == 1 ? "display" : "displays") · \(modifiers.joined()) + zone key"
    }

    private func hint(_ title: String, keys: [String]) -> some View {
        HStack {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Spacer()
            KeyCombo(keys: keys)
        }
    }
}

/// One monitor: a thumbnail of the layout it tiles with, and the profile picker.
private struct DisplayRow: View {
    let display: Display
    let store: ConfigStore

    var body: some View {
        let active = store.config.profile(for: display)
        let isPinned = store.config.displayProfiles[display.id] != nil

        HStack(spacing: 9) {
            ZoneCanvas(zones: .constant(active?.zones ?? []), selection: .constant(nil),
                       aspect: display.aspectRatio, style: .thumbnail)
                .frame(width: 64)
                .frame(minHeight: 28)

            VStack(alignment: .leading, spacing: 0) {
                Text(display.name).lineLimit(1)
                Menu {
                    Picker("Profile", selection: pinned) {
                        Text("Automatic").tag(String?.none)
                        Divider()
                        ForEach(store.config.profiles) { profile in
                            Text(profile.name).tag(String?.some(profile.name))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(active.map { isPinned ? $0.name : "\($0.name) · Auto" } ?? "No profile")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        // Lined up with Paritas rows, but not a HoverRow: the row itself does nothing when clicked.
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
    }

    private var pinned: Binding<String?> {
        Binding(
            get: { store.config.displayProfiles[display.id] },
            set: { store.pin($0, to: display) }
        )
    }
}

#if DEBUG
#Preview("Menu") {
    MenuContent(model: PreviewSupport.model())
        .background(.regularMaterial)
}
#endif
