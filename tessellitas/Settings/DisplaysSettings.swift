//
//  DisplaysSettings.swift
//  tessellitas
//

import SwiftUI

struct DisplaysSettings: View {
    let store: ConfigStore
    @State private var displays = Display.all()

    var body: some View {
        Form {
            Section {
                ForEach(displays) { display in
                    let active = store.config.profile(for: display)
                    HStack(alignment: .center, spacing: 16) {
                        ZoneCanvas(zones: .constant(active?.zones ?? []), selection: .constant(nil),
                                   aspect: display.aspectRatio, style: .thumbnail)
                            .frame(width: 132)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(display.name).font(.headline)
                            Text("\(Int(display.frame.width)) × \(Int(display.frame.height)) pt · \(display.aspectRatio.formatted(.number.precision(.fractionLength(2)))):1")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Profile", selection: pinned(display)) {
                            Text("Automatic · \(store.config.automaticProfile(for: display)?.name ?? "none")")
                                .tag(String?.none)
                            Divider()
                            ForEach(store.config.profiles) { profile in
                                Text(profile.name).tag(String?.some(profile.name))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                    }
                    .padding(.vertical, 6)
                }
            } footer: {
                Text("Automatic picks a profile by the display’s shape, using each profile’s aspect-ratio rule. Choose a profile to pin it to that monitor.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Displays")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = Display.all()
        }
    }

    private func pinned(_ display: Display) -> Binding<String?> {
        Binding(
            get: { store.config.displayProfiles[display.id] },
            set: { store.pin($0, to: display) }
        )
    }
}

#if DEBUG
#Preview("Displays") {
    DisplaysSettings(store: PreviewSupport.model().store)
        .frame(width: 620, height: 420)
}
#endif
