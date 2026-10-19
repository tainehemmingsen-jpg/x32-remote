import Foundation

/// The kinds of fader strips on an X32.
enum StripKind: String, Codable, CaseIterable, Hashable {
    case channel, auxIn, fxReturn, bus, matrix, main, mono, dca

    var count: Int {
        switch self {
        case .channel: return 32
        case .auxIn: return 8
        case .fxReturn: return 8
        case .bus: return 16
        case .matrix: return 6
        case .main, .mono: return 1
        case .dca: return 8
        }
    }

    var title: String {
        switch self {
        case .channel: return "Channel"
        case .auxIn: return "Aux In"
        case .fxReturn: return "FX Return"
        case .bus: return "Mix Bus"
        case .matrix: return "Matrix"
        case .main: return "Main LR"
        case .mono: return "Mono / Center"
        case .dca: return "DCA"
        }
    }
}

/// Identifies one strip (channel, bus, DCA…). Indices are 1-based like on the desk.
struct StripID: Hashable, Codable, Identifiable {
    var kind: StripKind
    var index: Int

    init(_ kind: StripKind, _ index: Int = 1) {
        self.kind = kind
        self.index = index
    }

    var id: String { "\(kind.rawValue)-\(index)" }

    static func channel(_ n: Int) -> StripID { StripID(.channel, n) }
    static func bus(_ n: Int) -> StripID { StripID(.bus, n) }
    static let mainLR = StripID(.main, 1)
    static let monoC = StripID(.mono, 1)

    static func all(_ kind: StripKind) -> [StripID] {
        (1...kind.count).map { StripID(kind, $0) }
    }

    /// Every strip with a fader, in desk order.
    static var everything: [StripID] {
        StripKind.allCases.flatMap { all($0) }
    }

    /// Strips that can send to mix buses.
    static var busSources: [StripID] {
        all(.channel) + all(.auxIn) + all(.fxReturn)
    }

    // MARK: Addresses

    var base: String {
        switch kind {
        case .channel: return String(format: "/ch/%02d", index)
        case .auxIn: return String(format: "/auxin/%02d", index)
        case .fxReturn: return String(format: "/fxrtn/%02d", index)
        case .bus: return String(format: "/bus/%02d", index)
        case .matrix: return String(format: "/mtx/%02d", index)
        case .main: return "/main/st"
        case .mono: return "/main/m"
        case .dca: return "/dca/\(index)"
        }
    }

    var faderPath: String { kind == .dca ? base + "/fader" : base + "/mix/fader" }
    var onPath: String { kind == .dca ? base + "/on" : base + "/mix/on" }
    var namePath: String { base + "/config/name" }
    var colorPath: String { base + "/config/color" }

    var panPath: String? {
        switch kind {
        case .channel, .auxIn, .fxReturn, .bus, .main: return base + "/mix/pan"
        default: return nil
        }
    }

    /// Assign to main stereo bus.
    var lrAssignPath: String? {
        switch kind {
        case .channel, .auxIn, .fxReturn, .bus: return base + "/mix/st"
        default: return nil
        }
    }

    var monoAssignPath: String? {
        switch kind {
        case .channel, .auxIn, .fxReturn, .bus: return base + "/mix/mono"
        default: return nil
        }
    }

    var monoLevelPath: String? {
        switch kind {
        case .channel, .auxIn, .fxReturn, .bus: return base + "/mix/mlevel"
        default: return nil
        }
    }

    var dcaGroupsPath: String? { kind == .dca ? nil : base + "/grp/dca" }
    var muteGroupsPath: String? { kind == .dca ? nil : base + "/grp/mute" }

    /// Number of sends this strip has, and what they feed.
    var sendCount: Int {
        switch kind {
        case .channel, .auxIn, .fxReturn: return 16
        case .bus, .main, .mono: return 6
        default: return 0
        }
    }

    var sendsFeedMatrix: Bool { kind == .bus || kind == .main || kind == .mono }

    func sendLevelPath(_ n: Int) -> String { base + String(format: "/mix/%02d/level", n) }
    func sendOnPath(_ n: Int) -> String { base + String(format: "/mix/%02d/on", n) }
    /// Pan and tap point exist on odd-numbered sends only (they cover the pair).
    func sendPanPath(_ n: Int) -> String { base + String(format: "/mix/%02d/pan", n % 2 == 1 ? n : n - 1) }
    func sendTypePath(_ n: Int) -> String { base + String(format: "/mix/%02d/type", n % 2 == 1 ? n : n - 1) }

    var eqBandCount: Int {
        switch kind {
        case .channel, .auxIn, .fxReturn: return 4
        case .bus, .matrix, .main, .mono: return 6
        case .dca: return 0
        }
    }

    var hasEQ: Bool { eqBandCount > 0 }
    var hasGate: Bool { kind == .channel }
    var hasDynamics: Bool { kind == .channel || kind == .bus || kind == .matrix || kind == .main || kind == .mono }
    var hasTrim: Bool { kind == .channel || kind == .auxIn }
    var hasPolarity: Bool { kind == .channel || kind == .auxIn || kind == .matrix }
    var hasHighPass: Bool { kind == .channel }
    var hasInputPage: Bool { kind == .channel || kind == .auxIn }
    var hasSendsPage: Bool { sendCount > 0 }
    var hasSetup: Bool { true }

    var eqOnPath: String { base + "/eq/on" }
    func eqPath(_ band: Int, _ field: String) -> String { base + "/eq/\(band)/\(field)" }
    func gatePath(_ field: String) -> String { base + "/gate/\(field)" }
    func dynPath(_ field: String) -> String { base + "/dyn/\(field)" }
    func preampPath(_ field: String) -> String { base + "/preamp/\(field)" }
    var sourcePath: String { base + "/config/source" }

    /// /-ha/NN/index tells which headamp feeds channels 1-32 (00-31) and aux 1-8 (32-39).
    var headampIndexPath: String? {
        switch kind {
        case .channel: return String(format: "/-ha/%02d/index", index - 1)
        case .auxIn: return String(format: "/-ha/%02d/index", 32 + index - 1)
        default: return nil
        }
    }

    static func headampGainPath(_ ha: Int) -> String { String(format: "/headamp/%03d/gain", ha) }
    static func headampPhantomPath(_ ha: Int) -> String { String(format: "/headamp/%03d/phantom", ha) }

    /// Index used by /-stat/solosw/NN (01-80).
    var soloIndex: Int {
        switch kind {
        case .channel: return index
        case .auxIn: return 32 + index
        case .fxReturn: return 40 + index
        case .bus: return 48 + index
        case .matrix: return 64 + index
        case .main: return 71
        case .mono: return 72
        case .dca: return 72 + index
        }
    }

    var soloPath: String { String(format: "/-stat/solosw/%02d", soloIndex) }

    // MARK: Labels

    /// Short label like "Ch 05", "Bus 3", "LR".
    var shortLabel: String {
        switch kind {
        case .channel: return String(format: "Ch %02d", index)
        case .auxIn: return index <= 6 ? "Aux \(index)" : (index == 7 ? "USB L" : "USB R")
        case .fxReturn: return "FX \((index - 1) / 2 + 1)\(index % 2 == 1 ? "L" : "R")"
        case .bus: return "Bus \(index)"
        case .matrix: return "Mtx \(index)"
        case .main: return "LR"
        case .mono: return "M/C"
        case .dca: return "DCA \(index)"
        }
    }

    /// Tiny number shown on scribble strips.
    var numberLabel: String {
        switch kind {
        case .channel: return String(format: "%02d", index)
        case .auxIn: return "A\(index)"
        case .fxReturn: return "F\(index)"
        case .bus: return "B\(index)"
        case .matrix: return "M\(index)"
        case .main: return "LR"
        case .mono: return "MC"
        case .dca: return "D\(index)"
        }
    }

    /// Default name the desk shows when the scribble strip is blank.
    var defaultName: String { shortLabel }

    // MARK: Meters

    /// Position in /meters/0 (32 ch, 8 aux, 8 fx returns, 16 bus, 6 matrix).
    var meters0Index: Int? {
        switch kind {
        case .channel: return index - 1
        case .auxIn: return 31 + index
        case .fxReturn: return 39 + index
        case .bus: return 47 + index
        case .matrix: return 63 + index
        default: return nil
        }
    }

    /// Fader quantisation for this strip.
    var faderSteps: Int { 1023 }
}

/// Banks of strips shown on the mixer screen.
enum MixerLayer: String, CaseIterable, Identifiable, Codable {
    case inputs1, inputs2, auxFx, buses, matrix, dca

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inputs1: return "1–16"
        case .inputs2: return "17–32"
        case .auxFx: return "Aux · FX"
        case .buses: return "Buses"
        case .matrix: return "Mtx · Main"
        case .dca: return "DCA"
        }
    }

    var strips: [StripID] {
        switch self {
        case .inputs1: return (1...16).map { StripID(.channel, $0) }
        case .inputs2: return (17...32).map { StripID(.channel, $0) }
        case .auxFx: return StripID.all(.auxIn) + StripID.all(.fxReturn)
        case .buses: return StripID.all(.bus)
        case .matrix: return StripID.all(.matrix) + [StripID.monoC]
        case .dca: return StripID.all(.dca)
        }
    }

    /// Whether this layer's strips can show sends-on-fader for a mix bus.
    var supportsBusSends: Bool {
        switch self {
        case .inputs1, .inputs2, .auxFx: return true
        default: return false
        }
    }
}
