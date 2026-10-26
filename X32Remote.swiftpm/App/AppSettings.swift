import Foundation

enum AppMode: String, Codable, CaseIterable, Identifiable {
    case mixer
    case monitor
    case simple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixer: return "Mixer"
        case .monitor: return "Monitor mix"
        case .simple: return "Simple controls"
        }
    }

    var subtitle: String {
        switch self {
        case .mixer: return "Full console: faders, EQ, dynamics, sends"
        case .monitor: return "One performer's mix, big faders"
        case .simple: return "A few big controls for staff"
        }
    }

    var symbol: String {
        switch self {
        case .mixer: return "slider.vertical.3"
        case .monitor: return "headphones"
        case .simple: return "dial.medium"
        }
    }
}

/// One big control on the Simple screen.
struct SimpleControl: Codable, Identifiable, Hashable {
    var id: UUID
    var strip: StripID
    var label: String
    /// Highest level staff can push this to, in dB (10 = no limit).
    var maxDB: Float

    init(id: UUID = UUID(), strip: StripID, label: String, maxDB: Float = 0) {
        self.id = id
        self.strip = strip
        self.label = label
        self.maxDB = maxDB
    }
}

/// Everything the app remembers between launches.
struct AppSettings: Codable, Equatable {
    var lastHost: String = ""
    var recentHosts: [String] = []
    var mode: AppMode = .mixer
    var pin: String = ""
    var locked: Bool = false
    var monitorBus: Int = 1
    var monitorShowAll: Bool = false
    var monitorHidden: [String] = []
    var simpleTitle: String = "Sound"
    var simpleControls: [SimpleControl] = AppSettings.defaultSimpleControls
    var hapticAtUnity: Bool = true
    var keepAwake: Bool = true
    var showFaderScale: Bool = true
    var autoConnect: Bool = true
    /// The two custom layers: strip ids ("channel-5") and names.
    var userLayers: [[String]] = [[], []]
    var userLayerNames: [String] = ["User 1", "User 2"]
    /// Opening a channel in the app also selects it on the desk's own screen.
    var selectOnDesk: Bool = false
    /// Show the desk's analyser behind the EQ curve (points the desk's RTA at the open channel).
    var showRTA: Bool = false

    static let defaultSimpleControls: [SimpleControl] = [
        SimpleControl(strip: StripID(.auxIn, 1), label: "Music", maxDB: 0),
        SimpleControl(strip: StripID(.channel, 22), label: "Microphone", maxDB: 0),
        SimpleControl(strip: StripID.mainLR, label: "Main volume", maxDB: 0)
    ]

    init() {}

    enum CodingKeys: String, CodingKey {
        case lastHost, recentHosts, mode, pin, locked, monitorBus, monitorShowAll, monitorHidden
        case simpleTitle, simpleControls, hapticAtUnity, keepAwake, showFaderScale, autoConnect
        case userLayers, userLayerNames, selectOnDesk, showRTA
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastHost = try c.decodeIfPresent(String.self, forKey: .lastHost) ?? ""
        recentHosts = try c.decodeIfPresent([String].self, forKey: .recentHosts) ?? []
        mode = try c.decodeIfPresent(AppMode.self, forKey: .mode) ?? .mixer
        pin = try c.decodeIfPresent(String.self, forKey: .pin) ?? ""
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        monitorBus = min(max(try c.decodeIfPresent(Int.self, forKey: .monitorBus) ?? 1, 1), 16)
        monitorShowAll = try c.decodeIfPresent(Bool.self, forKey: .monitorShowAll) ?? false
        monitorHidden = try c.decodeIfPresent([String].self, forKey: .monitorHidden) ?? []
        simpleTitle = try c.decodeIfPresent(String.self, forKey: .simpleTitle) ?? "Sound"
        simpleControls = try c.decodeIfPresent([SimpleControl].self, forKey: .simpleControls) ?? AppSettings.defaultSimpleControls
        hapticAtUnity = try c.decodeIfPresent(Bool.self, forKey: .hapticAtUnity) ?? true
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        showFaderScale = try c.decodeIfPresent(Bool.self, forKey: .showFaderScale) ?? true
        autoConnect = try c.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? true
        var layers = try c.decodeIfPresent([[String]].self, forKey: .userLayers) ?? []
        while layers.count < 2 { layers.append([]) }
        userLayers = layers
        var names = try c.decodeIfPresent([String].self, forKey: .userLayerNames) ?? []
        while names.count < 2 { names.append("User \(names.count + 1)") }
        userLayerNames = names
        selectOnDesk = try c.decodeIfPresent(Bool.self, forKey: .selectOnDesk) ?? false
        showRTA = try c.decodeIfPresent(Bool.self, forKey: .showRTA) ?? false
    }

    private static let key = "X32Remote.settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppSettings.key)
        }
    }
}
