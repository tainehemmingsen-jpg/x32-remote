import Foundation

// DiGiCo-style snapshots: stored desk values the app recalls itself (they are not X32 scenes).
//
// A snapshot always captures every strip and every parameter type, so its scope can be widened
// later without storing it again. Recall sends only what is inside the snapshot's scope, minus the
// show's recall safes, and only what differs from the desk now.

/// A stored set of desk values with a name, a scope and a fade time.
struct Snapshot: Codable, Identifiable, Equatable {
    /// The kinds of parameter a snapshot can recall.
    enum ParamType: String, Codable, CaseIterable, Identifiable, Hashable {
        case fader, mute, pan, sends, eq, gate, dyn, preamp, names, groups

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fader: return "Faders"
            case .mute: return "Mutes"
            case .pan: return "Pan"
            case .sends: return "Sends"
            case .eq: return "EQ"
            case .gate: return "Gate"
            case .dyn: return "Compressor"
            case .preamp: return "Preamp"
            case .names: return "Name & colour"
            case .groups: return "DCA & mute groups"
            }
        }

        /// Lower-case word used in summaries ("faders and mutes only").
        var summaryWord: String {
            switch self {
            case .fader: return "faders"
            case .mute: return "mutes"
            case .pan: return "pan"
            case .sends: return "sends"
            case .eq: return "EQ"
            case .gate: return "gates"
            case .dyn: return "compressors"
            case .preamp: return "preamps"
            case .names: return "names"
            case .groups: return "groups"
            }
        }

        /// What a new snapshot recalls: everything but preamps and names/colours.
        static let defaultSet: Set<ParamType> = Set(allCases).subtracting([.preamp, .names])
    }

    var id = UUID()
    var name: String
    /// 1-based position in its show (kept up to date by `SnapshotShow`).
    var number: Int = 0
    var notes: String = ""
    /// Seconds; 0 = snap.
    var fadeTime: Double = 0
    var scope = RecallScope()
    /// Every captured value, by OSC address.
    var values: [String: OSCArg] = [:]
    /// The headamp (0-127) feeding each input strip when captured, by strip id ("channel-5").
    /// Preamp gain and 48V belong to the headamp, so recall needs to know which one was stored.
    var headamps: [String: Int] = [:]
    var captured = Date()

    init(name: String, number: Int = 0, notes: String = "", fadeTime: Double = 0, scope: RecallScope = RecallScope(),
         values: [String: OSCArg] = [:], headamps: [String: Int] = [:], captured: Date = Date()) {
        self.name = name
        self.number = number
        self.notes = notes
        self.fadeTime = fadeTime
        self.scope = scope
        self.values = values
        self.headamps = headamps
        self.captured = captured
    }

    private enum CodingKeys: String, CodingKey { case id, name, number, notes, fadeTime, scope, values, headamps, captured }

    // Lenient decoding: fields added later get their defaults instead of losing the snapshot.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Snapshot"
        number = try c.decodeIfPresent(Int.self, forKey: .number) ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        fadeTime = try c.decodeIfPresent(Double.self, forKey: .fadeTime) ?? 0
        scope = try c.decodeIfPresent(RecallScope.self, forKey: .scope) ?? RecallScope()
        values = try c.decodeIfPresent([String: OSCArg].self, forKey: .values) ?? [:]
        headamps = try c.decodeIfPresent([String: Int].self, forKey: .headamps) ?? [:]
        captured = try c.decodeIfPresent(Date.self, forKey: .captured) ?? Date()
    }

    var isSnap: Bool { fadeTime <= 0 }

    /// Short description for list rows, e.g. "All strips · no preamps".
    var summary: String { scope.summary }

    // MARK: Addresses

    private static let gateFields = ["on", "mode", "thr", "range", "attack", "hold", "release", "keysrc",
                                     "filter/on", "filter/type", "filter/f"]

    /// The OSC addresses `type` covers on `strip` (only ones that exist on that kind of strip).
    /// Preamp gain and 48V live on the headamp: pass `headamp` (0-127) to include them.
    static func addresses(for strip: StripID, type: ParamType, headamp: Int? = nil) -> [String] {
        switch type {
        case .fader:
            return [strip.faderPath]
        case .mute:
            return [strip.onPath]
        case .pan:
            return strip.panPath.map { [$0] } ?? []
        case .sends:
            guard strip.sendCount > 0 else { return [] }
            var a: [String] = []
            for n in 1...strip.sendCount {
                a.append(strip.sendLevelPath(n))
                a.append(strip.sendOnPath(n))
                // Send pan lives on the odd send of each pair.
                if n % 2 == 1 { a.append(strip.sendPanPath(n)) }
            }
            return a
        case .eq:
            return strip.relativePaths(.eq).map { strip.base + $0 }
        case .gate:
            return strip.relativePaths(.gate).map { strip.base + $0 }
        case .dyn:
            return strip.relativePaths(.comp).map { strip.base + $0 }
        case .preamp:
            var a: [String] = []
            if strip.hasTrim { a.append(strip.preampPath("trim")) }
            if strip.hasPolarity { a.append(strip.preampPath("invert")) }
            if strip.hasHighPass { a += ["hpon", "hpf", "hpslope"].map { strip.preampPath($0) } }
            if let ha = headamp, strip.headampIndexPath != nil, (0..<128).contains(ha) {
                a += [StripID.headampGainPath(ha), StripID.headampPhantomPath(ha)]
            }
            return a
        case .names:
            return [strip.namePath, strip.colorPath]
        case .groups:
            // Only channels, aux ins, FX returns and mix buses have /grp on the X32.
            guard strip.isBusSource || strip.kind == .bus, let d = strip.dcaGroupsPath, let m = strip.muteGroupsPath else { return [] }
            return [d, m]
        }
    }

    /// Every address a snapshot can store, for every strip, without headamp gain/48V; plus the
    /// /-ha/NN/index paths, so the app learns which headamps feed the inputs. Request these from
    /// the desk before capturing (the app already asks for a headamp's gain and 48V when its
    /// index arrives), or use `allAddresses(headamp:)` once the indices are known.
    static func allAddresses() -> [String] {
        var a: [String] = []
        for strip in StripID.everything {
            for type in ParamType.allCases { a += addresses(for: strip, type: type) }
            if let ha = strip.headampIndexPath { a.append(ha) }
        }
        return a
    }

    /// Like `allAddresses()`, with each input's headamp gain and 48V (from its known headamp index).
    static func allAddresses(headamp: (StripID) -> Int?) -> [String] {
        var a: [String] = []
        var seen = Set<String>()
        for strip in StripID.everything {
            for type in ParamType.allCases {
                for p in addresses(for: strip, type: type, headamp: headamp(strip)) where seen.insert(p).inserted { a.append(p) }
            }
            if let ha = strip.headampIndexPath, seen.insert(ha).inserted { a.append(ha) }
        }
        return a
    }

    /// The headamp feeding `strip` according to `value`, if it is an input with a valid index.
    static func headamp(of strip: StripID, value: (String) -> OSCArg?) -> Int? {
        guard let p = strip.headampIndexPath, let ha = value(p)?.intValue, (0..<128).contains(ha) else { return nil }
        return ha
    }

    // MARK: Capture

    /// A new snapshot holding every value `value` knows, for `strips` and `types` (default: all).
    static func capture(name: String, scope: RecallScope = RecallScope(), fadeTime: Double = 0,
                        strips: [StripID] = StripID.everything, types: [ParamType] = ParamType.allCases,
                        value: (String) -> OSCArg?) -> Snapshot {
        var s = Snapshot(name: name, fadeTime: fadeTime, scope: scope)
        s.recapture(strips: strips, types: types, value: value)
        return s
    }

    /// Stores the current values again (keeping name, scope, notes and fade). Values for strips or
    /// types not listed are kept as they were.
    mutating func recapture(strips: [StripID] = StripID.everything, types: [ParamType] = ParamType.allCases,
                            value: (String) -> OSCArg?) {
        for strip in strips {
            let ha = Snapshot.headamp(of: strip, value: value)
            if types.contains(.preamp) {
                // Forget the old headamp's values for this strip; they are re-read below.
                if let old = headamps[strip.id], old != ha {
                    for p in [StripID.headampGainPath(old), StripID.headampPhantomPath(old)] where !headampInUse(old, except: strip) {
                        values[p] = nil
                    }
                }
                headamps[strip.id] = ha
            }
            for type in types {
                for address in Snapshot.addresses(for: strip, type: type, headamp: ha) {
                    if let v = value(address) { values[address] = v }
                }
            }
        }
        captured = Date()
    }

    private func headampInUse(_ ha: Int, except strip: StripID) -> Bool {
        headamps.contains { $0.key != strip.id && $0.value == ha }
    }

    // MARK: Recall

    /// What to send to recall this snapshot with its own scope.
    func changes(safes: RecallSafes = RecallSafes(), current: (String) -> OSCArg?) -> [(String, OSCArg)] {
        changes(scope: scope, safes: safes, current: current)
    }

    /// What to send to recall this snapshot: values inside `effective` (strips and types), minus the
    /// recall safes, that differ from `current`. Everything but faders comes first, faders last.
    /// Preamp gain/48V go to the headamp that feeds the strip now (stored from the one captured).
    func changes(scope effective: RecallScope, safes: RecallSafes = RecallSafes(),
                 current: (String) -> OSCArg?) -> [(String, OSCArg)] {
        var first: [(String, OSCArg)] = []
        var faders: [(String, OSCArg)] = []
        var seen = Set<String>()

        // Headamps feeding a strip whose preamp is safe are never touched, even through another
        // strip patched to the same input.
        var safeHeadamps = Set<Int>()
        for strip in StripID.everything where strip.headampIndexPath != nil && safes.isSafe(strip, .preamp) {
            if let ha = Snapshot.headamp(of: strip, value: current) ?? headamps[strip.id] { safeHeadamps.insert(ha) }
        }

        func add(_ address: String, _ v: OSCArg, fader: Bool) {
            guard seen.insert(address).inserted else { return }
            if let now = current(address), Snapshot.same(now, v) { return }
            if fader { faders.append((address, v)) } else { first.append((address, v)) }
        }

        for strip in StripID.everything where effective.strips.contains(strip) {
            for type in ParamType.allCases where effective.types.contains(type) && !safes.isSafe(strip, type) {
                for address in Snapshot.addresses(for: strip, type: type) {
                    guard let v = values[address] else { continue }
                    add(address, v, fader: type == .fader)
                }
                if type == .preamp, let stored = headamps[strip.id] {
                    let target = Snapshot.headamp(of: strip, value: current) ?? stored
                    guard !safeHeadamps.contains(target) else { continue }
                    let pairs = [(StripID.headampGainPath(stored), StripID.headampGainPath(target)),
                                 (StripID.headampPhantomPath(stored), StripID.headampPhantomPath(target))]
                    for (from, to) in pairs {
                        if let v = values[from] { add(to, v, fader: false) }
                    }
                }
            }
        }
        return first + faders
    }

    /// Recall split into what snaps now and what fades over `fadeTime` (faders and send levels).
    func recall(scope effective: RecallScope? = nil, safes: RecallSafes = RecallSafes(),
                current: (String) -> OSCArg?) -> SnapshotRecall {
        let all = changes(scope: effective ?? scope, safes: safes, current: current)
        guard fadeTime > 0 else { return SnapshotRecall(snaps: all, fades: [], duration: 0) }
        var snaps: [(String, OSCArg)] = []
        var late: [(String, OSCArg)] = []
        var fades: [SnapshotFade.Move] = []
        for (address, v) in all {
            if SnapshotFade.isFadeable(address), let to = v.floatValue {
                if let from = current(address)?.floatValue {
                    fades.append(SnapshotFade.Move(address: address, from: from, to: to))
                } else {
                    late.append((address, v))   // unknown start: just set it
                }
            } else {
                snaps.append((address, v))
            }
        }
        return SnapshotRecall(snaps: snaps + late, fades: fades, duration: fadeTime)
    }

    /// Equal for recall purposes (floats within a hair, since the desk quantises them).
    static func same(_ a: OSCArg, _ b: OSCArg) -> Bool {
        switch (a, b) {
        case (.float(let x), .float(let y)): return abs(x - y) < 0.00001
        case (.int(let x), .float(let y)), (.float(let y), .int(let x)): return abs(Float(x) - y) < 0.00001
        default: return a == b
        }
    }
}

// MARK: - Scope and safes

/// Which strips and parameter types a snapshot recalls.
struct RecallScope: Codable, Equatable {
    var strips: Set<StripID>
    var types: Set<Snapshot.ParamType>

    /// Default for a new snapshot: all strips, all types except preamp and name & colour.
    init(strips: Set<StripID> = Set(StripID.everything), types: Set<Snapshot.ParamType> = Snapshot.ParamType.defaultSet) {
        self.strips = strips
        self.types = types
    }

    static let everything = RecallScope(strips: Set(StripID.everything), types: Set(Snapshot.ParamType.allCases))

    func includes(_ strip: StripID, _ type: Snapshot.ParamType) -> Bool {
        strips.contains(strip) && types.contains(type)
    }

    /// e.g. "All strips · no preamps", "Ch 1–8, 12 · faders and mutes only".
    var summary: String { stripSummary + " · " + typeSummary }

    var stripSummary: String {
        if strips.isEmpty { return "No strips" }
        if strips.count == StripID.everything.count { return "All strips" }
        var parts: [String] = []
        for kind in StripKind.allCases {
            let ns = strips.filter { $0.kind == kind }.map(\.index).sorted()
            guard !ns.isEmpty else { continue }
            switch kind {
            case .main: parts.append("LR")
            case .mono: parts.append("M/C")
            default: parts.append(RecallScope.prefix(kind) + " " + RecallScope.ranges(ns))
            }
        }
        return parts.joined(separator: ", ")
    }

    var typeSummary: String {
        let all = Set(Snapshot.ParamType.allCases)
        if types.isEmpty { return "nothing" }
        if types == all { return "everything" }
        let ordered = Snapshot.ParamType.allCases.filter { types.contains($0) }
        if types.count <= 3 { return RecallScope.list(ordered.map(\.summaryWord)) + " only" }
        // Names are off by default, so leaving them out goes unsaid.
        let missing = Snapshot.ParamType.allCases.filter { !types.contains($0) && $0 != .names }
        if missing.isEmpty { return "all but names" }
        if missing.count <= 3 {
            let text = "no " + RecallScope.list(missing.map(\.summaryWord), conjunction: "or")
            return types.contains(.names) ? text + ", with names" : text
        }
        return RecallScope.list(ordered.map(\.summaryWord))
    }

    private static func prefix(_ kind: StripKind) -> String {
        switch kind {
        case .channel: return "Ch"
        case .auxIn: return "Aux"
        case .fxReturn: return "FX"
        case .bus: return "Bus"
        case .matrix: return "Mtx"
        case .main: return "LR"
        case .mono: return "M/C"
        case .dca: return "DCA"
        }
    }

    /// [1,2,3,4,12] -> "1–4, 12".
    static func ranges(_ ns: [Int]) -> String {
        var out: [String] = []
        var i = 0
        while i < ns.count {
            var j = i
            while j + 1 < ns.count && ns[j + 1] == ns[j] + 1 { j += 1 }
            out.append(j > i ? "\(ns[i])–\(ns[j])" : "\(ns[i])")
            i = j + 1
        }
        return out.joined(separator: ", ")
    }

    static func list(_ words: [String], conjunction: String = "and") -> String {
        switch words.count {
        case 0: return ""
        case 1: return words[0]
        default: return words.dropLast().joined(separator: ", ") + " \(conjunction) " + words.last!
        }
    }
}

/// Strips and parameter types no snapshot ever changes (e.g. the lectern mic, or all preamps).
struct RecallSafes: Codable, Equatable {
    /// Strips that are completely safe.
    var strips: Set<StripID> = []
    /// Types safe on every strip.
    var types: Set<Snapshot.ParamType> = []
    /// Types safe on one strip, by strip id ("channel-5" -> [.preamp]).
    var stripTypes: [String: Set<Snapshot.ParamType>] = [:]

    init(strips: Set<StripID> = [], types: Set<Snapshot.ParamType> = [], stripTypes: [String: Set<Snapshot.ParamType>] = [:]) {
        self.strips = strips
        self.types = types
        self.stripTypes = stripTypes
    }

    var isEmpty: Bool { strips.isEmpty && types.isEmpty && stripTypes.values.allSatisfy(\.isEmpty) }

    func isSafe(_ strip: StripID, _ type: Snapshot.ParamType) -> Bool {
        strips.contains(strip) || types.contains(type) || stripTypes[strip.id]?.contains(type) == true
    }

    /// Whether anything on the strip is safe (for a badge on the strip).
    func hasSafe(_ strip: StripID) -> Bool {
        strips.contains(strip) || !types.isEmpty || stripTypes[strip.id]?.isEmpty == false
    }

    mutating func setSafe(_ strip: StripID, _ type: Snapshot.ParamType, _ safe: Bool) {
        var set = stripTypes[strip.id] ?? []
        if safe { set.insert(type) } else { set.remove(type) }
        stripTypes[strip.id] = set.isEmpty ? nil : set
    }
}

// MARK: - Fades

/// The result of recalling a snapshot: send `snaps` at once, then step `fades` over `duration`.
struct SnapshotRecall {
    var snaps: [(String, OSCArg)]
    var fades: [SnapshotFade.Move]
    var duration: Double

    var isEmpty: Bool { snaps.isEmpty && fades.isEmpty }
}

enum SnapshotFade {
    /// Floor used for -∞ so a fade from silence has somewhere to start (the X32's own bottom).
    static let floorDB: Float = -90
    /// Suggested time between fade steps.
    static let frameInterval: Double = 0.05

    struct Move: Equatable {
        var address: String
        var from: Float
        var to: Float
    }

    /// Faders (strips and DCAs) and send levels fade; everything else snaps.
    static func isFadeable(_ address: String) -> Bool {
        address.hasSuffix("/fader") || (address.hasSuffix("/level") && address.contains("/mix/"))
    }

    /// Fader position (0...1) at `elapsed` seconds into a fade of `duration`, moving linearly in dB.
    static func value(from: Float, to: Float, elapsed: Double, duration: Double) -> Float {
        guard duration > 0, elapsed < duration else { return to }
        guard elapsed > 0 else { return from }
        let p = Float(elapsed / duration)
        let a = max(X32Math.faderToDB(from), floorDB)
        let b = max(X32Math.faderToDB(to), floorDB)
        return X32Math.dbToFader(a + (b - a) * p)
    }

    /// Every move's value at `elapsed`, quantised like the desk (exact targets once finished).
    static func frame(_ moves: [Move], elapsed: Double, duration: Double) -> [(String, OSCArg)] {
        let done = elapsed >= duration
        return moves.map { m in
            let v = value(from: m.from, to: m.to, elapsed: elapsed, duration: duration)
            return (m.address, .float(done || m.from == m.to ? m.to : X32Math.quantize(v, steps: 1023)))
        }
    }

    /// Steps a fade, returning only values that changed since the last step (keeps OSC traffic down).
    struct Run {
        let moves: [Move]
        let duration: Double
        private var last: [String: Float] = [:]
        private(set) var isFinished = false

        init(moves: [Move], duration: Double) {
            self.moves = moves
            self.duration = duration
            for m in moves { last[m.address] = m.from }
            if moves.isEmpty { isFinished = true }
        }

        mutating func step(elapsed: Double) -> [(String, OSCArg)] {
            guard !isFinished else { return [] }
            var out: [(String, OSCArg)] = []
            for (address, arg) in SnapshotFade.frame(moves, elapsed: elapsed, duration: duration) {
                guard let f = arg.floatValue else { continue }
                if last[address] != f {
                    last[address] = f
                    out.append((address, arg))
                }
            }
            if elapsed >= duration { isFinished = true }
            return out
        }
    }
}

// MARK: - Show (ordered list of snapshots)

/// An ordered list of snapshots with a current position and the recall safes that apply to all.
struct SnapshotShow: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    private(set) var snapshots: [Snapshot] = []
    /// The snapshot last recalled (or selected); nil before the first.
    var currentIndex: Int? {
        didSet {
            if let c = currentIndex, !snapshots.indices.contains(c) { currentIndex = snapshots.isEmpty ? nil : min(max(c, 0), snapshots.count - 1) }
        }
    }
    var safes = RecallSafes()

    init(name: String, snapshots: [Snapshot] = [], currentIndex: Int? = nil, safes: RecallSafes = RecallSafes()) {
        self.name = name
        self.snapshots = snapshots
        self.currentIndex = currentIndex
        self.safes = safes
        renumber()
    }

    private enum CodingKeys: String, CodingKey { case id, name, snapshots, currentIndex, safes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Show"
        snapshots = try c.decodeIfPresent([Snapshot].self, forKey: .snapshots) ?? []
        let i = try c.decodeIfPresent(Int.self, forKey: .currentIndex)
        currentIndex = i.flatMap { snapshots.indices.contains($0) ? $0 : nil }
        safes = try c.decodeIfPresent(RecallSafes.self, forKey: .safes) ?? RecallSafes()
    }

    var count: Int { snapshots.count }
    var current: Snapshot? { currentIndex.map { snapshots[$0] } }

    subscript(index: Int) -> Snapshot {
        get { snapshots[index] }
        set { snapshots[index] = newValue; renumber() }
    }

    func index(of id: UUID) -> Int? { snapshots.firstIndex { $0.id == id } }

    /// The snapshot GO / next would recall: the first one before anything is recalled, nil at the end.
    var nextIndex: Int? {
        guard !snapshots.isEmpty else { return nil }
        guard let c = currentIndex else { return 0 }
        return c + 1 < snapshots.count ? c + 1 : nil
    }

    /// The one before the current, nil at the start.
    var previousIndex: Int? {
        guard let c = currentIndex, c > 0 else { return nil }
        return c - 1
    }

    /// A name for a new snapshot, "Snapshot N".
    var nextDefaultName: String { "Snapshot \(snapshots.count + 1)" }

    /// Inserts after the current snapshot (or at the end with none) and makes it current.
    @discardableResult
    mutating func insertAfterCurrent(_ snapshot: Snapshot) -> Int {
        let i = currentIndex.map { $0 + 1 } ?? snapshots.count
        snapshots.insert(snapshot, at: i)
        renumber()
        currentIndex = i
        return i
    }

    /// Adds at the end without changing the current snapshot.
    @discardableResult
    mutating func append(_ snapshot: Snapshot) -> Int {
        snapshots.append(snapshot)
        renumber()
        return snapshots.count - 1
    }

    /// A copy right after the original, made current.
    @discardableResult
    mutating func duplicate(at index: Int) -> Int? {
        guard snapshots.indices.contains(index) else { return nil }
        var copy = snapshots[index]
        copy.id = UUID()
        copy.name += " copy"
        snapshots.insert(copy, at: index + 1)
        renumber()
        currentIndex = index + 1
        return index + 1
    }

    /// Removes a snapshot. If it was current, the one before becomes current, so next still goes
    /// to what followed it.
    mutating func delete(at index: Int) {
        guard snapshots.indices.contains(index) else { return }
        snapshots.remove(at: index)
        renumber()
        guard let c = currentIndex else { return }
        if snapshots.isEmpty { currentIndex = nil }
        else if c == index { currentIndex = index > 0 ? index - 1 : nil }
        else if c > index { currentIndex = c - 1 }
    }

    /// Moves a snapshot so it ends up at `destination`; the current snapshot stays current.
    mutating func move(from source: Int, to destination: Int) {
        guard snapshots.indices.contains(source) else { return }
        let currentID = current?.id
        let s = snapshots.remove(at: source)
        snapshots.insert(s, at: min(max(destination, 0), snapshots.count))
        renumber()
        currentIndex = currentID.flatMap { index(of: $0) }
    }

    /// SwiftUI List `onMove` semantics.
    mutating func move(fromOffsets offsets: IndexSet, toOffset: Int) {
        let currentID = current?.id
        let moving = offsets.filter { snapshots.indices.contains($0) }.map { snapshots[$0] }
        let before = offsets.filter { $0 < toOffset }.count
        for i in offsets.sorted(by: >) where snapshots.indices.contains(i) { snapshots.remove(at: i) }
        snapshots.insert(contentsOf: moving, at: min(max(toOffset - before, 0), snapshots.count))
        renumber()
        currentIndex = currentID.flatMap { index(of: $0) }
    }

    mutating func rename(at index: Int, to name: String) {
        guard snapshots.indices.contains(index) else { return }
        snapshots[index].name = name
    }

    /// Re-captures the desk into an existing snapshot, keeping its name, scope, notes and fade.
    mutating func update(at index: Int, value: (String) -> OSCArg?) {
        guard snapshots.indices.contains(index) else { return }
        snapshots[index].recapture(value: value)
    }

    /// What recalling snapshot `index` does now, with the show's safes. Set `currentIndex` once sent.
    func recall(at index: Int, scope: RecallScope? = nil, current: (String) -> OSCArg?) -> SnapshotRecall? {
        guard snapshots.indices.contains(index) else { return nil }
        return snapshots[index].recall(scope: scope, safes: safes, current: current)
    }

    private mutating func renumber() {
        for i in snapshots.indices { snapshots[i].number = i + 1 }
    }
}

// MARK: - Storage

/// Snapshot shows live in the app's own storage. A full snapshot is a few hundred KB of JSON, so
/// for big shows the app may prefer `encode`/`decode` with a file over UserDefaults.
enum SnapshotStore {
    static let key = "X32Remote.snapshots.v1"

    static func load(_ defaults: UserDefaults = .standard) -> [SnapshotShow] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let shows = decode(data) else {
            // Keep the unreadable store rather than letting the next save overwrite it.
            if defaults.data(forKey: key + ".backup") == nil { defaults.set(data, forKey: key + ".backup") }
            return []
        }
        return shows
    }

    static func save(_ shows: [SnapshotShow], _ defaults: UserDefaults = .standard) {
        if let data = encode(shows) { defaults.set(data, forKey: key) }
    }

    /// One show by id, or the first one saved when `id` is nil.
    static func loadShow(id: UUID? = nil, _ defaults: UserDefaults = .standard) -> SnapshotShow? {
        let shows = load(defaults)
        guard let id else { return shows.first }
        return shows.first { $0.id == id }
    }

    /// Saves one show, replacing the stored show with the same id (or adding it).
    static func saveShow(_ show: SnapshotShow, _ defaults: UserDefaults = .standard) {
        var shows = load(defaults)
        if let i = shows.firstIndex(where: { $0.id == show.id }) { shows[i] = show } else { shows.append(show) }
        save(shows, defaults)
    }

    static func encode(_ shows: [SnapshotShow]) -> Data? { try? JSONEncoder().encode(shows) }

    static func decode(_ data: Data) -> [SnapshotShow]? { try? JSONDecoder().decode([SnapshotShow].self, from: data) }
}
