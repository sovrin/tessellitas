//
//  AppModel.swift
//  tessellitas
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Observation

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel(store: ConfigStore())

    let store: ConfigStore
    private(set) var isTrusted = AXIsProcessTrusted()

    @ObservationIgnored private let hotKeys: HotKeyCenter
    @ObservationIgnored private let tiler: TileController
    @ObservationIgnored private var zoneHotKeys: [UInt32] = []
    @ObservationIgnored private var registeredModifiers: [ModifierKey] = []
    @ObservationIgnored private var trustTimer: Timer?

    /// Use `shared`; other instances exist for previews, with a store pointing somewhere harmless.
    init(store: ConfigStore) {
        self.store = store
        let hotKeys = HotKeyCenter()
        self.hotKeys = hotKeys
        tiler = TileController(hotKeys: hotKeys)
    }

    func start() {
        store.load()
        store.onChange = { [weak self] in self?.configDidChange() }
        registerZoneHotKeys()

        if !isTrusted {
            WindowAccessibility.requestAccess()
            pollForTrust()
        }
    }

    func tile(_ command: TileCommand) {
        tiler.handle(command, config: store.config)
        isTrusted = AXIsProcessTrusted()
    }

    func requestAccess() {
        WindowAccessibility.requestAccess()
        pollForTrust()
    }

    // MARK: - Hotkeys

    /// ⌃⌥1…9 (top row or keypad) select that zone; ⌃⌥← / ⌃⌥→ step through the zones of the current display;
    /// ⌃⌥↑ / ⌃⌥↓ grow or shrink the focused window's zone; ⌃⌥↩ fills the display's usable area.
    /// The modifiers are configurable.
    private func registerZoneHotKeys() {
        zoneHotKeys.forEach(hotKeys.unregister)
        let modifiers = store.config.carbonModifiers
        registeredModifiers = store.config.hotkeyModifiers

        let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                         kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        let keypadKeys = [kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5,
                          kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9]
        var bindings: [(Int, TileCommand)] = digitKeys.enumerated().map { ($1, .zone($0)) }
        bindings += keypadKeys.enumerated().map { ($1, .zone($0)) }
        bindings.append((kVK_RightArrow, .next))
        bindings.append((kVK_LeftArrow, .previous))
        bindings.append((kVK_UpArrow, .grow))
        bindings.append((kVK_DownArrow, .shrink))
        bindings.append((kVK_Return, .maximize))
        bindings.append((kVK_ANSI_KeypadEnter, .maximize))

        zoneHotKeys = bindings.compactMap { key, command in
            hotKeys.register(keyCode: key, modifiers: modifiers) { [weak self] in self?.tile(command) }
        }
    }

    private func configDidChange() {
        // Temporary sizes were derived from profiles that may just have been edited.
        tiler.resetLayouts()
        if store.config.hotkeyModifiers != registeredModifiers {
            tiler.cancel()
            registerZoneHotKeys()
        }
    }

    /// There's no notification for the Accessibility toggle, so poll until it flips.
    private func pollForTrust() {
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                if AXIsProcessTrusted() {
                    self.isTrusted = true
                    timer.invalidate()
                }
            }
        }
    }
}
