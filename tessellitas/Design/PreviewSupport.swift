//
//  PreviewSupport.swift
//  tessellitas
//

#if DEBUG
import Foundation

/// Keeps a preview's edits in memory, so clicking around never touches the real preferences.
final class MemoryStorage: ConfigStorage {
    private var data: Data?

    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
}

enum PreviewSupport {
    @MainActor
    static func model() -> AppModel {
        let model = AppModel(store: ConfigStore(storage: MemoryStorage()))
        model.store.load()
        return model
    }
}
#endif
