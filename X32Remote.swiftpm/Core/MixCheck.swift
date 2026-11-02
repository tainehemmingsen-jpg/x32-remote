import Foundation

/// "Mix check": a quick look over every input for the things that usually go wrong at a gig,
/// each explained in plain words and, where it's safe, with a one-tap fix.
enum MixCheck {
    /// What the check needs to know about one channel.
    struct Channel {
        var strip: StripID
        var name: String
        var muted: Bool
        /// Fader in dB (-inf when down).
        var faderDB: Float
        /// Loudest preamp level over the last minute, in dBFS (nil if not known yet).
        var recentPeak: Float?
        var clipped: Bool
        var lowCutOn: Bool?
        var eqOn: Bool
        /// (type, Hz, gain dB) per band.
        var eq: [(type: Int, hz: Float, gain: Float)]
        var compOn: Bool
        var compReduction: Float
        var hasHeadamp: Bool
    }

    enum Severity: Int, Comparable {
        case problem = 0, check = 1
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    enum Fix: Equatable {
        /// Open Auto gain for the channel.
        case autoGain
        /// Make these changes (one undo step).
        case changes([String: OSCArg], label: String)
        /// Open the channel on this page.
        case open(String)

        var buttonTitle: String {
            switch self {
            case .autoGain: return "Auto gain"
            case .changes(_, let label): return label
            case .open: return "Open"
            }
        }
    }

    struct Issue: Identifiable, Equatable {
        let id: String
        let strip: StripID?
        let severity: Severity
        let title: String
        let detail: String
        let fix: Fix?

        static func == (a: Issue, b: Issue) -> Bool { a.id == b.id && a.title == b.title && a.detail == b.detail }
    }

    /// Words that mean a voice is on the channel (low cut is almost always right there).
    private static let voiceWords = ["vox", "vocal", "voc", "voice", "sing", "bv", "pastor", "lectern",
                                     "speech", "host", "lapel", "headset", "instructor", "choir", "talk", "presenter"]
    /// Whole words only ("mc" but not "mcguitar"); "mic" alone is too vague ("Bass Mic", "Amp Mic").
    private static let voiceWholeWords: Set<String> = ["mc", "mic", "handheld", "hh", "spare"]
    private static let notVoice = ["bass", "gtr", "guitar", "amp", "kick", "snare", "tom", "hat", "oh", "piano", "keys", "drum", "cab"]

    static func isVoice(_ name: String) -> Bool {
        let n = name.lowercased()
        if notVoice.contains(where: { n.contains($0) }) && !voiceWords.contains(where: { n.contains($0) }) { return false }
        if voiceWords.contains(where: { n.contains($0) }) { return true }
        let words = n.split { !$0.isLetter }.map(String.init)
        // A plain "Mic 1" / "HH 2" / "MC" is a voice; "Bass Mic" was caught above.
        return words.contains { voiceWholeWords.contains($0) }
    }

    static func label(_ c: Channel) -> String {
        c.name.isEmpty ? c.strip.footLabel : "\(c.name) (\(c.strip.footLabel))"
    }

    static func issues(_ channels: [Channel], mainClipped: Bool) -> [Issue] {
        var out: [Issue] = []
        if mainClipped {
            out.append(Issue(id: "main-clip", strip: .mainLR, severity: .problem,
                             title: "Main LR has hit 0 dB",
                             detail: "The PA feed clipped. Pull the main fader or the loudest channels down a little.",
                             fix: nil))
        }
        for c in channels {
            let who = label(c)
            let inUse = !c.name.isEmpty || (c.recentPeak ?? -90) > -70
            let open = !c.muted && c.faderDB > -40
            if c.clipped && c.hasHeadamp {
                out.append(Issue(id: "clip-\(c.strip.id)", strip: c.strip, severity: .problem,
                                 title: "\(who) is clipping at the preamp",
                                 detail: "The input reached 0 dBFS, which distorts everything after it. Turn the gain down until the loudest moments peak around -12.",
                                 fix: .autoGain))
            } else if let peak = c.recentPeak, inUse, open, c.hasHeadamp, peak > -70, peak < -36 {
                out.append(Issue(id: "quiet-\(c.strip.id)", strip: c.strip, severity: .check,
                                 title: "\(who) is coming in quiet",
                                 detail: String(format: "Loudest in the last minute was %.0f dBFS. More preamp gain (and less fader) keeps it clear of noise.", peak),
                                 fix: .autoGain))
            }
            if !c.name.isEmpty, open, let peak = c.recentPeak, peak <= -70 {
                out.append(Issue(id: "silent-\(c.strip.id)", strip: c.strip, severity: .check,
                                 title: "Nothing on \(who)",
                                 detail: "It's up in the mix but there's been no signal for a minute. Check the mic, cable, patch and 48V, or mute it so it can't add noise.",
                                 fix: .changes([c.strip.onPath: .int(0)], label: "Mute")))
            }
            if c.name.isEmpty && open && c.faderDB > -20, let peak = c.recentPeak, peak <= -70 {
                out.append(Issue(id: "unused-\(c.strip.id)", strip: c.strip, severity: .check,
                                 title: "\(c.strip.footLabel) is up with nothing on it",
                                 detail: "An open, unused channel only adds noise and hum to the mix.",
                                 fix: .changes([c.strip.onPath: .int(0)], label: "Mute")))
            }
            if isVoice(c.name), c.lowCutOn == false {
                out.append(Issue(id: "lowcut-\(c.strip.id)", strip: c.strip, severity: .problem,
                                 title: "\(who) has no low cut",
                                 detail: "Voices have nothing useful below about 100 Hz, just handling noise, stage rumble and pops.",
                                 fix: .changes([c.strip.preampPath("hpon"): .int(1),
                                                c.strip.preampPath("hpf"): RingOut.arg(Specs.hpf, 100)], label: "Low cut at 100 Hz")))
            }
            if c.eqOn, let boost = c.eq.filter({ $0.type >= 1 && $0.type <= 4 }).max(by: { $0.gain < $1.gain }), boost.gain >= 9 {
                out.append(Issue(id: "boost-\(c.strip.id)", strip: c.strip, severity: .check,
                                 title: String(format: "%@ has a big EQ boost (+%.0f dB at %@)", who, boost.gain, RingOut.label(boost.hz)),
                                 detail: "Big boosts are where feedback starts. Cutting what's in the way usually sounds better than boosting what's missing.",
                                 fix: .open("eq")))
            }
            if c.compOn && c.compReduction >= 15 {
                out.append(Issue(id: "squash-\(c.strip.id)", strip: c.strip, severity: .check,
                                 title: String(format: "%@ compressor is pulling %.0f dB", who, c.compReduction),
                                 detail: "That much squashes the life out of it. Raise the threshold or lower the ratio.",
                                 fix: .open("comp")))
            }
            if open && c.faderDB > 5 && c.hasHeadamp {
                out.append(Issue(id: "hotfader-\(c.strip.id)", strip: c.strip, severity: .check,
                                 title: String(format: "%@ fader is at +%.0f dB", who, c.faderDB),
                                 detail: "Faders work best around 0 dB. If it needs to be that high, the preamp gain is probably too low.",
                                 fix: .autoGain))
            }
        }
        return out.sorted { a, b in a.severity == b.severity ? false : a.severity < b.severity }
    }
}

/// Keeps the loudest preamp level of each channel over the last minute.
struct PeakTracker {
    private var windows: [StripID: [(t: TimeInterval, db: Float)]] = [:]
    private var started: [StripID: TimeInterval] = [:]
    var window: TimeInterval = 60

    mutating func add(_ strip: StripID, _ db: Float, at t: TimeInterval) {
        if started[strip] == nil { started[strip] = t }
        // Called 20 times a second for 32 channels: change the stored array in place (no copies).
        // One sample a second is plenty: keep the loudest in each second.
        if let last = windows[strip]?.last, t - last.t < 1 {
            if db > last.db {
                let i = windows[strip]!.count - 1
                windows[strip]![i].db = db
            }
            return
        }
        windows[strip, default: []].append((t, db))
        // Samples are in time order, so anything too old is at the front.
        while let first = windows[strip]?.first, t - first.t > window {
            windows[strip]!.removeFirst()
        }
    }

    /// nil until a few seconds have been watched.
    func peak(_ strip: StripID, now t: TimeInterval) -> Float? {
        guard let w = windows[strip], let since = started[strip], t - since >= 5, !w.isEmpty else { return nil }
        return w.reduce(-Float.infinity) { max($0, $1.db) }
    }
}
