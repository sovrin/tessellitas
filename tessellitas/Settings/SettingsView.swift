//
//  SettingsView.swift
//  tessellitas
//

import SwiftUI

private enum SettingsPage: Hashable {
    case general
    case displays
    case profile(UUID)
}

struct SettingsView: View {
    let model: AppModel
    @State private var page: SettingsPage? = .general

    var body: some View {
        let store = model.store
        let profiles = store.config.profiles

        NavigationSplitView {
            List(selection: $page) {
                Label("General", systemImage: "gearshape").tag(SettingsPage.general)
                Label("Displays", systemImage: "display").tag(SettingsPage.displays)

                Section("Profiles") {
                    ForEach(profiles) { profile in
                        Label { Text(profile.name) } icon: { ProfileGlyph(profile: profile) }
                            .tag(SettingsPage.profile(profile.id))
                            .contextMenu {
                                Button("Delete Profile", role: .destructive) { remove(profile.id) }
                                    .disabled(profiles.count <= 1)
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button { page = .profile(store.addProfile()) } label: {
                    Label("New Profile", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        } detail: {
            detail(store: store)
        }
        .frame(minWidth: 820, minHeight: 580)
        .onChange(of: profiles.map(\.id)) { _, ids in
            // A reload or delete can invalidate the selected profile.
            if case .profile(let id) = page, !ids.contains(id) { page = .general }
        }
        // A menu-bar-only app can't take keyboard focus properly; become a regular app while this window is open.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @ViewBuilder
    private func detail(store: ConfigStore) -> some View {
        switch page ?? .general {
        case .general:
            GeneralSettings(model: model)
        case .displays:
            DisplaysSettings(store: store)
        case .profile(let id):
            if let binding = store.profileBinding(id) {
                ProfileEditor(
                    profile: binding,
                    nameIsTaken: store.config.profiles.contains { $0.name == binding.wrappedValue.name && $0.id != id },
                    canDelete: store.config.profiles.count > 1,
                    onDelete: { remove(id) }
                )
                .id(id)
            } else {
                GeneralSettings(model: model)
            }
        }
    }

    private func remove(_ id: UUID) {
        if page == .profile(id) { page = .general }
        model.store.removeProfile(id)
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView(model: PreviewSupport.model())
}
#endif
