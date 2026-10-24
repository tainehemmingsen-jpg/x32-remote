import Foundation

/// Conversions between the X32's normalised 0...1 OSC floats and real-world units.
/// Ranges and step counts follow the unofficial X32 OSC protocol documentation.
enum X32Math {

    // MARK: Fader law (faders, sends, DCAs)
    // 0.0 = -inf, 0.0625 = -60 dB, 0.25 = -30 dB, 0.5 = -10 dB, 0.75 = 0 dB, 1.0 = +10 dB

    static func faderToDB(_ f: Float) -> Float {
        let v = min(max(f, 0), 1)
        if v <= 0 { return -Float.infinity }
        if v >= 0.5 { return v * 40 - 30 }
        if v >= 0.25 { return v * 80 - 50 }
        if v >= 0.0625 { return v * 160 - 70 }
        return v * 480 - 90
    }

    static func dbToFader(_ db: Float) -> Float {
        if db.isInfinite && db < 0 { return 0 }
        let d = min(max(db, -90), 10)
        let f: Float
        if d < -60 {
            f = (d + 90) / 480
        } else if d < -30 {
            f = (d + 70) / 160
        } else if d < -10 {
            f = (d + 50) / 80
        } else {
            f = (d + 30) / 40
        }
        return min(max(f, 0), 1)
    }

    static let unityFader: Float = 0.75

    static func quantize(_ f: Float, steps: Int) -> Float {
        guard steps > 0 else { return f }
        let s = Float(steps)
        return min(max((f * s).rounded() / s, 0), 1)
    }

    static func formatDB(_ db: Float, decimals: Int = 1) -> String {
        if db.isInfinite || db <= -89.9 { return "-∞" }
        var rounded = (db * 10).rounded() / 10
        if abs(rounded) < 0.05 { rounded = 0 }   // no "-0.0"
        let sign = rounded > 0 ? "+" : ""
        return sign + String(format: "%.\(decimals)f", rounded)
    }

    static func formatFader(_ f: Float) -> String {
        formatDB(faderToDB(f))
    }

    // MARK: Linear / logarithmic scales

    static func lin(_ f: Float, _ lo: Float, _ hi: Float) -> Float {
        lo + (hi - lo) * min(max(f, 0), 1)
    }

    static func linInverse(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        guard hi != lo else { return 0 }
        return min(max((v - lo) / (hi - lo), 0), 1)
    }

    static func log(_ f: Float, _ lo: Float, _ hi: Float) -> Float {
        lo * powf(hi / lo, min(max(f, 0), 1))
    }

    static func logInverse(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        guard v > 0, lo > 0, hi > 0, hi != lo else { return 0 }
        return min(max(logf(v / lo) / logf(hi / lo), 0), 1)
    }

    // MARK: Meters (linear amplitude, 1.0 = 0 dBFS)

    static func amplitudeToDB(_ a: Float) -> Float {
        if a <= 0.0000316 { return -90 }   // below -90 dB
        return 20 * log10f(a)
    }
}

/// Describes how a normalised X32 parameter maps to a displayed value.
struct ParamSpec {
    enum Scale {
        case linear(Float, Float)
        case logarithmic(Float, Float)
        case fader
    }

    let scale: Scale
    let steps: Int
    let unit: String
    let decimals: Int
    let defaultNorm: Float

    init(_ scale: Scale, steps: Int, unit: String = "", decimals: Int = 1, defaultNorm: Float = 0) {
        self.scale = scale
        self.steps = steps
        self.unit = unit
        self.decimals = decimals
        self.defaultNorm = defaultNorm
    }

    func value(_ norm: Float) -> Float {
        switch scale {
        case .linear(let lo, let hi): return X32Math.lin(norm, lo, hi)
        case .logarithmic(let lo, let hi): return X32Math.log(norm, lo, hi)
        case .fader: return X32Math.faderToDB(norm)
        }
    }

    func norm(_ value: Float) -> Float {
        switch scale {
        case .linear(let lo, let hi): return X32Math.linInverse(value, lo, hi)
        case .logarithmic(let lo, let hi): return X32Math.logInverse(value, lo, hi)
        case .fader: return X32Math.dbToFader(value)
        }
    }

    func quantize(_ norm: Float) -> Float {
        X32Math.quantize(norm, steps: steps)
    }

    func display(_ norm: Float) -> String {
        let v = value(norm)
        if case .fader = scale {
            return X32Math.formatDB(v) + (unit.isEmpty ? "" : " " + unit)
        }
        if unit == "Hz" {
            return ParamSpec.formatHz(v)
        }
        if unit == "ms" && v >= 1000 {
            return String(format: "%.2f s", v / 1000)
        }
        let text: String
        if decimals == 0 {
            text = String(format: "%.0f", v)
        } else {
            text = String(format: "%.\(decimals)f", v)
        }
        return unit.isEmpty ? text : text + " " + unit
    }

    /// Reads a value typed by the user ("-6", "-6 dB", "1.2k", "off", "-inf") and returns the
    /// normalised 0...1 value. Nil if it isn't a number or is outside the parameter's range,
    /// so a typo never sends something unexpected to the desk.
    func parse(_ text: String) -> Float? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        t = t.replacingOccurrences(of: ",", with: ".")
        t = t.replacingOccurrences(of: "−", with: "-")
        if case .fader = scale, ["off", "-inf", "inf", "-∞", "∞", "-oo"].contains(t) {
            return 0
        }
        var multiplier: Float = 1
        for suffix in ["db", "hz", "ms", "%", ":1"] where t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        if unit == "Hz" && t.hasSuffix("khz") {
            t = String(t.dropLast(3))
            multiplier = 1000
        } else if unit == "Hz" && t.hasSuffix("k") {
            t = String(t.dropLast())
            multiplier = 1000
        } else if t.hasSuffix("s") && unit == "ms" {
            t = String(t.dropLast())
            multiplier = 1000
        }
        if t.hasPrefix("+") { t.removeFirst() }
        guard let number = Float(t.trimmingCharacters(in: .whitespaces)), number.isFinite else { return nil }
        let value = number * multiplier
        let (lo, hi) = range
        // A little slack for rounding, e.g. "0.3" ms or "-90" on a fader.
        let slack = (hi - lo) * 0.0005
        guard value >= lo - slack, value <= hi + slack else { return nil }
        let clamped = min(max(value, lo), hi)
        let n: Float
        switch scale {
        case .linear(let a, let b):
            n = X32Math.linInverse(clamped, a, b)
        case .logarithmic(let a, let b):
            n = X32Math.logInverse(clamped, a, b)
        case .fader:
            n = X32Math.dbToFader(clamped)
        }
        return quantize(min(max(n, 0), 1))
    }

    /// Lowest and highest value in real units (faders: -90 to +10 dB).
    var range: (Float, Float) {
        switch scale {
        case .linear(let a, let b), .logarithmic(let a, let b):
            return (min(a, b), max(a, b))
        case .fader:
            return (-90, 10)
        }
    }

    static func formatHz(_ hz: Float) -> String {
        if hz >= 10000 { return String(format: "%.1fk", hz / 1000) }
        if hz >= 1000 { return String(format: "%.2fk", hz / 1000) }
        if hz >= 100 { return String(format: "%.0f", hz) }
        return String(format: "%.1f", hz)
    }
}

/// Parameter specs for the controls the app exposes.
enum Specs {
    static let fader = ParamSpec(.fader, steps: 1023, unit: "dB", defaultNorm: 0.75)
    static let send = ParamSpec(.fader, steps: 160, unit: "dB", defaultNorm: 0.75)
    static let pan = ParamSpec(.linear(-100, 100), steps: 100, decimals: 0, defaultNorm: 0.5)
    static let delay = ParamSpec(.linear(0.3, 500), steps: 4997, unit: "ms", decimals: 1, defaultNorm: 0)

    static let headampGain = ParamSpec(.linear(-12, 60), steps: 144, unit: "dB", defaultNorm: 12.0 / 72.0)
    static let trim = ParamSpec(.linear(-18, 18), steps: 144, unit: "dB", defaultNorm: 0.5)
    static let hpf = ParamSpec(.logarithmic(20, 400), steps: 100, unit: "Hz", defaultNorm: 0.405)

    static let eqFreq = ParamSpec(.logarithmic(20, 20000), steps: 200, unit: "Hz", defaultNorm: 0.5)
    static let eqGain = ParamSpec(.linear(-15, 15), steps: 120, unit: "dB", defaultNorm: 0.5)
    static let eqQ = ParamSpec(.logarithmic(10, 0.3), steps: 71, decimals: 1, defaultNorm: 0.4648)

    static let gateThreshold = ParamSpec(.linear(-80, 0), steps: 160, unit: "dB", defaultNorm: 0.5)
    static let gateRange = ParamSpec(.linear(3, 60), steps: 57, unit: "dB", decimals: 0, defaultNorm: 1)
    static let attack = ParamSpec(.linear(0, 120), steps: 120, unit: "ms", decimals: 0, defaultNorm: 10.0 / 120.0)
    static let hold = ParamSpec(.logarithmic(0.02, 2000), steps: 100, unit: "ms", decimals: 2, defaultNorm: 0.5)
    static let release = ParamSpec(.logarithmic(5, 4000), steps: 100, unit: "ms", decimals: 0, defaultNorm: 0.5)

    static let dynThreshold = ParamSpec(.linear(-60, 0), steps: 120, unit: "dB", defaultNorm: 1)
    static let knee = ParamSpec(.linear(0, 5), steps: 5, decimals: 0, defaultNorm: 0.2)
    static let makeup = ParamSpec(.linear(0, 24), steps: 48, unit: "dB", defaultNorm: 0)
    static let dynMix = ParamSpec(.linear(0, 100), steps: 20, unit: "%", decimals: 0, defaultNorm: 1)
}

/// Enumerations used by X32 parameters.
enum X32Enums {
    static let colorNames = ["Off", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
    static let eqTypes = ["LCut", "LShv", "PEQ", "VEQ", "HShv", "HCut"]
    static let eqTypesLong = ["Low cut", "Low shelf", "Parametric", "Vintage", "High shelf", "High cut"]
    static let busEqExtraTypes = ["BU6", "BU12", "BS12", "LR12", "BU18", "BU24", "BS24", "LR24"]
    static let gateModes = ["EXP2", "EXP3", "EXP4", "GATE", "DUCK"]
    static let dynModes = ["COMP", "EXP"]
    static let dynDetect = ["PEAK", "RMS"]
    static let dynEnvelope = ["LIN", "LOG"]
    static let ratios: [String] = ["1.1", "1.3", "1.5", "2", "2.5", "3", "4", "5", "7", "10", "20", "100"]
    static let ratioValues: [Float] = [1.1, 1.3, 1.5, 2, 2.5, 3, 4, 5, 7, 10, 20, 100]
    static let hpfSlopes = ["12", "18", "24"]
    static let sendTaps = ["In/LC", "<-EQ", "EQ->", "Pre", "Post", "Group"]
    /// /…/insert/sel
    static let insertSelections = ["Off", "FX1L", "FX1R", "FX2L", "FX2R", "FX3L", "FX3R", "FX4L", "FX4R",
                                   "FX5L", "FX5R", "FX6L", "FX6R", "FX7L", "FX7R", "FX8L", "FX8R",
                                   "Aux 1", "Aux 2", "Aux 3", "Aux 4", "Aux 5", "Aux 6"]
    /// /…/insert/pos and /…/dyn/pos
    static let prePost = ["Pre", "Post"]
    /// Sidechain filter types for gate and compressor keys.
    static let keyFilterTypes = ["LC6", "LC12", "HC6", "HC12", "BP 1.0", "BP 2.0", "BP 3.0", "BP 5.0", "BP 10.0"]

    /// /ch/xx/config/source values.
    static func sourceName(_ v: Int) -> String {
        switch v {
        case 0: return "Off"
        case 1...32: return "In \(v)"
        case 33...38: return "Aux \(v - 32)"
        case 39: return "USB L"
        case 40: return "USB R"
        case 41...48:
            let n = v - 41
            return "FX \(n / 2 + 1)\(n % 2 == 0 ? "L" : "R")"
        case 49...64: return "Bus \(v - 48)"
        default: return "#\(v)"
        }
    }
}

/// Solo/phones monitoring and talkback settings.
enum Monitoring {
    static let sourcePath = "/config/solo/source"
    static let monoPath = "/config/solo/mono"
    static let channelModePath = "/config/solo/chmode"
    static let busModePath = "/config/solo/busmode"
    static let exclusivePath = "/config/solo/exclusive"

    static func talkDestinationPath(_ channel: String) -> String { "/config/talk/\(channel)/destmap" }

    /// What the phones/monitor outputs listen to when nothing is soloed.
    static let sources = ["Off", "LR", "LR + C", "LR PFL", "LR AFL", "Aux 5/6", "Aux 7/8"]
    static let soloModes = ["PFL", "AFL"]
    /// Talkback destination bits: mix buses 1-16, then LR and mono/centre.
    static let talkDestinations: [String] = (1...16).map { "\($0)" } + ["LR", "M/C"]

    static var addresses: [String] {
        [sourcePath, monoPath, channelModePath, busModePath, exclusivePath, talkDestinationPath("A"), talkDestinationPath("B")]
    }
}

/// The desk's built-in USB stick recorder (2-track).
enum Recorder {
    static let statePath = "/-stat/tape/state"
    static let filePath = "/-stat/tape/file"
    static let mountedPath = "/-stat/usbmounted"

    enum State: Int, CaseIterable {
        case stop = 0, playPaused, play, recordPaused, record, fastForward, rewind

        var title: String {
            switch self {
            case .stop: return "Stopped"
            case .playPaused: return "Playback paused"
            case .play: return "Playing"
            case .recordPaused: return "Recording paused"
            case .record: return "Recording"
            case .fastForward: return "Fast forward"
            case .rewind: return "Rewind"
            }
        }

        var isRecording: Bool { self == .record || self == .recordPaused }
    }

    static var addresses: [String] { [statePath, filePath, mountedPath] }

    /// What the pause button does from each state.
    static func pauseTarget(from state: State) -> State? {
        switch state {
        case .play: return .playPaused
        case .playPaused: return .play
        case .record: return .recordPaused
        case .recordPaused: return .record
        default: return nil
        }
    }
}
