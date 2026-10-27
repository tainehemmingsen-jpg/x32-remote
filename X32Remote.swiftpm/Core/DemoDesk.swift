import Foundation

/// A simulated X32 that lives inside the app, so every screen can be tried without a console.
/// It answers OSC exactly like the real desk does: gets, sets, /xinfo, /meters and scene recall.
final class DemoTransport: X32Transport {
    var onMessage: ((OSCMessage) -> Void)?
    var displayAddress: String { "Demo desk" }

    private var values: [String: OSCArg] = [:]
    private var meterExpiry: [Int: TimeInterval] = [:]
    private var timer: Timer?
    private var tickCount: Double = 0
    private var envelope: [Float] = Array(repeating: 0, count: 48)

    init() {
        seed()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.meterTick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit {
        timer?.invalidate()
    }

    func send(_ message: OSCMessage) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.003) { [weak self] in
            self?.handle(message)
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        onMessage = nil
    }

    // MARK: - Protocol handling

    private func reply(_ message: OSCMessage) {
        onMessage?(message)
    }

    private func handle(_ message: OSCMessage) {
        let address = message.address
        switch address {
        case "/xinfo":
            reply(OSCMessage("/xinfo", [.string("0.0.0.0"), .string("Demo X32"), .string("X32"), .string("4.06")]))
            return
        case "/info":
            reply(OSCMessage("/info", [.string("V2.07"), .string("Demo X32"), .string("X32"), .string("4.06")]))
            return
        case "/status":
            reply(OSCMessage("/status", [.string("active"), .string("0.0.0.0"), .string("Demo X32")]))
            return
        case "/xremote":
            return
        case "/meters":
            if case .string(let name)? = message.args.first, let block = Int(name.replacingOccurrences(of: "/meters/", with: "")) {
                meterExpiry[block] = X32Client.now() + 10
            }
            return
        case "/-action/goscene":
            if let n = message.args.first?.intValue {
                recallScene(n)
            }
            return
        case "/-action/gocue":
            if let n = message.args.first?.intValue, (0..<Show.Control.cues.count).contains(n) {
                if let scene = Show.cueScene(scene: int(Show.cuePath(n, "scene"))) {
                    recallScene(scene)
                }
                if int(Show.controlPath) == Show.Control.cues.rawValue { change(Show.currentPath, .int(Int32(n))) }
            }
            return
        case "/-action/gosnippet":
            if let n = message.args.first?.intValue, (0..<100).contains(n) {
                if int(Show.controlPath) == Show.Control.snippets.rawValue { change(Show.currentPath, .int(Int32(n))) }
            }
            return
        case "/save":
            // /save ,siss scene <n> <name> <note>
            if message.args.count >= 3, case .string(let kind) = message.args[0], kind == "scene",
               let n = message.args[1].intValue, case .string(let name) = message.args[2] {
                change(String(format: "/-show/showfile/scene/%03d/name", n), .string(name))
                change(String(format: "/-show/showfile/scene/%03d/hasdata", n), .int(1))
                reply(OSCMessage("/save", [.string("scene"), .int(1)]))
            }
            return
        case "/-action/clearsolo":
            for n in 1...80 {
                change(String(format: "/-stat/solosw/%02d", n), .int(0))
            }
            change("/-stat/solo", .int(0))
            return
        default:
            break
        }

        if message.args.isEmpty {
            if let v = values[address] ?? effectDefault(address) ?? DemoTransport.defaultValue(for: address) {
                reply(OSCMessage(address, [v]))
            }
        } else {
            values[address] = message.args[0]
            if address.hasPrefix("/fx/") && address.hasSuffix("/type") {
                // A new effect starts from its defaults.
                let prefix = String(address.dropLast("type".count)) + "par/"
                values = values.filter { !$0.key.hasPrefix(prefix) }
            }
            // Like the real desk, a change to one side of a linked pair moves the other side too.
            // (Pan isn't copied: a linked pair keeps its left/right spread.)
            if !address.hasSuffix("/pan"), let partner = LinkSync.partnerAddress(for: address, isLinked: { s in s.linkPath.map { self.int($0) != 0 } ?? false }) {
                values[partner] = message.args[0]
            }
            if address.hasPrefix("/-stat/solosw/") {
                let anySolo = (1...80).contains { n in
                    (values[String(format: "/-stat/solosw/%02d", n)]?.intValue ?? 0) != 0
                }
                change("/-stat/solo", .int(anySolo ? 1 : 0))
            }
        }
    }

    /// Change a value on the "desk" and tell the remote, like /xremote would.
    private func change(_ address: String, _ value: OSCArg) {
        values[address] = value
        reply(OSCMessage(address, [value]))
    }

    private func float(_ address: String) -> Float {
        values[address]?.floatValue ?? DemoTransport.defaultValue(for: address)?.floatValue ?? 0
    }

    private func int(_ address: String) -> Int {
        values[address]?.intValue ?? DemoTransport.defaultValue(for: address)?.intValue ?? 0
    }

    // MARK: - Scenes

    private let sceneNames = ["Soundcheck", "Band set", "Acoustic set", "Speeches", "Walk-in music"]

    private func recallScene(_ n: Int) {
        guard n >= 0, n < sceneNames.count else { return }
        // The desk's position follows scenes only while its show control is set to scenes.
        if int(Show.controlPath) == Show.Control.scenes.rawValue { change(Show.currentPath, .int(Int32(n))) }
        let bandChannels = Array(1...21)
        switch n {
        case 3:
            for ch in bandChannels {
                change(String(format: "/ch/%02d/mix/on", ch), .int(0))
            }
            change("/ch/22/mix/on", .int(1))
            change("/ch/22/mix/fader", .float(X32Math.dbToFader(0)))
        case 4:
            for ch in 1...24 {
                change(String(format: "/ch/%02d/mix/on", ch), .int(0))
            }
            change("/auxin/01/mix/on", .int(1))
            change("/auxin/02/mix/on", .int(1))
            change("/auxin/01/mix/fader", .float(X32Math.dbToFader(-5)))
            change("/auxin/02/mix/fader", .float(X32Math.dbToFader(-5)))
        case 2:
            for ch in bandChannels {
                change(String(format: "/ch/%02d/mix/on", ch), .int(ch >= 12 ? 1 : 0))
            }
        default:
            for ch in 1...24 {
                change(String(format: "/ch/%02d/mix/on", ch), .int(1))
            }
        }
    }

    // MARK: - Meters

    private func meterTick() {
        let now = X32Client.now()
        tickCount += 1
        let active = meterExpiry.filter { $0.value > now }.map { $0.key }
        guard !active.isEmpty, onMessage != nil else { return }

        // Input levels (pre-fader) for 32 channels + 8 aux + 8 fx returns.
        var inputs = [Float](repeating: 0, count: 48)
        for i in 0..<48 {
            inputs[i] = simulatedInput(i)
        }

        var gateGR = [Float](repeating: 1, count: 32)
        var dynGR = [Float](repeating: 1, count: 32)
        for ch in 0..<32 {
            let db = X32Math.amplitudeToDB(inputs[ch])
            if ch < 7 && db < -40 {
                gateGR[ch] = 0.1
            }
            if db > -20 && (ch == 0 || ch == 1 || ch == 15 || ch == 16 || ch == 7) {
                let reduction = min(12, (db + 20) * 0.6)
                dynGR[ch] = powf(10, -reduction / 20)
            }
        }

        // Post-fader contributions.
        var mainL: Float = 0
        var mainR: Float = 0
        var buses = [Float](repeating: 0, count: 16)
        let sources = StripID.busSources
        for (i, strip) in sources.enumerated() where i < 48 {
            let amp = inputs[i]
            if amp <= 0 || int(strip.onPath) == 0 { continue }
            let faderGain = dbGain(float(strip.faderPath))
            if int(strip.lrAssignPath ?? "") != 0 || strip.kind != .channel {
                let pan = float(strip.panPath ?? "")
                let post = amp * faderGain
                mainL += post * post * (1 - pan) * 2
                mainR += post * post * pan * 2
            }
            for bus in 1...16 where int(strip.sendOnPath(bus)) != 0 {
                let g = dbGain(float(strip.sendLevelPath(bus)))
                if g > 0 {
                    buses[bus - 1] = max(buses[bus - 1], amp * g)
                }
            }
        }
        let mainGain = int("/main/st/mix/on") != 0 ? dbGain(float("/main/st/mix/fader")) : 0
        let outL = sqrtf(mainL) * mainGain * 0.7
        let outR = sqrtf(mainR) * mainGain * 0.7
        for b in 0..<16 {
            let bus = StripID(.bus, b + 1)
            buses[b] *= int(bus.onPath) != 0 ? dbGain(float(bus.faderPath)) : 0
        }

        if active.contains(0) {
            var block = [Float](repeating: 0, count: 70)
            for i in 0..<48 {
                block[i] = inputs[i]
            }
            for b in 0..<16 {
                block[48 + b] = buses[b]
            }
            sendMeters(0, block)
        }
        if active.contains(1) {
            var block = [Float](repeating: 0, count: 96)
            for ch in 0..<32 {
                block[ch] = inputs[ch]
                block[32 + ch] = gateGR[ch]
                block[64 + ch] = dynGR[ch]
            }
            sendMeters(1, block)
        }
        if active.contains(2) {
            var block = [Float](repeating: 1, count: 49)
            for b in 0..<16 {
                block[b] = buses[b]
            }
            for m in 16..<22 {
                block[m] = 0
            }
            block[22] = outL
            block[23] = outR
            block[24] = 0
            sendMeters(2, block)
        }
        if active.contains(RTA.block) {
            let source = int(RTA.sourcePath)
            let amp: Float
            switch source {
            case 2...49: amp = inputs[source - 2]
            case 50...65: amp = buses[source - 50]
            case 72, 73: amp = max(outL, outR)
            default: amp = 0
            }
            var spectrum = demoSpectrum(level: amp, seed: source)
            addFeedback(&spectrum, source: source)
            reply(OSCMessage("/meters/\(RTA.block)", [.blob(RTA.encode(spectrum))]))
        }
    }

    /// Pushing a bus or the main mix above -8 dB makes it "ring" at two frequencies, like a
    /// wedge or PA feeding back, until its EQ has a cut there (so ring-out can be tried).
    private func addFeedback(_ spectrum: inout [Float], source: Int) {
        let strip: StripID
        switch source {
        case 50...65: strip = StripID(.bus, source - 49)
        case 72: strip = .mainLR
        default: return
        }
        let faderDB = X32Math.faderToDB(float(strip.faderPath))
        guard faderDB.isFinite, faderDB > -8, int(strip.onPath) != 0 else { return }
        let rings = [70 + source % 7, 44 + source % 5]
        for (n, band) in rings.enumerated() where band < spectrum.count {
            let hz = Float(RTA.frequency(band))
            var cut: Float = 0
            if int(strip.eqOnPath) != 0 {
                for b in 1...strip.eqBandCount {
                    let t = int(strip.eqPath(b, "type"))
                    guard t == 2 || t == 3 else { continue }
                    let f = Specs.eqFreq.value(float(strip.eqPath(b, "f")))
                    if abs(log2f(f / hz)) <= 1.0 / 6 { cut += min(0, Specs.eqGain.value(float(strip.eqPath(b, "g")))) }
                }
            }
            // The louder the output, the harder it rings; a 6 dB cut tames it.
            let strength = (faderDB + 8) * 2 + Float(n == 0 ? 14 : 10) + cut * 2.5
            guard strength > 0 else { continue }
            let peak = min(-6, -30 + strength)
            spectrum[band] = max(spectrum[band], peak)
            if band > 0 { spectrum[band - 1] = max(spectrum[band - 1], peak - 14) }
            if band + 1 < spectrum.count { spectrum[band + 1] = max(spectrum[band + 1], peak - 14) }
        }
    }

    /// A moving, roughly pink spectrum with a couple of resonances (different per source).
    private func demoSpectrum(level amp: Float, seed: Int) -> [Float] {
        let base = X32Math.amplitudeToDB(amp)
        let t = tickCount * 0.05
        guard base.isFinite, base > -80 else {
            // A running analyser on silence: a low, slightly moving floor.
            return (0..<RTA.bandCount).map { i in -92 + 1.5 * sinf(Float(t) * 2.3 + Float(i) * 0.9) }
        }
        let peak1 = 25 + (seed * 7) % 30
        let peak2 = 55 + (seed * 13) % 30
        return (0..<RTA.bandCount).map { i in
            let fi = Float(i)
            var db = base - 8 - 0.12 * abs(fi - 40)              // tilt away from ~150 Hz
            if i < 12 { db -= Float(12 - i) * 2.5 }               // low roll-off
            db += 6 * expf(-powf((fi - Float(peak1)) / 4, 2))
            db += 4 * expf(-powf((fi - Float(peak2)) / 6, 2))
            db += 2.5 * sinf(Float(t) * 3.1 + fi * 0.7) + 1.5 * sinf(Float(t) * 7.3 + fi * 1.9)
            return min(db, 0)
        }
    }

    private func sendMeters(_ block: Int, _ floats: [Float]) {
        reply(OSCMessage("/meters/\(block)", [.blob(MeterBlob.encode(floats))]))
    }

    private func dbGain(_ fader: Float) -> Float {
        let db = X32Math.faderToDB(fader)
        if db.isInfinite { return 0 }
        return powf(10, db / 20)
    }

    /// A believable, moving input level for source i (0-31 channels, 32-39 aux, 40-47 fx returns).
    private func simulatedInput(_ i: Int) -> Float {
        let t = tickCount * 0.05
        let seed = Double(i) * 1.37
        var db: Double
        switch i {
        case 0...4:
            // drums: hits
            let beat = (t * (i == 0 ? 2.0 : 4.0) + seed).truncatingRemainder(dividingBy: 1.0)
            db = beat < 0.08 ? -6 + 4 * sin(seed) : -55
        case 5, 6:
            db = -24 + 6 * sin(t * 3.1 + seed) + 3 * sin(t * 7.3)
        case 7, 8:
            db = -16 + 5 * sin(t * 1.7 + seed)
        case 9...14:
            db = -20 + 7 * sin(t * 0.9 + seed) + 2 * sin(t * 5.1 + seed)
        case 15...18:
            let phrase = sin(t * 0.35 + seed)
            db = phrase > -0.2 ? -14 + 6 * sin(t * 2.3 + seed) : -60
        case 19, 20:
            db = sin(t * 0.2 + seed) > 0.3 ? -18 + 5 * sin(t * 3 + seed) : -70
        case 21:
            db = -30 + 8 * sin(t * 0.5)
        case 22, 23:
            db = -70
        case 24...27:
            db = -22 + 3 * sin(t * 1.1 + seed)
        case 32, 33:
            db = -20 + 2 * sin(t * 0.8 + seed)
        case 40...47:
            db = -30 + 6 * sin(t * 0.6 + seed)
        default:
            db = -90
        }
        let jitter = Double.random(in: -1.5...1.5)
        let value = Float(db + jitter)
        let target = value <= -89 ? 0 : powf(10, value / 20)
        // Smooth decay so drum hits ring a little.
        envelope[i] = max(target, envelope[i] * 0.8)
        return envelope[i]
    }

    // MARK: - Initial desk state

    private func seed() {
        let channels: [(String, Int)] = [
            ("Kick", 1), ("Snare", 1), ("Hi-Hat", 1), ("Rack Tom", 1), ("Floor Tom", 1),
            ("OH L", 1), ("OH R", 1), ("Bass DI", 4), ("Bass Mic", 4), ("Gtr 1", 2),
            ("Gtr 2", 2), ("Acoustic", 2), ("Keys L", 3), ("Keys R", 3), ("Synth", 3),
            ("Lead Vox", 5), ("BV 1", 5), ("BV 2", 5), ("BV 3", 5), ("Sax", 6),
            ("Trumpet", 6), ("MC Mic", 7), ("Wireless 1", 7), ("Wireless 2", 7),
            ("Laptop L", 14), ("Laptop R", 14), ("Playback L", 14), ("Playback R", 14),
            ("Talkback", 15), ("", 0), ("", 0), ("", 0)
        ]
        let faderDB: [Float] = [-2, -4, -12, -8, -8, -10, -10, -3, -9, -6,
                                -7, -5, -8, -8, -11, 0, -6, -6, -7, -5,
                                -6, -2, -90, -90, -10, -10, -90, -90, -90, -90, -90, -90]
        let pans: [Float] = [0.5, 0.45, 0.35, 0.4, 0.62, 0.15, 0.85, 0.5, 0.5, 0.3,
                             0.7, 0.55, 0.0, 1.0, 0.6, 0.5, 0.35, 0.65, 0.5, 0.4,
                             0.6, 0.5, 0.5, 0.5, 0.0, 1.0, 0.0, 1.0, 0.5, 0.5, 0.5, 0.5]
        let dcaFor: [Int] = [1, 1, 1, 1, 1, 1, 1, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 5, 6, 6, 0, 0, 0, 8, 8, 8, 8, 0, 0, 0, 0]

        for (i, ch) in channels.enumerated() {
            let s = StripID(.channel, i + 1)
            values[s.namePath] = .string(ch.0)
            values[s.colorPath] = .int(Int32(ch.1))
            values[s.faderPath] = .float(X32Math.dbToFader(faderDB[i]))
            values[s.onPath] = .int(ch.0.isEmpty || i == 28 ? 0 : 1)
            values[s.panPath ?? ""] = .float(pans[i])
            values[s.dcaGroupsPath ?? ""] = .int(dcaFor[i] > 0 ? Int32(1 << (dcaFor[i] - 1)) : 0)
            values[s.preampPath("hpon")] = .int(i == 0 || i == 7 || i == 8 ? 0 : 1)
            values[s.preampPath("hpf")] = .float(X32Math.logInverse(i >= 15 && i <= 18 ? 120 : 80, 20, 400))
            values[String(format: "/headamp/%03d/gain", i)] = .float(X32Math.linInverse(i < 7 ? 22 : 34, -12, 60))
            values[String(format: "/headamp/%03d/phantom", i)] = .int((i >= 5 && i <= 6) || i == 11 ? 1 : 0)
        }

        // A characterful EQ and dynamics on the lead vocal and kick, so the graphs have something to show.
        let vox = StripID(.channel, 16)
        values[vox.eqOnPath] = .int(1)
        values[vox.eqPath(1, "type")] = .int(1)
        values[vox.eqPath(1, "f")] = .float(X32Math.logInverse(180, 20, 20000))
        values[vox.eqPath(1, "g")] = .float(X32Math.linInverse(-3, -15, 15))
        values[vox.eqPath(2, "f")] = .float(X32Math.logInverse(420, 20, 20000))
        values[vox.eqPath(2, "g")] = .float(X32Math.linInverse(-4.5, -15, 15))
        values[vox.eqPath(2, "q")] = .float(X32Math.logInverse(3, 10, 0.3))
        values[vox.eqPath(3, "f")] = .float(X32Math.logInverse(3200, 20, 20000))
        values[vox.eqPath(3, "g")] = .float(X32Math.linInverse(3, -15, 15))
        values[vox.eqPath(4, "type")] = .int(4)
        values[vox.eqPath(4, "f")] = .float(X32Math.logInverse(9000, 20, 20000))
        values[vox.eqPath(4, "g")] = .float(X32Math.linInverse(2, -15, 15))
        values[vox.dynPath("on")] = .int(1)
        values[vox.dynPath("thr")] = .float(X32Math.linInverse(-24, -60, 0))
        values[vox.dynPath("ratio")] = .int(6)
        values[vox.dynPath("mgain")] = .float(X32Math.linInverse(4, 0, 24))

        let kick = StripID(.channel, 1)
        values[kick.eqOnPath] = .int(1)
        values[kick.eqPath(1, "f")] = .float(X32Math.logInverse(62, 20, 20000))
        values[kick.eqPath(1, "g")] = .float(X32Math.linInverse(4, -15, 15))
        values[kick.eqPath(2, "f")] = .float(X32Math.logInverse(350, 20, 20000))
        values[kick.eqPath(2, "g")] = .float(X32Math.linInverse(-7, -15, 15))
        values[kick.eqPath(2, "q")] = .float(X32Math.logInverse(2.5, 10, 0.3))
        values[kick.eqPath(3, "f")] = .float(X32Math.logInverse(4000, 20, 20000))
        values[kick.eqPath(3, "g")] = .float(X32Math.linInverse(5, -15, 15))
        values[kick.gatePath("on")] = .int(1)
        values[kick.gatePath("mode")] = .int(3)
        values[kick.gatePath("thr")] = .float(X32Math.linInverse(-38, -80, 0))
        values[kick.dynPath("on")] = .int(1)
        values[kick.dynPath("thr")] = .float(X32Math.linInverse(-14, -60, 0))
        values[kick.dynPath("ratio")] = .int(5)

        // Stereo sources are linked pairs, like on a real desk.
        for path in ["/config/chlink/13-14", "/config/chlink/25-26", "/config/chlink/27-28", "/config/auxlink/1-2", "/config/auxlink/7-8"] {
            values[path] = .int(1)
        }

        // Typical processing elsewhere, so every strip's pictures look like a real show.
        let compOn: [Int] = [2, 4, 5, 8, 9, 10, 11, 12, 15, 17, 18, 19, 20, 21, 22]
        for n in compOn {
            let s = StripID(.channel, n)
            values[s.dynPath("on")] = .int(1)
            values[s.dynPath("thr")] = .float(X32Math.linInverse(Float(-12 - (n * 7) % 18), -60, 0))
            values[s.dynPath("ratio")] = .int(Int32(3 + n % 4))
        }
        for n in [2, 4, 5, 9] {
            let s = StripID(.channel, n)
            values[s.gatePath("on")] = .int(1)
            values[s.gatePath("thr")] = .float(X32Math.linInverse(Float(-34 - n * 2), -80, 0))
            values[s.gatePath("range")] = .float(X32Math.linInverse(Float(20 + n * 4), 3, 60))
        }
        let eqShapes: [Int: [(Int, Float, Float)]] = [
            2: [(2, 220, 3), (3, 900, -4), (4, 6000, 3)],
            3: [(2, 600, -3), (4, 10000, 4)],
            4: [(2, 120, 4), (3, 600, -6)],
            5: [(2, 90, 4), (3, 500, -6)],
            8: [(2, 80, 3), (3, 700, -3)],
            10: [(2, 300, -3), (3, 2500, 3)],
            11: [(2, 350, -2), (3, 3000, 2)],
            12: [(2, 250, -4), (4, 9000, 3)],
            13: [(3, 1500, -2)],
            15: [(2, 400, -3), (3, 5000, 2)]
        ]
        for (n, bands) in eqShapes {
            let s = StripID(.channel, n)
            values[s.eqOnPath] = .int(1)
            for (band, freq, gain) in bands {
                values[s.eqPath(band, "f")] = .float(X32Math.logInverse(freq, 20, 20000))
                values[s.eqPath(band, "g")] = .float(X32Math.linInverse(gain, -15, 15))
            }
        }

        let aux: [(String, Int)] = [("Walk-in L", 14), ("Walk-in R", 14), ("Video L", 6), ("Video R", 6), ("", 0), ("", 0), ("USB L", 15), ("USB R", 15)]
        for (i, a) in aux.enumerated() {
            let s = StripID(.auxIn, i + 1)
            values[s.namePath] = .string(a.0)
            values[s.colorPath] = .int(Int32(a.1))
            values[s.faderPath] = .float(a.0.isEmpty ? 0 : X32Math.dbToFader(-10))
            values[s.panPath ?? ""] = .float(i % 2 == 0 ? 0 : 1)
        }

        let fx = ["Hall Rev", "Hall Rev", "Plate", "Plate", "Delay", "Delay", "Chorus", "Chorus"]
        for (i, name) in fx.enumerated() {
            let s = StripID(.fxReturn, i + 1)
            values[s.namePath] = .string(name)
            values[s.colorPath] = .int(14)
            values[s.faderPath] = .float(X32Math.dbToFader(-8))
            values[s.panPath ?? ""] = .float(i % 2 == 0 ? 0 : 1)
        }

        let buses: [(String, Int)] = [
            ("Vox Wedge", 5), ("Gtr Wedge", 2), ("Bass Wedge", 4), ("Keys Wedge", 3),
            ("Drum Fill", 1), ("Side Fill", 7), ("IEM Sax", 6), ("IEM Tpt", 6),
            ("Sub", 12), ("Front Fill", 15), ("", 0), ("", 0),
            ("Hall Rev", 14), ("Plate", 14), ("Delay", 14), ("Chorus", 14)
        ]
        for (i, b) in buses.enumerated() {
            let s = StripID(.bus, i + 1)
            values[s.namePath] = .string(b.0)
            values[s.colorPath] = .int(Int32(b.1))
            values[s.faderPath] = .float(b.0.isEmpty ? 0 : X32Math.dbToFader(i < 10 ? -2 : 0))
        }

        // Monitor sends: who hears what.
        let mixes: [Int: [Int: Float]] = [
            1: [16: 0, 17: -6, 18: -6, 13: -12, 14: -12, 1: -15],
            2: [10: -2, 11: -4, 16: -8, 1: -12, 2: -12],
            3: [8: 0, 1: -3, 2: -8, 16: -10],
            4: [13: -2, 14: -2, 15: -4, 16: -6],
            5: [1: -2, 2: -4, 8: -6, 16: -8, 10: -10],
            7: [20: 0, 16: -6, 13: -10, 1: -12],
            8: [21: 0, 16: -6, 13: -10, 1: -12]
        ]
        for strip in StripID.all(.channel) {
            for bus in 1...16 {
                var level: Float = 0
                if let mix = mixes[bus], let db = mix[strip.index] {
                    level = X32Math.dbToFader(db)
                } else if bus >= 13 && (strip.index >= 16 && strip.index <= 21) {
                    level = X32Math.dbToFader(bus == 13 ? -12 : -20)
                }
                values[strip.sendLevelPath(bus)] = .float(level)
            }
        }

        let dcas = ["Drums", "Bass", "Guitars", "Keys", "Vocals", "Horns", "FX", "Playback"]
        let dcaColors = [1, 4, 2, 3, 5, 6, 14, 15]
        for (i, name) in dcas.enumerated() {
            let s = StripID(.dca, i + 1)
            values[s.namePath] = .string(name)
            values[s.colorPath] = .int(Int32(dcaColors[i]))
            values[s.faderPath] = .float(X32Math.unityFader)
        }

        let matrices = ["Lobby", "Record L", "Record R", "Delay Spk", "", ""]
        for (i, name) in matrices.enumerated() {
            let s = StripID(.matrix, i + 1)
            values[s.namePath] = .string(name)
            values[s.colorPath] = .int(name.isEmpty ? 0 : 7)
        }

        values["/main/st/mix/fader"] = .float(X32Math.dbToFader(-3))
        values["/main/st/config/name"] = .string("Main")
        values["/main/st/config/color"] = .int(7)
        values["/main/m/config/name"] = .string("Sub/Center")

        for (i, name) in sceneNames.enumerated() {
            values[Show.scenePath(i, "name")] = .string(name)
            values[Show.scenePath(i, "hasdata")] = .int(1)
        }
        values[Show.currentPath] = .int(1)
        values[Show.controlPath] = .int(Int32(Show.Control.scenes.rawValue))
        values[Show.namePath] = .string("Saturday gig")
        // A small cue list: (number, name, scene, snippet)
        let cues: [(Int, String, Int, Int)] = [(100, "Doors", 4, -1), (200, "Welcome", 3, -1), (300, "Band on", 1, 0),
                                               (310, "Acoustic", 2, -1), (320, "Full band", 1, 1), (400, "Encore", 1, 0), (500, "Walk-out", 4, -1)]
        for (i, cue) in cues.enumerated() {
            values[Show.cuePath(i, "numb")] = .int(Int32(cue.0))
            values[Show.cuePath(i, "name")] = .string(cue.1)
            values[Show.cuePath(i, "scene")] = .int(Int32(cue.2))
            values[Show.cuePath(i, "bit")] = .int(Int32(cue.3))
            values[Show.cuePath(i, "skip")] = .int(i == 5 ? 1 : 0)
        }
        for (i, name) in ["FX on", "FX off", "Vox EQ tweak"].enumerated() {
            values[Show.snippetPath(i, "name")] = .string(name)
            values[Show.snippetPath(i, "hasdata")] = .int(1)
        }
    }

    /// What an untouched X32 reports for parameters the demo hasn't set.
    /// After the type of a slot is changed, its parameters take the new type's shape.
    private func effectDefault(_ address: String) -> OSCArg? {
        let parts = address.split(separator: "/")
        guard parts.count == 4, parts[0] == "fx", parts[2] == "par", let slot = Int(parts[1]), let n = Int(parts[3]),
              let type = values[Effects.typePath(slot)]?.intValue else { return nil }
        if Effects.graphicEQSides(slot: slot, type: type) != nil { return .float(0.5) }
        guard let params = Effects.parameters(slot: slot, type: type), n >= 1, n <= params.count else { return nil }
        if case .choice = params[n - 1].kind { return .int(0) }
        return .float(0.5)
    }

    static func defaultValue(for address: String) -> OSCArg? {
        if address.hasPrefix("/-ha/") && address.hasSuffix("/index") {
            let parts = address.split(separator: "/")
            if parts.count >= 2, let n = Int(parts[1]) {
                return .int(n < 32 ? Int32(n) : -1)
            }
            return .int(-1)
        }
        if address.hasPrefix("/headamp/") {
            if address.hasSuffix("/gain") { return .float(X32Math.linInverse(20, -12, 60)) }
            if address.hasSuffix("/phantom") { return .int(0) }
        }
        if address.hasPrefix("/-show/showfile/scene/") || address.hasPrefix("/-show/showfile/snippet/") {
            if address.hasSuffix("/name") { return .string("") }
            if address.hasSuffix("/hasdata") { return .int(0) }
        }
        if address.hasPrefix("/-show/showfile/cue/") {
            if address.hasSuffix("/name") { return .string("") }
            if address.hasSuffix("/numb") || address.hasSuffix("/skip") { return .int(0) }
            if address.hasSuffix("/scene") || address.hasSuffix("/bit") { return .int(-1) }
        }
        if address == Show.controlPath { return .int(1) }
        if address == Show.namePath { return .string("") }
        if address.hasPrefix("/-stat/solosw/") || address == "/-stat/solo" { return .int(0) }
        if address.hasPrefix("/config/mute/") { return .int(0) }
        if address.hasPrefix("/config/") && address.contains("link/") { return .int(0) }
        if address.hasPrefix("/config/linkcfg/") { return .int(1) }
        if address.hasPrefix("/fx/") {
            let parts = address.split(separator: "/")
            let slot = parts.count >= 2 ? Int(parts[1]) ?? 1 : 1
            if address.hasSuffix("/type") {
                // Hall, Plate, Stereo Delay, Chorus in 1-4 (fed by Mix 13-16), GEQs in 5-8.
                return .int(slot <= 4 ? Int32([0, 5, 10, 13][slot - 1]) : Int32([0, 0, 1, 2][slot - 5]))
            }
            if address.hasSuffix("/source/l") || address.hasSuffix("/source/r") {
                return .int(slot <= 4 ? Int32(12 + slot) : 0)
            }
            if address.contains("/par/") {
                // Choice parameters are ints on the desk (delay mode/factors, switches).
                let n = Int(parts.last ?? "") ?? 1
                if slot >= 5 {
                    // Graphic EQs: a typical wedge curve (a few notches), masters at 0 dB.
                    let band = (n - 1) % 32 + 1
                    let cuts: [Int: Float] = [9: -3, 13: -4.5, 17: -2, 21: -6, 23: -3.5, 27: -2.5]
                    return .float(band == 32 ? 0.5 : Effects.geqSpec.norm(cuts[band] ?? 0))
                }
                let type = [0, 5, 10, 13][slot - 1]
                if let p = Effects.parameters(slot: slot, type: type), n <= p.count, case .choice = p[n - 1].kind {
                    return .int(n == 4 || n == 5 ? 4 : 0)
                }
                return .float(0.4)
            }
        }
        if address == "/-show/prepos/current" { return .int(0) }
        if address.hasPrefix("/config/routing/OUT/") {
            // Local XLR outs carry the 16 "Out" signals.
            return .int(20)
        }
        if address.hasPrefix("/config/routing/AES50A/") || address.hasPrefix("/config/routing/AES50B/") || address.hasPrefix("/config/routing/CARD/") {
            let block = Int(address.split(separator: "/").last?.split(separator: "-").first ?? "1") ?? 1
            return .int(Int32((block - 1) / 8))   // local inputs, block by block
        }
        if address == OutputRouting.switchPath { return .int(0) }
        if address.hasPrefix("/config/routing/PLAY/") {
            let tail = address.dropFirst("/config/routing/PLAY/".count)
            return .int(Int32(["1-8": 16, "9-16": 17, "17-24": 18, "25-32": 19, "AUX": 10][String(tail)] ?? 0))
        }
        if address.hasPrefix("/config/routing/IN/") {
            // Local inputs on channels 1-32, local aux on the aux ins.
            switch address.dropFirst("/config/routing/IN/".count) {
            case "1-8": return .int(0)
            case "9-16": return .int(1)
            case "17-24": return .int(2)
            case "25-32": return .int(3)
            default: return .int(0)
            }
        }
        if address.hasPrefix("/outputs/") {
            // A typical patch: local outs 1-2 = LR, then the mix buses; P16 = channel direct outs.
            let parts = address.split(separator: "/")
            if parts.count == 5, parts[3] == "delay" { return parts[4] == "on" ? .int(0) : .float(0) }
            guard parts.count == 4, let n = Int(parts[2]) else { return nil }
            if parts[3] == "pos" { return .int(6) }
            if parts[3] == "invert" { return .int(0) }
            if parts[3] != "src" { return nil }
            switch parts[1] {
            case "main": return .int(Int32(n <= 2 ? n : n + 1))
            case "aux": return .int(Int32(n + 3))
            case "p16": return .int(Int32(25 + n))
            case "aes": return .int(Int32(n))
            case "rec": return .int(Int32(n))
            default: return nil
            }
        }
        if address == RTA.sourcePath || address == RTA.screenPath || address == RTA.meterPagePath { return .int(0) }
        if address == RTA.positionPath { return .int(1) }
        if address == "/config/solo/level" { return .float(0.5) }
        if address == Monitoring.sourcePath { return .int(1) }
        if address.hasSuffix("/automix/group") || address.hasPrefix("/config/amixenable/") { return .int(0) }
        if address.hasSuffix("/automix/weight") { return .float(0.5) }
        if address == Oscillator.onPath || address == Oscillator.selectPath || address == Oscillator.typePath { return .int(0) }
        if address == Oscillator.levelPath { return .float(X32Math.dbToFader(-20)) }
        if address == Oscillator.f1Path { return .float(Oscillator.frequencySpec.norm(1000)) }
        if address == Oscillator.f2Path { return .float(Oscillator.frequencySpec.norm(100)) }
        if address == Oscillator.destinationPath { return .int(18) }
        if address == Recorder.statePath { return .int(0) }
        if address == Recorder.mountedPath { return .int(1) }
        if address == Recorder.filePath { return .string("R_20261024-201500.wav") }
        if [Monitoring.monoPath, Monitoring.channelModePath, Monitoring.busModePath, Monitoring.exclusivePath].contains(address) { return .int(0) }
        if address == Monitoring.talkDestinationPath("A") { return .int(0b111111) }
        if address == Monitoring.talkDestinationPath("B") { return .int(0) }
        if address == "/config/solo/dim" { return .int(0) }
        if address.hasPrefix("/config/talk/") && address.hasSuffix("/level") { return .float(0.5) }
        if address.hasPrefix("/-stat/talk/") { return .int(0) }

        if address.hasSuffix("/config/name") { return .string("") }
        if address.hasSuffix("/config/color") { return .int(0) }
        if address.hasSuffix("/config/icon") { return .int(1) }
        if address.hasSuffix("/config/source") {
            let parts = address.split(separator: "/")
            if parts.count >= 2, parts[0] == "ch", let n = Int(parts[1]) { return .int(Int32(n)) }
            return .int(0)
        }
        if address.hasSuffix("/grp/dca") || address.hasSuffix("/grp/mute") { return .int(0) }
        if address.hasSuffix("/mix/fader") || address.hasSuffix("/fader") {
            if address.hasPrefix("/dca/") || address.hasPrefix("/main/") { return .float(X32Math.unityFader) }
            return .float(0)
        }
        if address.hasPrefix("/bus/0") && address.contains("/insert/") {
            // Wedges on Mix 1-4 run through the graphic EQs in FX 5 and 6.
            if let n = Int(address.dropFirst(5).prefix(2)), (1...4).contains(n) {
                if address.hasSuffix("/on") { return .int(1) }
                if address.hasSuffix("/sel") { return .int(Int32(8 + n)) }
            }
        }
        if address.hasSuffix("/on") {
            if address.contains("/eq/") || address.contains("/gate/") || address.contains("/dyn/") || address.contains("/insert/") || address.contains("/delay/") {
                return .int(address.contains("/eq/") ? 1 : 0)
            }
            return .int(1)
        }
        if address.hasSuffix("/mix/pan") || address.hasSuffix("/pan") { return .float(0.5) }
        if address.hasSuffix("/mix/st") { return .int(1) }
        if address.hasSuffix("/mix/mono") { return .int(0) }
        if address.hasSuffix("/mix/mlevel") { return .float(0) }
        if address.hasSuffix("/level") { return .float(0) }
        if address.hasSuffix("/type") && address.contains("/mix/") { return .int(3) }
        if address.hasSuffix("/panFollow") { return .int(0) }

        if address.hasSuffix("/delay/time") { return .float(0) }
        if address.hasSuffix("/insert/pos") || address.hasSuffix("/insert/sel") { return .int(0) }
        if address.hasSuffix("/keysrc") || address.hasSuffix("/filter/type") || address.hasSuffix("/dyn/pos") { return .int(0) }
        if address.hasSuffix("/filter/f") { return .float(0.5) }
        if address.contains("/preamp/") {
            if address.hasSuffix("/trim") { return .float(0.5) }
            if address.hasSuffix("/invert") { return .int(0) }
            if address.hasSuffix("/hpon") { return .int(0) }
            if address.hasSuffix("/hpslope") { return .int(0) }
            if address.hasSuffix("/hpf") { return .float(X32Math.logInverse(80, 20, 400)) }
        }
        if address.contains("/eq/") {
            let parts = address.split(separator: "/")
            let band = parts.count >= 2 ? Int(parts[parts.count - 2]) ?? 1 : 1
            if address.hasSuffix("/type") {
                if band == 1 { return .int(1) }
                if band == 4 && !address.hasPrefix("/bus") && !address.hasPrefix("/mtx") && !address.hasPrefix("/main") { return .int(4) }
                if band == 6 { return .int(4) }
                return .int(2)
            }
            if address.hasSuffix("/f") {
                let sixBand = address.hasPrefix("/bus") || address.hasPrefix("/mtx") || address.hasPrefix("/main")
                let freqs: [Float] = sixBand ? [80, 250, 800, 2500, 6000, 12000] : [100, 400, 1600, 8000]
                return .float(X32Math.logInverse(freqs[max(0, min(freqs.count - 1, band - 1))], 20, 20000))
            }
            if address.hasSuffix("/g") { return .float(0.5) }
            if address.hasSuffix("/q") { return .float(X32Math.logInverse(2, 10, 0.3)) }
        }
        if address.contains("/gate/") {
            if address.hasSuffix("/mode") { return .int(3) }
            if address.hasSuffix("/thr") { return .float(X32Math.linInverse(-50, -80, 0)) }
            if address.hasSuffix("/range") { return .float(X32Math.linInverse(60, 3, 60)) }
            if address.hasSuffix("/attack") { return .float(0) }
            if address.hasSuffix("/hold") { return .float(X32Math.logInverse(50, 0.02, 2000)) }
            if address.hasSuffix("/release") { return .float(X32Math.logInverse(200, 5, 4000)) }
            if address.hasSuffix("/keysrc") { return .int(0) }
        }
        if address.contains("/dyn/") {
            if address.hasSuffix("/mode") || address.hasSuffix("/det") || address.hasSuffix("/env") { return .int(address.hasSuffix("/env") ? 1 : 0) }
            if address.hasSuffix("/thr") { return .float(X32Math.linInverse(-20, -60, 0)) }
            if address.hasSuffix("/ratio") { return .int(3) }
            if address.hasSuffix("/knee") { return .float(X32Math.linInverse(2, 0, 5)) }
            if address.hasSuffix("/mgain") { return .float(0) }
            if address.hasSuffix("/attack") { return .float(X32Math.linInverse(10, 0, 120)) }
            if address.hasSuffix("/hold") { return .float(X32Math.logInverse(2, 0.02, 2000)) }
            if address.hasSuffix("/release") { return .float(X32Math.logInverse(150, 5, 4000)) }
            if address.hasSuffix("/pos") { return .int(0) }
            if address.hasSuffix("/mix") { return .float(1) }
            if address.hasSuffix("/auto") { return .int(0) }
            if address.hasSuffix("/keysrc") { return .int(0) }
        }
        return nil
    }
}
