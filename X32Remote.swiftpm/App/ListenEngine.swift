import AVFoundation
import Foundation
import Observation

/// Plays the desk's solo bus into whatever earphones are plugged into this iPad, either streamed
/// from the X32 Listen Bridge on a Mac (over Wi-Fi) or read straight from the desk's USB port
/// when the iPad is plugged into it.
@Observable
final class ListenEngine {
    enum Source: String, CaseIterable, Identifiable {
        case mac, usb
        var id: String { rawValue }
        var title: String {
            switch self {
            case .mac: return "Mac on Wi-Fi"
            case .usb: return "iPad plugged into the desk"
            }
        }
    }

    /// How much audio to hold back to ride out Wi-Fi hiccups. More is steadier but later.
    enum Cushion: Int, CaseIterable, Identifiable {
        case tight = 10, normal = 25, safe = 60
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .tight: return "Tight"
            case .normal: return "Normal"
            case .safe: return "Safe"
            }
        }
    }

    struct Bridge: Identifiable, Equatable {
        let ip: String
        let name: String
        var id: String { ip }
    }

    // MARK: Settings (remembered)

    var source: Source = Source(rawValue: UserDefaults.standard.string(forKey: "listen.source") ?? "") ?? .mac {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "listen.source"); if running { restart() } }
    }
    var bridgeIP: String = UserDefaults.standard.string(forKey: "listen.bridge") ?? "" {
        didSet { UserDefaults.standard.set(bridgeIP, forKey: "listen.bridge") }
    }
    var cushion: Cushion = Cushion(rawValue: UserDefaults.standard.integer(forKey: "listen.cushion")) ?? .normal {
        didSet {
            UserDefaults.standard.set(cushion.rawValue, forKey: "listen.cushion")
            buffer.targetFrames = framesFor(cushion)
        }
    }
    var volume: Float = (UserDefaults.standard.object(forKey: "listen.volume") as? Float) ?? 0.8 {
        didSet {
            UserDefaults.standard.set(volume, forKey: "listen.volume")
            applyVolume()
        }
    }
    /// USB channels (1-based) the solo bus arrives on, from the desk routing.
    @ObservationIgnored var usbChannels: (left: Int, right: Int) = (31, 32)

    // MARK: State

    private(set) var running = false
    private(set) var status = ""
    /// Something's wrong enough to say so in red.
    private(set) var problem: String?
    private(set) var bridges: [Bridge] = []
    /// Audio is arriving (Wi-Fi) or the desk is connected (USB).
    private(set) var receiving = false
    private(set) var delayMS = 0
    private(set) var dropouts = 0

    // MARK: Internals

    // Plumbing the screen never shows (and lastAudio changes 200 times a second).
    private let buffer = JitterBuffer()
    @ObservationIgnored private var socket: UDPSocket?
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastAudio: TimeInterval = 0
    @ObservationIgnored private var lastHello: TimeInterval = 0
    private let engine = AVAudioEngine()
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    @ObservationIgnored private var sinkNode: AVAudioSinkNode?
    @ObservationIgnored private var graphRate: Double = 0
    @ObservationIgnored private var routeObserver: NSObjectProtocol?
    @ObservationIgnored private var silencedForSafety = false
    /// Interleaved scratch for the render callback (allocated once, never on the audio thread).
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 8192 * 2)

    init() {
        buffer.targetFrames = framesFor(cushion)
    }

    deinit {
        scratch.deallocate()
    }

    private func framesFor(_ c: Cushion) -> Int {
        max(240, buffer.sampleRate * c.rawValue / 1000)
    }

    // MARK: Finding a bridge

    /// Looks for Macs running the bridge on this network (the same sweep the desk search uses).
    func search() {
        guard ensureSocket() else { return }
        searchGeneration += 1
        let generation = searchGeneration
        var targets: [String] = []
        for interface in LocalIPv4Interface.all() {
            // This device too: when the app runs on the Mac itself, the bridge can be right here.
            let own = LocalIPv4Interface.format(interface.address)
            if !targets.contains(own) { targets.append(own) }
            for ip in interface.scanTargets where !targets.contains(ip) { targets.append(ip) }
        }
        let probe = ListenProtocol.encode(.probe)
        for (n, start) in stride(from: 0, to: targets.count, by: 32).enumerated() {
            let batch = Array(targets[start..<min(start + 32, targets.count)])
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(n) * 0.03) { [weak self] in
                guard let self, self.searchGeneration == generation, let s = self.socket else { return }
                for ip in batch { _ = s.send(probe, to: ip, port: ListenProtocol.port) }
            }
        }
    }

    private func ensureSocket() -> Bool {
        if socket != nil { return true }
        guard let s = try? UDPSocket(label: "x32remote.listen") else {
            problem = "Couldn't open a network socket"
            return false
        }
        let buffer = buffer
        s.onReceive = { [weak self] data, sender in
            guard let message = ListenProtocol.decode(data) else { return }
            switch message {
            case .audio(let audio):
                // Straight into the buffer from the network thread; the screen hears about it later.
                buffer.push(audio)
                DispatchQueue.main.async { self?.lastAudio = X32Client.now() }
            case .info(let name):
                DispatchQueue.main.async { self?.found(Bridge(ip: sender, name: name)) }
            default:
                break
            }
        }
        s.start()
        socket = s
        return true
    }

    private func found(_ bridge: Bridge) {
        if let i = bridges.firstIndex(where: { $0.ip == bridge.ip }) {
            bridges[i] = bridge
        } else {
            bridges.append(bridge)
        }
        // The first one found becomes the choice if there's none yet.
        if bridgeIP.isEmpty { bridgeIP = bridge.ip }
    }

    // MARK: Start and stop

    func start() {
        guard !running else { return }
        running = true
        problem = nil
        dropouts = 0
        buffer.reset()
        switch source {
        case .mac: startWiFi()
        case .usb: startUSB()
        }
        guard running else { return }
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        if let o = routeObserver { NotificationCenter.default.removeObserver(o) }
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkRoute()
        }
    }

    func stop() {
        guard running else { return }
        running = false
        if source == .mac, let s = socket, let ip = IPv4.normalized(bridgeIP) {
            _ = s.send(ListenProtocol.encode(.bye), to: ip, port: ListenProtocol.port)
        }
        timer?.invalidate()
        timer = nil
        if let o = routeObserver { NotificationCenter.default.removeObserver(o) }
        routeObserver = nil
        engine.stop()
        if let n = sourceNode { engine.detach(n) }
        sourceNode = nil
        if let n = sinkNode { engine.detach(n) }
        sinkNode = nil
        graphRate = 0
        buffer.targetFrames = framesFor(cushion)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        receiving = false
        status = ""
        delayMS = 0
    }

    func toggle() {
        running ? stop() : start()
    }

    private func restart() {
        stop()
        start()
    }

    // MARK: Wi-Fi

    private func startWiFi() {
        guard let ip = IPv4.normalized(bridgeIP) else {
            problem = "Pick the Mac running X32 Listen Bridge first"
            running = false
            return
        }
        guard ensureSocket() else { running = false; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            problem = "The iPad wouldn't start audio: \(error.localizedDescription)"
            running = false
            return
        }
        buildPlayer(rate: Double(buffer.sampleRate))
        sendHello(to: ip)
        status = "Waiting for audio from the Mac…"
        checkRoute()
    }

    private func sendHello(to ip: String) {
        lastHello = X32Client.now()
        _ = socket?.send(ListenProtocol.encode(.hello), to: ip, port: ListenProtocol.port)
    }

    /// The player: pulls from the jitter buffer on the audio thread.
    private func buildPlayer(rate: Double) {
        engine.stop()
        if let n = sourceNode { engine.detach(n) }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let buffer = buffer
        let scratch = scratch
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let frames = min(Int(frameCount), 8192)
            buffer.pull(frames, into: scratch)
            let list = UnsafeMutableAudioBufferListPointer(audioBufferList)
            // Standard format is one buffer per channel.
            if list.count >= 2, let l = list[0].mData?.assumingMemoryBound(to: Float.self),
               let r = list[1].mData?.assumingMemoryBound(to: Float.self) {
                for i in 0..<frames {
                    l[i] = scratch[i * 2]
                    r[i] = scratch[i * 2 + 1]
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
        graphRate = rate
        applyVolume()
        do {
            try engine.start()
        } catch {
            problem = "The iPad wouldn't start audio: \(error.localizedDescription)"
        }
    }

    // MARK: USB

    private func startUSB() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [])
            guard let usb = session.availableInputs?.first(where: { $0.portType == .usbAudio }) else {
                problem = "No desk on USB. Plug the iPad into the X32's USB port (the USB card on the back) with a USB-C cable."
                running = false
                return
            }
            try session.setPreferredInput(usb)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            // Open every channel the card has, so the solo bus channels are there to pick.
            try? session.setPreferredInputNumberOfChannels(session.maximumInputNumberOfChannels)
        } catch {
            problem = "The iPad wouldn't use the desk's USB audio: \(error.localizedDescription)"
            running = false
            return
        }
        let input = engine.inputNode
        let hardware = input.outputFormat(forBus: 0)
        let channels = Int(hardware.channelCount)
        guard channels >= usbChannels.right else {
            problem = "The desk's USB card shows \(channels) channels here; solo is on \(usbChannels.left)/\(usbChannels.right)."
            running = false
            return
        }
        // Take the two solo channels from all the card's channels, into the same small buffer the
        // Wi-Fi player uses (a direct stereo hookup to a 32-channel input isn't reliable).
        let buffer = buffer
        let left = usbChannels.left - 1, right = usbChannels.right - 1
        let rate = Int(hardware.sampleRate)
        buffer.targetFrames = max(128, rate * 6 / 1000)
        let sink = AVAudioSinkNode { _, frameCount, audioBufferList -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
            guard list.count > right,
                  let l = list[left].mData?.assumingMemoryBound(to: Float.self),
                  let r = list[right].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            buffer.push(left: l, right: r, frames: Int(frameCount), sampleRate: rate)
            return noErr
        }
        engine.attach(sink)
        engine.connect(input, to: sink, format: hardware)
        sinkNode = sink
        buildPlayer(rate: hardware.sampleRate)
        if problem != nil {
            running = false
            return
        }
        receiving = true
        status = "Listening to USB \(usbChannels.left)/\(usbChannels.right) from the desk"
        checkRoute()
    }

    // MARK: Housekeeping

    private func tick() {
        guard running else { return }
        let now = X32Client.now()
        if source == .mac {
            if let ip = IPv4.normalized(bridgeIP), now - lastHello >= 1 { sendHello(to: ip) }
            receiving = now - lastAudio < 1
            if Double(buffer.sampleRate) != graphRate { buildPlayer(rate: Double(buffer.sampleRate)) }
            let cushionMS = buffer.buffered * 1000 / max(buffer.sampleRate, 1)
            let output = Int(AVAudioSession.sharedInstance().outputLatency * 1000)
            let io = Int(AVAudioSession.sharedInstance().ioBufferDuration * 1000)
            // Mac capture and network are a few ms more on top of what's measured here.
            delayMS = cushionMS + output + io + 8
            dropouts = buffer.underruns
            if receiving {
                status = "Listening via \(bridges.first { $0.ip == bridgeIP }?.name ?? bridgeIP)"
            } else if lastAudio == 0 || now - lastAudio > 3 {
                status = "No audio from the Mac. Is X32 Listen Bridge running and on the same Wi-Fi?"
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            delayMS = Int((session.inputLatency + session.outputLatency + session.ioBufferDuration * 2) * 1000)
        }
    }

    /// Never send the solo bus back into the desk, and warn about Bluetooth's delay.
    private func checkRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let toDesk = source == .usb && outputs.contains { $0.portType == .usbAudio }
        let bluetoothPorts: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        let bluetooth = outputs.contains { bluetoothPorts.contains($0.portType) }
        silencedForSafety = toDesk
        applyVolume()
        if toDesk {
            problem = "The sound would go back into the desk, so it's muted. Plug your earphones into the iPad (headphone socket, or a USB-C hub with a headphone adapter)."
        } else if bluetooth {
            problem = "Bluetooth earphones add about 200 ms of delay. Fine for checking sources; use wired IEMs for anything timing-critical."
        } else if problem?.hasPrefix("The sound would go back") == true || problem?.hasPrefix("Bluetooth") == true {
            problem = nil
        }
    }

    private func applyVolume() {
        engine.mainMixerNode.outputVolume = silencedForSafety ? 0 : volume
    }
}
