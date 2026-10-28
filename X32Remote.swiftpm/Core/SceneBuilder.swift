import Foundation

/// Builds a whole desk setup from a plain description ("rock band: 2 vox, acoustic, bass, keys,
/// drums" or "church service with a pastor lapel and worship team"): channel names and colours,
/// a starting EQ/gate/compressor for every source, DCAs and named monitor mixes.
///
/// The description is read by the built-in parser below; on iPads with Apple Intelligence the app
/// can use the on-device model instead, which hands back the same `ScenePlan`.
struct ScenePlan: Equatable {
    struct Input: Identifiable, Equatable {
        var id = UUID()
        var name: String
        /// A `StarterPresets` name ("Kick", "Lead vocal"…).
        var starter: String
        var group: Group

        init(_ name: String, _ starter: String, _ group: Group) {
            self.name = SceneBuilder.deskName(name)
            self.starter = starter
            self.group = group
        }
    }

    /// Groups decide colour and DCA.
    enum Group: String, CaseIterable, Equatable {
        case drums = "Drums", bass = "Bass", guitars = "Guitars", keys = "Keys", vocals = "Vocals"
        case horns = "Horns", speech = "Speech", playback = "Playback"

        /// X32 scribble colours: 1 red, 2 green, 3 yellow, 4 blue, 5 magenta, 6 cyan, 7 white.
        var color: Int {
            switch self {
            case .drums: return 1
            case .bass: return 4
            case .guitars: return 2
            case .keys: return 3
            case .vocals: return 5
            case .horns: return 3
            case .speech: return 7
            case .playback: return 6
            }
        }

        /// The DCA it goes on (drums, band, vocals, speech, playback).
        var dcaName: String {
            switch self {
            case .drums: return "Drums"
            case .bass, .guitars, .keys, .horns: return "Band"
            case .vocals: return "Vocals"
            case .speech: return "Speech"
            case .playback: return "Playback"
            }
        }

        static func of(starter: String) -> Group {
            switch StarterPresets.named(starter)?.category {
            case .drums?: return .drums
            case .strings?: return starter.lowercased().hasPrefix("bass") ? .bass : .guitars
            case .keys?: return .keys
            case .horns?: return .horns
            case .speech?: return .speech
            case .playback?: return .playback
            default: return .vocals
            }
        }
    }

    var title: String
    var inputs: [Input]
    var mixes: [String]

    /// DCA names in the order they're used.
    var dcas: [String] {
        var seen: [String] = []
        for i in inputs where !seen.contains(i.group.dcaName) { seen.append(i.group.dcaName) }
        return Array(seen.prefix(8))
    }
}

enum SceneBuilder {
    /// X32 names are at most 12 characters.
    static func deskName(_ s: String) -> String {
        var out = ""
        for ch in s.trimmingCharacters(in: .whitespaces) {
            if (out + String(ch)).utf8.count > 12 { break }
            out.append(ch)
        }
        return out
    }

    // MARK: - Reading a description

    private static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "single": 1, "two": 2, "pair": 2, "couple": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8,
    ]

    /// What a word (or two) in the description means: inputs to add, per item.
    private struct Source {
        let keys: [String]
        let make: (Int) -> [ScenePlan.Input]
    }

    private static func numbered(_ base: String, _ starter: String, _ group: ScenePlan.Group, _ n: Int) -> [ScenePlan.Input] {
        n <= 1 ? [ScenePlan.Input(base, starter, group)] : (1...n).map { ScenePlan.Input("\(base) \($0)", starter, group) }
    }

    private static func stereo(_ base: String, _ starter: String, _ group: ScenePlan.Group) -> [ScenePlan.Input] {
        [ScenePlan.Input("\(base) L", starter, group), ScenePlan.Input("\(base) R", starter, group)]
    }

    static let drumKit: [ScenePlan.Input] = [
        .init("Kick", "Kick", .drums), .init("Snare", "Snare", .drums), .init("Hi-Hat", "Hi-hat", .drums),
        .init("Rack Tom", "Toms", .drums), .init("Floor Tom", "Toms", .drums),
        .init("OH L", "Overheads", .drums), .init("OH R", "Overheads", .drums),
    ]

    /// Longest phrases first, so "lead vocal" wins over "vocal" and "bass amp" over "bass".
    private static let sources: [Source] = [
        Source(keys: ["drum kit", "drums", "kit"]) { _ in drumKit },
        Source(keys: ["kick drum", "kick"]) { n in numbered("Kick", "Kick", .drums, n) },
        Source(keys: ["snare"]) { n in numbered("Snare", "Snare", .drums, n) },
        Source(keys: ["hi-hat", "hihat", "hi hat", "hats"]) { _ in [.init("Hi-Hat", "Hi-hat", .drums)] },
        Source(keys: ["toms", "tom"]) { n in numbered("Tom", "Toms", .drums, max(n, 2)) },
        Source(keys: ["overheads", "overhead"]) { _ in stereo("OH", "Overheads", .drums) },
        Source(keys: ["cajon"]) { n in numbered("Cajon", "Cajon", .drums, n) },
        Source(keys: ["percussion", "percs", "congas", "bongos"]) { n in numbered("Perc", "Overheads", .drums, n) },
        Source(keys: ["bass amp", "bass cab"]) { _ in [.init("Bass Amp", "Bass amp", .bass)] },
        Source(keys: ["bass guitar", "bassist", "bass di", "bass"]) { _ in [.init("Bass", "Bass DI", .bass)] },
        Source(keys: ["acoustic guitars", "acoustic guitar", "acoustic", "acoustics"]) { n in numbered("Acoustic", "Acoustic guitar", .guitars, n) },
        Source(keys: ["electric guitars", "electric guitar", "electric", "lead guitar", "rhythm guitar", "guitars", "guitar", "gtr"]) { n in numbered("Gtr", "Electric guitar", .guitars, n) },
        Source(keys: ["piano"]) { _ in stereo("Piano", "Piano", .keys) },
        Source(keys: ["organ", "hammond"]) { _ in stereo("Organ", "Organ", .keys) },
        Source(keys: ["synth", "synths"]) { _ in stereo("Synth", "Synth", .keys) },
        Source(keys: ["keyboard", "keyboards", "keys"]) { _ in stereo("Keys", "Keys", .keys) },
        Source(keys: ["saxophone", "saxes", "sax"]) { n in numbered("Sax", "Sax", .horns, n) },
        Source(keys: ["trumpet", "trumpets", "horns", "horn", "brass", "trombone"]) { n in numbered("Tpt", "Trumpet", .horns, n) },
        Source(keys: ["violin", "violins", "fiddle", "strings", "cello"]) { n in numbered("Violin", "Violin", .horns, n) },
        Source(keys: ["lead vocals", "lead vocal", "lead vox", "lead singer", "worship leader", "frontman", "singer", "lead"]) { n in numbered("Lead Vox", "Lead vocal", .vocals, n) },
        Source(keys: ["backing vocals", "backing vocal", "backing vox", "backing singers", "bvs", "bv", "harmonies"]) { n in numbered("BV", "Backing vocal", .vocals, max(n, 1)) },
        Source(keys: ["rapper", "rap", "mc"]) { n in numbered("MC", "Rap vocal", .vocals, n) },
        Source(keys: ["choir"]) { n in numbered("Choir", "Choir", .vocals, max(n, 2)) },
        Source(keys: ["vocals", "vocal", "vox", "voices", "singers"]) { n in
            n <= 1 ? [.init("Lead Vox", "Lead vocal", .vocals)]
                   : [.init("Lead Vox", "Lead vocal", .vocals)] + (1..<n).map { .init("BV \($0)", "Backing vocal", .vocals) }
        },
        Source(keys: ["pastor", "preacher", "minister", "priest", "celebrant"]) { _ in [.init("Pastor", "Lapel mic", .speech)] },
        Source(keys: ["lectern", "podium", "pulpit"]) { _ in [.init("Lectern", "Speech", .speech)] },
        Source(keys: ["instructor", "trainer", "coach", "teacher"]) { _ in [.init("Instructor", "Headset mic", .speech)] },
        Source(keys: ["headset", "headsets"]) { n in numbered("Headset", "Headset mic", .speech, n) },
        Source(keys: ["lapel", "lapels", "lav", "lavalier"]) { n in numbered("Lapel", "Lapel mic", .speech, n) },
        Source(keys: ["presenter", "host", "speaker", "speakers", "emcee", "panel", "announcements"]) { n in numbered("Speaker", "Speech", .speech, n) },
        Source(keys: ["handheld", "handhelds", "wireless mics", "wireless mic", "radio mics", "mics", "mic"]) { n in numbered("Mic", "Speech", .speech, max(n, 1)) },
        Source(keys: ["dj"]) { _ in stereo("DJ", "DJ", .playback) },
        Source(keys: ["playback", "backing tracks", "tracks", "track", "laptop", "spotify", "ipod", "music", "video"]) { _ in stereo("Playback", "Playback", .playback) },
    ]

    /// Events that suggest a setup when the description doesn't list the inputs.
    private static let events: [(keys: [String], inputs: () -> [ScenePlan.Input], mixes: [String])] = [
        (["church", "worship", "service", "mass", "chapel"], {
            [.init("Pastor", "Lapel mic", .speech), .init("Lectern", "Speech", .speech),
             .init("Lead Vox", "Lead vocal", .vocals), .init("BV 1", "Backing vocal", .vocals), .init("BV 2", "Backing vocal", .vocals),
             .init("Acoustic", "Acoustic guitar", .guitars), .init("Gtr", "Electric guitar", .guitars), .init("Bass", "Bass DI", .bass),
             .init("Keys L", "Keys", .keys), .init("Keys R", "Keys", .keys)] + drumKit +
            [.init("Playback L", "Playback", .playback), .init("Playback R", "Playback", .playback)]
        }, ["Lead Vox", "BVs", "Band", "Drums", "Stage"]),
        (["conference", "meeting", "seminar", "presentation", "talk", "lecture", "speeches", "awards", "funeral", "panel"], {
            [.init("Lectern", "Speech", .speech), .init("Lapel", "Lapel mic", .speech),
             .init("Mic 1", "Speech", .speech), .init("Mic 2", "Speech", .speech),
             .init("Playback L", "Playback", .playback), .init("Playback R", "Playback", .playback)]
        }, ["Stage"]),
        (["gym", "fitness", "class", "spin", "yoga", "crossfit", "bootcamp", "workout"], {
            [.init("Instructor", "Headset mic", .speech), .init("Mic", "Speech", .speech),
             .init("Music L", "Playback", .playback), .init("Music R", "Playback", .playback)]
        }, []),
        (["wedding", "reception"], {
            [.init("Celebrant", "Lapel mic", .speech), .init("Mic 1", "Speech", .speech), .init("Mic 2", "Speech", .speech),
             .init("Playback L", "Playback", .playback), .init("Playback R", "Playback", .playback)]
        }, []),
        (["band", "gig", "rock", "covers", "concert", "show", "pub", "festival", "jazz", "funk", "live music"], {
            drumKit + [.init("Bass", "Bass DI", .bass), .init("Gtr 1", "Electric guitar", .guitars), .init("Gtr 2", "Electric guitar", .guitars),
                       .init("Keys L", "Keys", .keys), .init("Keys R", "Keys", .keys),
                       .init("Lead Vox", "Lead vocal", .vocals), .init("BV 1", "Backing vocal", .vocals), .init("BV 2", "Backing vocal", .vocals),
                       .init("Playback L", "Playback", .playback), .init("Playback R", "Playback", .playback)]
        }, ["Lead Vox", "BVs", "Gtr", "Bass", "Keys", "Drums"]),
        (["dj", "party", "club", "disco"], {
            [.init("DJ L", "DJ", .playback), .init("DJ R", "DJ", .playback), .init("MC", "Speech", .speech)]
        }, ["DJ booth"]),
    ]

    /// Reads a description into a plan. Never returns an empty plan for a non-empty description
    /// with recognisable words; returns nil when nothing at all was recognised.
    static func plan(from description: String) -> ScenePlan? {
        // Punctuation separates items ("drums, mics"): keep it as its own word.
        var cleaned = ""
        for ch in description.lowercased().replacingOccurrences(of: "&", with: " and ") {
            if ch.isLetter || ch.isNumber || ch == "-" { cleaned.append(ch) }
            else if ",.;:/+()".contains(ch) { cleaned += " , " }
            else { cleaned.append(" ") }
        }
        let text = " " + cleaned + " "
        let chars = Array(text)
        var used = Array(repeating: false, count: chars.count)
        var found: [(position: Int, inputs: [ScenePlan.Input])] = []

        // Every key is matched as whole words, longest first, so a word is only used once.
        let allKeys = sources.enumerated().flatMap { (i, s) in s.keys.map { (key: $0, source: i) } }
            .sorted { $0.key.count > $1.key.count }
        for (key, sourceIndex) in allKeys {
            let needle = Array(" " + key + " ")
            var i = 0
            while i + needle.count <= chars.count {
                guard Array(chars[i..<(i + needle.count)]) == needle,
                      !used[(i + 1)..<(i + needle.count - 1)].contains(true) else {
                    i += 1
                    continue
                }
                for j in (i + 1)..<(i + needle.count - 1) { used[j] = true }
                // "pastor lapel mic", "vocal mic": a describing word right after something already
                // recognised adds nothing of its own.
                if modifiers.contains(key) && previousWordUsed(before: i, in: chars, used: used) {
                    i += needle.count - 1
                    continue
                }
                found.append((i, sources[sourceIndex].make(number(before: i, in: chars) ?? 1)))
                i += needle.count - 1
            }
        }
        found.sort { $0.position < $1.position }
        var inputs = order(found.flatMap(\.inputs))
        var mixes: [String] = []
        var title = "New scene"

        if let event = events.first(where: { e in e.keys.contains { text.contains(" \($0) ") } }) {
            title = event.keys.first(where: { text.contains(" \($0) ") })!.capitalized
            if inputs.isEmpty { inputs = event.inputs() }
            mixes = event.mixes
        }
        guard !inputs.isEmpty else { return nil }
        inputs = uniqueNames(inputs)

        // Monitor mixes: asked for, or the event's usual ones.
        let wantsMonitors = [" wedge", " monitor", " iem", " in-ear", " in ear", " foldback", " ears "].contains { text.contains($0) }
        if wantsMonitors || mixes.isEmpty == false {
            if mixes.isEmpty || wantsMonitors {
                mixes = monitorMixes(for: inputs)
            }
        }
        if let n = numberBefore(word: "mixes", in: text) ?? numberBefore(word: "wedges", in: text) ?? numberBefore(word: "iems", in: text) {
            mixes = Array((mixes + (1...16).map { "Mix \($0)" }).prefix(n))
        }
        return ScenePlan(title: title, inputs: Array(inputs.prefix(32)), mixes: Array(mixes.prefix(12)))
    }

    private static let modifiers: Set<String> = [
        "mic", "mics", "lapel", "lapels", "lav", "lavalier", "headset", "headsets", "handheld", "handhelds",
        "wireless mic", "wireless mics", "radio mics",
    ]

    private static func previousWordUsed(before index: Int, in chars: [Character], used: [Bool]) -> Bool {
        var end = index
        while end > 0 && chars[end - 1] == " " { end -= 1 }
        guard end > 0, chars[end - 1] != "," else { return false }
        return used[end - 1]
    }

    private static func number(before index: Int, in chars: [Character]) -> Int? {
        // The word just before the match: "2 vox", "two acoustics".
        var end = index
        while end > 0 && chars[end - 1] == " " { end -= 1 }
        var start = end
        while start > 0 && chars[start - 1] != " " { start -= 1 }
        guard start < end else { return nil }
        let word = String(chars[start..<end])
        if let n = Int(word), n > 0, n <= 16 { return n }
        if let n = Int(word.replacingOccurrences(of: "x", with: "")), word.hasSuffix("x"), n > 0, n <= 16 { return n }
        return numberWords[word]
    }

    private static func numberBefore(word: String, in text: String) -> Int? {
        guard let r = text.range(of: " " + word + " ") else { return nil }
        return number(before: text.distance(from: text.startIndex, to: r.lowerBound), in: Array(text))
    }

    /// The usual desk order: drums, bass, guitars, keys, horns, vocals, speech, playback.
    private static func order(_ inputs: [ScenePlan.Input]) -> [ScenePlan.Input] {
        let rank: [ScenePlan.Group: Int] = [.drums: 0, .bass: 1, .guitars: 2, .keys: 3, .horns: 4, .vocals: 5, .speech: 6, .playback: 7]
        return inputs.enumerated().sorted { a, b in
            let ra = rank[a.element.group] ?? 9, rb = rank[b.element.group] ?? 9
            return ra == rb ? a.offset < b.offset : ra < rb
        }.map(\.element)
    }

    /// "Gtr", "Gtr" → "Gtr 1", "Gtr 2".
    private static func uniqueNames(_ inputs: [ScenePlan.Input]) -> [ScenePlan.Input] {
        var counts: [String: Int] = [:]
        for i in inputs { counts[i.name, default: 0] += 1 }
        var seen: [String: Int] = [:]
        return inputs.map { input in
            guard (counts[input.name] ?? 0) > 1 else { return input }
            seen[input.name, default: 0] += 1
            var copy = input
            copy.name = deskName("\(input.name) \(seen[input.name]!)")
            return copy
        }
    }

    /// One mix per lead/backing vocal and per instrument family, as performers usually get.
    static func monitorMixes(for inputs: [ScenePlan.Input]) -> [String] {
        var mixes: [String] = []
        func add(_ s: String) { if !mixes.contains(s) { mixes.append(s) } }
        for i in inputs {
            switch i.group {
            case .vocals: add(i.starter == "Backing vocal" ? "BVs" : deskName(i.name))
            case .guitars: add(deskName(i.name.hasPrefix("Acoustic") ? "Acoustic" : "Gtr"))
            case .bass: add("Bass")
            case .keys: add("Keys")
            case .drums: add("Drums")
            case .horns: add("Horns")
            case .speech where i.name == "Pastor" || i.name == "Instructor": add("Stage")
            default: break
            }
        }
        return mixes
    }

    // MARK: - From plan to desk

    /// Every change the plan makes, for one undoable step. Channels beyond the plan are cleared
    /// (name and colour) when `clearRest` is on.
    static func changes(for plan: ScenePlan, clearRest: Bool) -> [(String, OSCArg)] {
        var out: [(String, OSCArg)] = []
        let dcas = plan.dcas
        for (i, input) in plan.inputs.prefix(32).enumerated() {
            let ch = StripID(.channel, i + 1)
            out.append((ch.namePath, .string(input.name)))
            out.append((ch.colorPath, .int(Int32(input.group.color))))
            if let starter = StarterPresets.named(input.starter) {
                out += StarterPresets.preset(starter).clip.changes(onto: ch)
            }
            if let path = ch.dcaGroupsPath, let d = dcas.firstIndex(of: input.group.dcaName) {
                out.append((path, .int(Int32(1 << d))))
            }
            // Stereo pairs (… L / … R) pan apart.
            if let pan = ch.panPath {
                if input.name.hasSuffix(" L") { out.append((pan, .float(0))) }
                else if input.name.hasSuffix(" R") { out.append((pan, .float(1))) }
            }
        }
        if clearRest && plan.inputs.count < 32 {
            for n in (plan.inputs.count + 1)...32 {
                let ch = StripID(.channel, n)
                out.append((ch.namePath, .string("")))
                out.append((ch.colorPath, .int(0)))
                if let path = ch.dcaGroupsPath { out.append((path, .int(0))) }
            }
        }
        for (i, name) in dcas.enumerated() {
            let dca = StripID(.dca, i + 1)
            out.append((dca.namePath, .string(deskName(name))))
            let color = ScenePlan.Group.allCases.first { $0.dcaName == name }?.color ?? 7
            out.append((dca.colorPath, .int(Int32(color))))
        }
        for (i, name) in plan.mixes.prefix(12).enumerated() {
            let bus = StripID(.bus, i + 1)
            out.append((bus.namePath, .string(deskName(name))))
            out.append((bus.colorPath, .int(Int32(i % 7 + 1))))
        }
        return out
    }
}
