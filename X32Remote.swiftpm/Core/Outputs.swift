import Foundation

/// The desk's output patch: what each output (local XLRs, aux outs, P16/Ultranet, AES, record)
/// carries, and from which point in a channel when it's a direct out.
enum Outputs {
    enum Group: String, CaseIterable, Identifiable {
        case main, aux, p16, aes, rec

        var id: String { rawValue }

        var count: Int {
            switch self {
            case .main, .p16: return 16
            case .aux: return 6
            case .aes, .rec: return 2
            }
        }

        var title: String {
            switch self {
            case .main: return "Local outs"
            case .aux: return "Aux outs"
            case .p16: return "P16 (Ultranet)"
            case .aes: return "AES/EBU"
            case .rec: return "Record (2-track)"
            }
        }

        var shortLabel: String {
            switch self {
            case .main: return "Out"
            case .aux: return "Aux"
            case .p16: return "P16"
            case .aes: return "AES"
            case .rec: return "Rec"
            }
        }
    }

    static func path(_ group: Group, _ n: Int, _ field: String) -> String {
        String(format: "/outputs/%@/%02d/%@", group.rawValue, n, field)
    }

    /// /outputs/…/src values 0-76.
    static let sourceNames: [String] = {
        var names = ["Off", "Main L", "Main R", "M/C"]
        names += (1...16).map { "Mix \($0)" }
        names += (1...6).map { "Mtx \($0)" }
        names += (1...32).map { "Ch \($0) direct" }
        names += (1...8).map { "Aux \($0) direct" }
        names += (1...8).map { "FX \(($0 + 1) / 2)\($0 % 2 == 1 ? "L" : "R") direct" }
        names += ["Monitor L", "Monitor R", "Talkback"]
        return names
    }()

    /// Where a direct out taps the channel (/outputs/…/pos). "+ mute" taps follow the channel's mute.
    static let tapNames = ["Input", "Input + mute", "Pre EQ", "Pre EQ + mute", "Post EQ", "Post EQ + mute",
                           "Pre fader", "Pre fader + mute", "Post fader"]

    /// Direct outs (channels, aux ins, FX returns) are the only sources the tap point applies to.
    static func isDirectOut(_ source: Int) -> Bool { (26...73).contains(source) }

    /// The source groups shown in the picker, as (title, values).
    static let sourceGroups: [(String, ClosedRange<Int>)] = [
        ("Main", 1...3), ("Mix buses", 4...19), ("Matrices", 20...25),
        ("Channel direct outs", 26...57), ("Aux direct outs", 58...65), ("FX direct outs", 66...73), ("Monitor", 74...76)
    ]

    static func addresses() -> [String] {
        Group.allCases.flatMap { g in
            (1...g.count).flatMap { n in [path(g, n, "src"), path(g, n, "pos")] }
        }
    }
}

extension Outputs {
    /// The strip an output source comes from (for showing its name).
    static func sourceStrip(_ v: Int) -> StripID? {
        switch v {
        case 1, 2: return StripID.mainLR
        case 3: return StripID.monoC
        case 4...19: return StripID(.bus, v - 3)
        case 20...25: return StripID(.matrix, v - 19)
        case 26...57: return StripID(.channel, v - 25)
        case 58...65: return StripID(.auxIn, v - 57)
        case 66...73: return StripID(.fxReturn, v - 65)
        default: return nil
        }
    }

    static func sourceName(_ v: Int) -> String {
        sourceNames.indices.contains(v) ? sourceNames[v] : "Source \(v)"
    }

    /// "/outputs/main/03/src" -> "Out 3 source".
    static func describe(_ address: String) -> String? {
        let parts = address.split(separator: "/")
        guard parts.count == 4, parts[0] == "outputs", let g = Group(rawValue: String(parts[1])), let n = Int(parts[2]) else { return nil }
        let field = ["src": "source", "pos": "tap point", "invert": "polarity"][String(parts[3])] ?? String(parts[3])
        return "\(g.shortLabel) \(n) \(field)"
    }
}
