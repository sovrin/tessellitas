//
//  Config.swift
//  tessellitas
//

import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// A named set of zones. Zone N is bound to hotkey ⌃⌥N.
struct Profile: Codable, Identifiable, Hashable {
    var name: String
    /// Used for automatic assignment: the profile with the highest value that
    /// is <= the display's width/height ratio wins. Ignored if a display is pinned.
    var minAspectRatio: Double?
    var zones: [Zone]
    /// Runtime-only identity, so renaming a profile doesn't confuse the editor.
    var id = UUID()

    private enum CodingKeys: String, CodingKey { case name, minAspectRatio, zones }

    static func columns(_ name: String, weights: [Double], minAspectRatio: Double? = nil) -> Profile {
        Profile(name: name, minAspectRatio: minAspectRatio, zones: Zone.grid(columns: weights))
    }
}

enum ModifierKey: String, Codable, CaseIterable, Identifiable {
    case control, option, shift, command

    var id: String { rawValue }

    var carbonFlag: Int {
        switch self {
        case .control: controlKey
        case .option: optionKey
        case .shift: shiftKey
        case .command: cmdKey
        }
    }

    var appKitFlag: NSEvent.ModifierFlags {
        switch self {
        case .control: .control
        case .option: .option
        case .shift: .shift
        case .command: .command
        }
    }

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    var title: String { rawValue.capitalized }
}

struct Config: Codable {
    var profiles: [Profile]
    /// Display UUID -> profile name. Displays not listed here are matched by aspect ratio.
    var displayProfiles: [String: String] = [:]
    /// Seconds. 0 turns animation off.
    var animationDuration = 0.18
    /// Points between windows and between windows and the screen edge.
    var gap = 0.0
    /// How much one grow/shrink press moves, as a fraction of the display (0.05 = 5%).
    var resizeStep = 0.05
    var hotkeyModifiers: [ModifierKey] = [.control, .option]

    static let `default` = Config(profiles: [
        .columns("Ultrawide 1-3-1", weights: [1, 3, 1], minAspectRatio: 2.0),
        .columns("Halves", weights: [1, 1]),
    ])

    var carbonModifiers: Int { hotkeyModifiers.reduce(0) { $0 | $1.carbonFlag } }

    var requiredModifierFlags: NSEvent.ModifierFlags {
        hotkeyModifiers.reduce(into: []) { $0.insert($1.appKitFlag) }
    }

    var modifierSymbols: String { hotkeyModifiers.map(\.symbol).joined() }

    func profile(for display: Display) -> Profile? {
        if let name = displayProfiles[display.id], let pinned = profiles.first(where: { $0.name == name }) {
            return pinned
        }
        return automaticProfile(for: display)
    }

    func automaticProfile(for display: Display) -> Profile? {
        profiles
            .filter { ($0.minAspectRatio ?? 0) <= display.aspectRatio }
            .max { ($0.minAspectRatio ?? 0) < ($1.minAspectRatio ?? 0) }
            ?? profiles.first
    }
}

/// Lets config files written by earlier versions (which lack newer keys) keep loading.
extension Config {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Config(profiles: [])
        profiles = try container.decode([Profile].self, forKey: .profiles)
        displayProfiles = try container.decodeIfPresent([String: String].self, forKey: .displayProfiles) ?? defaults.displayProfiles
        animationDuration = try container.decodeIfPresent(Double.self, forKey: .animationDuration) ?? defaults.animationDuration
        gap = try container.decodeIfPresent(Double.self, forKey: .gap) ?? defaults.gap
        resizeStep = try container.decodeIfPresent(Double.self, forKey: .resizeStep) ?? defaults.resizeStep
        let modifiers = try container.decodeIfPresent([ModifierKey].self, forKey: .hotkeyModifiers) ?? defaults.hotkeyModifiers
        hotkeyModifiers = modifiers.isEmpty ? defaults.hotkeyModifiers : modifiers
    }
}

@MainActor
@Observable
final class ConfigStore {
    private(set) var config = Config.default

    /// Called after every load or edit.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let storage: ConfigStorage

    /// The app's store, backed by the standard preferences.
    convenience init() {
        self.init(storage: UserDefaultsStorage())
    }

    /// Storage is injectable so previews and tests never touch the real preferences.
    init(storage: ConfigStorage) {
        self.storage = storage
    }

    /// Reads the saved configuration. First launch, or after an unreadable save, starts from the defaults.
    func load() {
        if let data = storage.read() {
            config = (try? JSONDecoder().decode(Config.self, from: data)) ?? .default
        } else {
            config = .default
        }
        onChange?()
    }

    func resetToDefaults() {
        config = .default
        save()
        onChange?()
    }

    func update(_ change: (inout Config) -> Void) {
        change(&config)
        save()
        onChange?()
    }

    func binding<Value>(_ keyPath: WritableKeyPath<Config, Value>) -> Binding<Value> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    func pin(_ profileName: String?, to display: Display) {
        update { $0.displayProfiles[display.id] = profileName }
    }

    // MARK: Profiles

    func profileBinding(_ id: UUID) -> Binding<Profile>? {
        guard let current = config.profiles.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.config.profiles.first(where: { $0.id == id }) ?? current },
            set: { self.setProfile($0) }
        )
    }

    /// Display pins refer to profiles by name, so a rename carries them along.
    func setProfile(_ profile: Profile) {
        update { config in
            guard let index = config.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
            let oldName = config.profiles[index].name
            config.profiles[index] = profile
            if oldName != profile.name {
                for (display, name) in config.displayProfiles where name == oldName {
                    config.displayProfiles[display] = profile.name
                }
            }
        }
    }

    @discardableResult
    func addProfile() -> UUID {
        let names = Set(config.profiles.map(\.name))
        var name = "New Profile"
        var counter = 2
        while names.contains(name) {
            name = "New Profile \(counter)"
            counter += 1
        }
        let profile = Profile.columns(name, weights: [1, 1])
        update { $0.profiles.append(profile) }
        return profile.id
    }

    func removeProfile(_ id: UUID) {
        update { config in
            guard config.profiles.count > 1, let profile = config.profiles.first(where: { $0.id == id }) else { return }
            config.profiles.removeAll { $0.id == id }
            config.displayProfiles = config.displayProfiles.filter { $0.value != profile.name }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        storage.write(data)
    }
}
