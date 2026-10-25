import Foundation

/// The desk's automixer: two groups (X and Y) of channels that share a gain budget, so the
/// loudest talker comes through and open mics come down.
enum Automix {
    static func enablePath(_ group: String) -> String { "/config/amixenable/\(group)" }
    static let groupNames = ["Off", "X", "Y"]

    static func groupPath(_ strip: StripID) -> String? {
        strip.kind == .channel ? strip.base + "/automix/group" : nil
    }

    static func weightPath(_ strip: StripID) -> String? {
        strip.kind == .channel ? strip.base + "/automix/weight" : nil
    }

    /// -12…+12 dB in 0.5 dB steps: how much a channel is favoured within its group.
    static let weightSpec = ParamSpec(.linear(-12, 12), steps: 48, unit: "dB", decimals: 1, defaultNorm: 0.5)

    static var globalAddresses: [String] { [enablePath("X"), enablePath("Y")] }

    static func addresses(_ strip: StripID) -> [String] {
        [groupPath(strip), weightPath(strip)].compactMap { $0 }
    }
}

/// The built-in signal generator (sine, pink or white noise) that can be sent to a mix bus,
/// the mains or a matrix for testing and ringing out.
enum Oscillator {
    static let onPath = "/-stat/osc/on"
    static let levelPath = "/config/osc/level"
    static let f1Path = "/config/osc/f1"
    static let f2Path = "/config/osc/f2"
    static let selectPath = "/config/osc/fsel"
    static let typePath = "/config/osc/type"
    static let destinationPath = "/config/osc/dest"

    static let types = ["Sine", "Pink noise", "White noise"]
    static let frequencySelect = ["F1", "F2"]
    /// 20 Hz – 20 kHz in 121 steps, like the EQ but coarser.
    static let frequencySpec = ParamSpec(.logarithmic(20, 20000), steps: 120, unit: "Hz", decimals: 0, defaultNorm: 0.5)
    /// Same 161-step level law as a send.
    static let levelSpec = Specs.send

    /// /config/osc/dest values: mix buses, then L, R, L+R, M/C, then the matrices.
    static let destinations: [String] = (1...16).map { "Mix \($0)" } + ["Main L", "Main R", "Main L+R", "M/C"] + (1...6).map { "Mtx \($0)" }

    static var addresses: [String] { [onPath, levelPath, f1Path, f2Path, selectPath, typePath, destinationPath] }

    static func destinationName(_ v: Int) -> String {
        destinations.indices.contains(v) ? destinations[v] : "Destination \(v)"
    }
}
