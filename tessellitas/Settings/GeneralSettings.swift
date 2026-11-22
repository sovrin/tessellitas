//
//  GeneralSettings.swift
//  tessellitas
//

import OSLog
import Paritas
import SwiftUI

struct GeneralSettings: View {
    let model: AppModel
    private static let log = Logger(subsystem: "com.sovrin.Tessellitas", category: "login")
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmReset = false

    var body: some View {
        let store = model.store
        let config = store.config
        let modifiers = config.hotkeyModifiers.map(\.symbol)

        Form {
            Section {
                HStack(spacing: 8) {
                    ForEach(ModifierKey.allCases) { key in
                        ModifierKeyToggle(key: key, isOn: modifierBinding(key, store: store))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } header: {
                Text("Shortcut keys")
            } footer: {
                Text("Hold these together with a zone key. At least one is required.")
            }

            Section("How it works") {
                LabeledContent("Preview a zone") { KeyCombo(keys: modifiers + ["1–9"]) }
                LabeledContent("Step through zones") { KeyCombo(keys: modifiers + ["←", "→"]) }
                LabeledContent("Apply") {
                    HStack(spacing: 6) {
                        Text("Release").foregroundStyle(.secondary)
                        KeyCombo(keys: modifiers)
                    }
                }
                LabeledContent("Cancel") { KeyCap("esc") }
                LabeledContent("Grow or shrink the window") { KeyCombo(keys: modifiers + ["↑", "↓"]) }
                LabeledContent("Fill the screen") { KeyCombo(keys: modifiers + ["↩"]) }
            }

            Section("Motion and spacing") {
                LabeledContent("Animation") {
                    HStack {
                        Slider(value: store.binding(\.animationDuration), in: 0...0.5, step: 0.01)
                            .frame(width: 200)
                        Text(config.animationDuration == 0 ? "Off" : "\(Int((config.animationDuration * 1000).rounded())) ms")
                            .monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                LabeledContent("Grow and shrink step") {
                    HStack {
                        Slider(value: store.binding(\.resizeStep), in: 0.01...0.15, step: 0.01)
                            .frame(width: 200)
                        Text("\(Int((config.resizeStep * 100).rounded()))%")
                            .monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                LabeledContent("Gap between windows") {
                    HStack {
                        Slider(value: store.binding(\.gap), in: 0...40, step: 1)
                            .frame(width: 200)
                        Text("\(Int(config.gap)) pt")
                            .monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }

            Section("System") {
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: {
                        do { try LoginItem.setEnabled($0) } catch {
                            Self.log.error("Launch at login failed: \(error.localizedDescription)")
                        }
                        launchAtLogin = LoginItem.isEnabled
                    }
                ))
                LabeledContent("Accessibility access") {
                    if model.isTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") { model.requestAccess() }
                    }
                }
            }

            Section {
                Button("Reset Profiles and Settings…", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Everything is saved automatically.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .confirmationDialog("Reset all settings and profiles to defaults?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.resetToDefaults() }
        } message: {
            Text("Your custom profiles and display assignments will be lost.")
        }
    }

    private func modifierBinding(_ key: ModifierKey, store: ConfigStore) -> Binding<Bool> {
        Binding(
            get: { store.config.hotkeyModifiers.contains(key) },
            set: { enabled in
                store.update { config in
                    var chosen = Set(config.hotkeyModifiers)
                    if enabled { chosen.insert(key) } else if chosen.count > 1 { chosen.remove(key) }
                    config.hotkeyModifiers = ModifierKey.allCases.filter(chosen.contains)
                }
            }
        )
    }
}

#if DEBUG
#Preview("General") {
    GeneralSettings(model: PreviewSupport.model())
        .frame(width: 620, height: 760)
}
#endif
