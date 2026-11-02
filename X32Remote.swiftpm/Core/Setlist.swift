import Foundation

/// A setlist: songs in order, each with its tempo (delays follow it), notes for the engineer,
/// and the channels that sit the song out (muted while it plays).
struct Setlist: Codable, Identifiable, Equatable {
    struct Song: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        /// Beats per minute; nil leaves the delays alone.
        var bpm: Double?
        var notes: String = ""
        /// Strip ids ("channel-5") muted for this song.
        var sittingOut: [String] = []
    }

    var id = UUID()
    var name: String
    var songs: [Song] = []
}

enum SetlistMath {
    /// A quarter note at `bpm`, in ms, within what the X32 delays can do.
    static func delayMS(bpm: Double) -> Float {
        guard bpm > 0 else { return 500 }
        return Float(min(max(60000 / bpm, 1), 3000))
    }

    /// Changes for moving to `song`: delay times for every delay effect loaded in slots 1-4
    /// (`types` gives each slot's effect type), mutes for the channels sitting out, and unmutes for
    /// the ones the previous song had sitting out that play in this one.
    static func changes(for song: Setlist.Song, previous: Setlist.Song?, types: (Int) -> Int?) -> [(String, OSCArg)] {
        var out: [(String, OSCArg)] = []
        if let bpm = song.bpm {
            let ms = delayMS(bpm: bpm)
            for slot in 1...4 {
                guard let t = types(slot), let par = Effects.tapTimeParameter(slot: slot, type: t) else { continue }
                out.append((Effects.parPath(slot, par), .float(X32Math.quantize(Effects.delayTimeSpec.norm(ms), steps: Effects.delayTimeSpec.steps))))
            }
        }
        let now = Set(song.sittingOut)
        for id in song.sittingOut {
            if let s = StripID(id: id) { out.append((s.onPath, .int(0))) }
        }
        for id in previous?.sittingOut ?? [] where !now.contains(id) {
            if let s = StripID(id: id) { out.append((s.onPath, .int(1))) }
        }
        return out
    }

    /// BPM from taps (seconds): the average gap of the last few, ignoring a long pause.
    static func bpm(fromTaps taps: [TimeInterval]) -> Double? {
        let recent = Array(taps.suffix(6))
        guard recent.count >= 2 else { return nil }
        let gaps = zip(recent.dropFirst(), recent).map { $0 - $1 }.filter { $0 > 0.2 && $0 < 2.5 }
        guard !gaps.isEmpty else { return nil }
        let bpm = 60 / (gaps.reduce(0, +) / Double(gaps.count))
        return (bpm * 10).rounded() / 10
    }
}

enum SetlistStore {
    static let key = "X32Remote.setlists.v1"

    static func load(_ defaults: UserDefaults = .standard) -> [Setlist] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Setlist].self, from: data)) ?? []
    }

    static func save(_ lists: [Setlist], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(lists) { defaults.set(data, forKey: key) }
    }
}

// MARK: - Talk over music

/// Ducking: the music channels' gates in DUCK mode, keyed from a mic, so the music dips while
/// someone talks and comes back when they stop.
struct DuckSetup: Codable, Equatable {
    var mic: StripID
    var music: [StripID]
    /// How far the music dips, in dB.
    var depth: Float = 15

    /// The gate settings that make it duck (or switch the gates off again).
    func changes(on: Bool) -> [(String, OSCArg)] {
        var out: [(String, OSCArg)] = []
        guard let key = DuckSetup.keySourceValue(mic) else { return [] }
        for m in music where m.hasGate {
            if on {
                out += [
                    (m.gatePath("mode"), .int(4)),            // DUCK
                    (m.gatePath("keysrc"), .int(Int32(key))),
                    (m.gatePath("thr"), RingOut.arg(Specs.gateThreshold, -45)),
                    (m.gatePath("range"), RingOut.arg(Specs.gateRange, min(max(depth, 3), 60))),
                    (m.gatePath("attack"), RingOut.arg(Specs.attack, 10)),
                    (m.gatePath("hold"), RingOut.arg(Specs.hold, 400)),
                    (m.gatePath("release"), RingOut.arg(Specs.release, 800)),
                    (m.gatePath("on"), .int(1)),
                ]
            } else {
                // Off, and back to a plain gate keyed from its own channel, so switching that
                // gate on later for noise doesn't secretly duck the music.
                out += [
                    (m.gatePath("on"), .int(0)),
                    (m.gatePath("mode"), .int(3)),            // GATE
                    (m.gatePath("keysrc"), .int(0)),          // self
                ]
            }
        }
        return out
    }

    /// The gate key-source value for a strip (1-32 channels, 33-40 aux ins…).
    static func keySourceValue(_ s: StripID) -> Int? {
        switch s.kind {
        case .channel: return s.index
        case .auxIn: return 32 + s.index
        case .fxReturn: return 40 + s.index
        case .bus: return 48 + s.index
        default: return nil
        }
    }

    /// True when the first music channel's gate is set up as a ducker keyed from the mic.
    func isOn(_ value: (String) -> OSCArg?) -> Bool {
        guard let m = music.first(where: { $0.hasGate }), let key = DuckSetup.keySourceValue(mic) else { return false }
        return value(m.gatePath("on"))?.intValue == 1 && value(m.gatePath("mode"))?.intValue == 4
            && value(m.gatePath("keysrc"))?.intValue == key
    }
}
