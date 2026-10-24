import Foundation

extension OSCArg: Codable {
    private enum CodingKeys: String, CodingKey { case i, f, s, b }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(Int32.self, forKey: .i) {
            self = .int(v)
        } else if let v = try c.decodeIfPresent(Float.self, forKey: .f) {
            self = .float(v)
        } else if let v = try c.decodeIfPresent(String.self, forKey: .s) {
            self = .string(v)
        } else if let v = try c.decodeIfPresent(Data.self, forKey: .b) {
            self = .blob(v)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown OSC value"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .int(let v): try c.encode(v, forKey: .i)
        case .float(let v): try c.encode(v, forKey: .f)
        case .string(let v): try c.encode(v, forKey: .s)
        case .blob(let v): try c.encode(v, forKey: .b)
        }
    }
}

extension ProcessingSection: Codable {}

/// A channel's processing saved on this device under a name, to load onto any channel later.
struct ChannelPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var created = Date()
    var clip: ChannelClipboard

    /// What a preset keeps: everything but the sends (which belong to one show's mixes).
    static let sections: [ProcessingSection] = [.preamp, .gate, .eq, .comp]

    var summary: String {
        clip.sections.map(\.title).joined(separator: ", ")
    }

    /// The preset limited to some of its sections.
    func clipboard(only sections: [ProcessingSection]?) -> ChannelClipboard {
        guard let sections else { return clip }
        return ChannelClipboard(source: clip.source, sections: clip.sections.filter { sections.contains($0) }, values: clip.values)
    }
}

/// Presets live in the app's own storage (they're not on the desk).
enum PresetLibrary {
    static let key = "X32Remote.presets.v1"

    static func load(from defaults: UserDefaults = .standard) -> [ChannelPreset] {
        guard let data = defaults.data(forKey: key) else { return [] }
        // Decode each preset on its own, so one unreadable preset doesn't lose the rest.
        guard let items = try? JSONDecoder().decode([Lenient].self, from: data) else {
            // Keep the unreadable store rather than letting the next save overwrite it.
            keepBackup(data, defaults)
            return []
        }
        let presets = items.compactMap(\.preset)
        if presets.count < items.count {
            keepBackup(data, defaults)
        }
        return presets
    }

    /// The first unreadable store is kept; later failures never overwrite it.
    private static func keepBackup(_ data: Data, _ defaults: UserDefaults) {
        if defaults.data(forKey: key + ".backup") == nil {
            defaults.set(data, forKey: key + ".backup")
        }
    }

    private struct Lenient: Decodable {
        let preset: ChannelPreset?

        init(from decoder: Decoder) throws {
            preset = try? ChannelPreset(from: decoder)
        }
    }

    static func save(_ presets: [ChannelPreset], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: key)
        }
    }

    /// Presets sorted by name, case-insensitively.
    static func sorted(_ presets: [ChannelPreset]) -> [ChannelPreset] {
        presets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
