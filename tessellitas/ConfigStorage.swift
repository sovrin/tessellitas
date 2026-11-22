//
//  ConfigStorage.swift
//  tessellitas
//

import Foundation

/// Where the configuration is kept: one encoded blob, so a save is all-or-nothing.
protocol ConfigStorage {
    func read() -> Data?
    func write(_ data: Data)
}

/// The app's real storage: the standard preferences (~/Library/Preferences/<bundle id>.plist).
struct UserDefaultsStorage: ConfigStorage {
    private static let key = "configuration"

    func read() -> Data? { UserDefaults.standard.data(forKey: Self.key) }
    func write(_ data: Data) { UserDefaults.standard.set(data, forKey: Self.key) }
}
