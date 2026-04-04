import Foundation

public final class PluginSettingsStorage: @unchecked Sendable {
    private let pluginId: String
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(pluginId: String, defaults: UserDefaults = .standard) {
        self.pluginId = pluginId
        self.defaults = defaults
    }

    private func key(for optionKey: String) -> String {
        "com.TablePro.plugin.\(pluginId).\(optionKey)"
    }

    public func save<T: Encodable>(_ value: T, forKey optionKey: String = "settings") {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key(for: optionKey))
    }

    public func load<T: Decodable>(_ type: T.Type, forKey optionKey: String = "settings") -> T? {
        guard let data = defaults.data(forKey: key(for: optionKey)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    public func removeAll() {
        let prefix = "com.TablePro.plugin.\(pluginId)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
