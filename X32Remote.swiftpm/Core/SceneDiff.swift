import Foundation

/// "What changed since soundcheck": the differences between a saved scene and the desk now,
/// node by node, in words a person can read, each with the scene's line to put it back.
enum SceneDiff {
    struct Change: Identifiable, Equatable {
        /// The node path, e.g. "/ch/05/eq/2".
        let path: String
        /// "Lead Vox (Ch 5) · EQ band 2"
        let title: String
        /// What the scene had, and what the desk has now (values only).
        let saved: String
        let now: String
        /// The scene's line: sending it to the desk puts this back.
        let restoreLine: String
        var id: String { path }

        /// Just the fields that differ, in words: "Mute: on → off · Fader: -4.0 → -10.0".
        var summary: String { SceneDiff.describe(path: path, saved: saved, now: now) }
    }

    /// Differences for the nodes in `scene` (nodes the desk didn't answer are left out).
    /// `names` gives a strip's name for nicer titles.
    static func changes(scene: [String], desk: [String], names: (StripID) -> String = { _ in "" }) -> [Change] {
        var deskByPath: [String: String] = [:]
        for line in desk { deskByPath[SceneFile.path(of: line)] = line }
        var out: [Change] = []
        for line in scene {
            let path = SceneFile.path(of: line)
            guard let current = deskByPath[path] else { continue }
            let a = SceneFile.tokens(line).values
            let b = SceneFile.tokens(current).values
            guard !same(a, b) else { continue }
            out.append(Change(path: path, title: title(for: path, names: names),
                              saved: a.joined(separator: " "), now: b.joined(separator: " "), restoreLine: line))
        }
        return out
    }

    /// Values match when every token matches, numbers within a hair (X32-Edit and the desk
    /// sometimes write the same number differently, like 0.0 and +0.0).
    static func same(_ a: [String], _ b: [String]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where x != y {
            if let fx = number(x), let fy = number(y), abs(fx - fy) < 0.011 { continue }
            return false
        }
        return true
    }

    private static func number(_ s: String) -> Double? {
        if s == "-oo" { return -1e9 }
        // The desk writes kHz values like "1k23" and "10k0".
        if let k = s.firstIndex(of: "k"), let whole = Double(s[..<k]) {
            let frac = String(s[s.index(after: k)...])
            return (whole + (Double("0." + frac) ?? 0)) * 1000
        }
        return Double(s.replacingOccurrences(of: "+", with: ""))
    }

    /// Field names for the node types people change most (in the desk's own order).
    static func fields(for path: String) -> [String]? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let head = parts[0]
        let isStrip = ["ch", "auxin", "fxrtn", "bus", "mtx"].contains(head)
        if head == "headamp" { return ["Gain", "48 V"] }
        if head == "dca" && parts.count == 2 { return ["On", "Level"] }
        if head == "dca" && parts.last == "config" { return ["Name", "Icon", "Colour"] }
        if head == "fx" && parts.count == 2 { return ["Type", "Source"] }
        if head == "main" && parts.count == 2 { return ["Mute", "Fader", "", "Pan", "", ""] }
        if head == "main" && parts.last == "config" { return ["Name", "Icon", "Colour"] }
        guard isStrip, parts.count >= 3 else { return nil }
        let rest = Array(parts.dropFirst(2))
        switch rest.first {
        case "config": return ["Name", "Icon", "Colour", "Source"]
        case "preamp": return head == "ch" ? ["Trim", "Polarity", "Low cut", "Slope", "Low cut Hz"] : ["Trim", "Polarity"]
        case "gate": return rest.count == 1 ? ["On", "Mode", "Threshold", "Range", "Attack", "Hold", "Release", "Key"] : ["Key filter", "Type", "Hz"]
        case "dyn": return rest.count == 1 ? ["On", "Mode", "Detector", "Envelope", "Threshold", "Ratio", "Knee", "Make-up", "Attack", "Hold", "Release", "Position", "Key", "Mix", "Auto"] : ["Key filter", "Type", "Hz"]
        case "eq": return rest.count == 1 ? ["On"] : ["Type", "Hz", "Gain", "Q"]
        case "mix":
            if rest.count == 1 { return ["Mute", "Fader", "To LR", "Pan", "To M/C", "M/C level"] }
            return ["On", "Level", "Pan", "Pre/post", "Pan follows"]
        case "grp": return ["DCAs", "Mute groups"]
        case "delay": return ["On", "Time"]
        default: return nil
        }
    }

    /// The differing fields of two value strings, in words.
    static func describe(path: String, saved: String, now: String) -> String {
        let a = saved.split(separator: " ").map(String.init)
        let b = now.split(separator: " ").map(String.init)
        guard a.count == b.count else { return "\(saved) → \(now)" }
        let names = fields(for: path)
        var parts: [String] = []
        for i in a.indices where a[i] != b[i] {
            if let fx = number(a[i]), let fy = number(b[i]), abs(fx - fy) < 0.011 { continue }
            var name = names.flatMap { i < $0.count ? $0[i] : nil } ?? "Value \(i + 1)"
            if name.isEmpty { name = "Value \(i + 1)" }
            var x = a[i], y = b[i]
            if name == "Mute" {
                // The desk stores "ON" for not muted.
                x = a[i] == "ON" ? "off" : "on"
                y = b[i] == "ON" ? "off" : "on"
            } else {
                x = x.lowercased() == "on" || x.lowercased() == "off" ? x.lowercased() : x
                y = y.lowercased() == "on" || y.lowercased() == "off" ? y.lowercased() : y
            }
            parts.append("\(name): \(x) → \(y)")
        }
        return parts.isEmpty ? "\(saved) → \(now)" : parts.joined(separator: " · ")
    }

    /// A readable name for a node path.
    static func title(for path: String, names: (StripID) -> String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard let head = parts.first else { return path }
        let kinds: [String: StripKind] = ["ch": .channel, "auxin": .auxIn, "fxrtn": .fxReturn, "bus": .bus, "mtx": .matrix, "dca": .dca]
        var strip: StripID?
        var rest = Array(parts.dropFirst())
        if let kind = kinds[head], let n = rest.first.flatMap({ Int($0) }) {
            strip = StripID(kind, n)
            rest.removeFirst()
        } else if head == "main" {
            strip = rest.first == "m" ? StripID.monoC : StripID.mainLR
            rest = Array(rest.dropFirst())
        }
        let what: String = {
            guard let first = rest.first else { return "On and level" }
            switch first {
            case "config": return "Name, colour and source"
            case "delay": return "Delay"
            case "preamp": return "Trim, polarity and low cut"
            case "gate": return rest.count > 1 ? "Gate key filter" : "Gate"
            case "dyn": return rest.count > 1 ? "Compressor key filter" : "Compressor"
            case "insert": return "Insert"
            case "eq": return rest.count > 1 ? "EQ band \(rest[1])" : "EQ on/off"
            case "mix":
                if rest.count > 1, let n = Int(rest[1]) { return "Send to Mix \(n)" }
                return "Fader, mute and pan"
            case "grp": return "DCA and mute groups"
            case "automix": return "Automix"
            default: return first
            }
        }()
        if let strip {
            let name = names(strip)
            let who = name.isEmpty ? strip.footLabel : "\(name) (\(strip.footLabel))"
            return "\(who) · \(what)"
        }
        switch head {
        case "fx": return "FX \(parts.count > 1 ? parts[1] : "") " + (parts.count > 2 ? (parts[2] == "par" ? "settings" : parts[2]) : "type")
        case "headamp": return "Preamp \(parts.count > 1 ? parts[1] : "") gain and 48V"
        case "outputs": return "Output patch " + parts.dropFirst().joined(separator: " ")
        case "config": return "Desk setup · " + parts.dropFirst().joined(separator: " ")
        default: return path
        }
    }
}
