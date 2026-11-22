//
//  HotKeyCenter.swift
//  tessellitas
//

import Carbon.HIToolbox
import OSLog

/// Global hotkeys via Carbon's RegisterEventHotKey: needs no extra permissions and
/// swallows the key combo system-wide.
@MainActor
final class HotKeyCenter {
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private let log = Logger(subsystem: "com.sovrin.Tessellitas", category: "hotkeys")

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { center.handlers[hotKeyID.id]?() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )
        if status != noErr { log.error("InstallEventHandler failed: \(status)") }
    }

    /// `modifiers` uses Carbon flags (controlKey, optionKey, cmdKey, shiftKey).
    /// Returns nil if the combo is taken, e.g. by another app such as Rectangle.
    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> UInt32? {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         EventHotKeyID(signature: OSType(0x5453_4C54) /* 'TSLT' */, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            log.error("Could not register hotkey \(keyCode) (status \(status))")
            return nil
        }
        refs[id] = ref
        handlers[id] = handler
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }
}
