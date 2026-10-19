import SwiftUI
import Observation
import UIKit

/// App-wide state: the console session, parameter store, meters and UI navigation.
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case connecting(String)
        case connected
    }

    enum Sheet: String, Identifiable {
        case scenes
        case settings
        case modes
        var id: String { rawValue }
    }

    let store = ParamStore()
    let meters = MeterStore()
    let discovery = X32Discovery()

    @ObservationIgnored private var client: X32Client?
    @ObservationIgnored private var connectTimeout: DispatchWorkItem?
    @ObservationIgnored private var currentHost: String?
    @ObservationIgnored private var didApplyLaunchArguments = false

    private(set) var settings: AppSettings = AppSettings.load()
    private(set) var phase: Phase = .idle
    private(set) var console: ConsoleInfo?
    private(set) var isDemo = false
    private(set) var linkLost = false
    var lastError: String?
    var discovered: [X32Discovery.Console] = []

    // Mixer navigation
    var layer: MixerLayer = .inputs1
    var sendsBus: Int?
    var detailStrip: StripID?
    var sheet: Sheet?
    var detailTab: DetailTab = .eq
    /// The channel the open channel page is showing now (it can step prev/next).
    @ObservationIgnored var visibleDetailStrip: StripID?

    init() {
        discovery.onChange = { [weak self] consoles in
            self?.discovered = consoles
        }
    }

    // MARK: - Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        settings = copy
        settings.save()
        applyIdleTimer()
    }

    var hasPIN: Bool { !settings.pin.isEmpty }

    func checkPIN(_ entry: String) -> Bool {
        settings.pin.isEmpty || entry == settings.pin
    }

    func setMode(_ mode: AppMode) {
        updateSettings { $0.mode = mode }
        if mode == .monitor {
            loadSends(bus: settings.monitorBus)
        }
        updateMeterSubscriptions()
    }

    // MARK: - Connection

    var connectedName: String {
        if let c = console, !c.name.isEmpty { return c.name }
        if isDemo { return "Demo desk" }
        return currentHost ?? "X32"
    }

    var connectedAddress: String {
        isDemo ? "Built-in demo" : (currentHost ?? "")
    }

    func startDiscovery() {
        if !discovery.isRunning {
            discovery.start()
        }
    }

    func stopDiscovery() {
        discovery.stop()
    }

    static func isValidIPv4(_ s: String) -> Bool {
        IPv4.normalized(s) != nil
    }

    func connect(host rawHost: String) {
        guard let host = IPv4.normalized(rawHost) else {
            let shown = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
            lastError = "“\(shown)” isn't an IP address. It looks like 192.168.1.50 — find it on the X32 under Setup › Network."
            return
        }
        disconnect()
        lastError = nil
        do {
            let transport = try UDPTransport(host: host)
            currentHost = host
            start(transport: transport, demo: false)
            phase = .connecting(host)
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if case .connecting = self.phase {
                    if self.settings.locked {
                        // A locked staff/performer iPad: keep waiting for the desk (e.g. it's still booting).
                        self.connect(host: host)
                        return
                    }
                    self.disconnect()
                    self.lastError = "No answer from \(host). Check the X32's IP address (Setup › Network), that this iPad is on the same network, and that Local Network is allowed for X32 Remote in Settings › Privacy."
                }
            }
            connectTimeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
        } catch {
            lastError = "Couldn't open a network socket: \(error.localizedDescription)"
        }
    }

    func startDemo() {
        disconnect()
        lastError = nil
        currentHost = nil
        start(transport: DemoTransport(), demo: true)
        phase = .connecting("Demo desk")
    }

    func disconnect() {
        connectTimeout?.cancel()
        connectTimeout = nil
        client?.close()
        client = nil
        phase = .idle
        console = nil
        linkLost = false
        isDemo = false
        detailStrip = nil
        sendsBus = nil
        sheet = nil
        applyIdleTimer()
    }

    private func start(transport: X32Transport, demo: Bool) {
        store.clear()
        meters.reset()
        isDemo = demo
        client = makeClient(transport)
    }

    private func makeClient(_ transport: X32Transport) -> X32Client {
        let c = X32Client(transport: transport)
        c.onStatus = { [weak self] status in
            self?.clientStatusChanged(status)
        }
        c.onInfo = { [weak self] info in
            self?.console = info
        }
        c.onMessage = { [weak self] message in
            self?.handle(message)
        }
        c.onMeters = { [weak self] block, values in
            self?.meters.ingest(block: block, values: values)
        }
        return c
    }

    @ObservationIgnored private var resyncOnConnect = false

    private func clientStatusChanged(_ status: X32Client.Status) {
        switch status {
        case .connected:
            connectTimeout?.cancel()
            connectTimeout = nil
            let wasLost = linkLost
            linkLost = false
            if phase != .connected {
                phase = .connected
                stopDiscovery()
                if let host = currentHost {
                    updateSettings { s in
                        s.lastHost = host
                        s.recentHosts.removeAll { $0 == host }
                        s.recentHosts.insert(host, at: 0)
                        if s.recentHosts.count > 5 {
                            s.recentHosts = Array(s.recentHosts.prefix(5))
                        }
                    }
                }
                syncAll()
                applyIdleTimer()
                applyLaunchActionsAfterConnect()
            } else if wasLost || resyncOnConnect {
                // Changes made on the desk while we couldn't hear it would otherwise be missed.
                syncAll()
            }
            resyncOnConnect = false
            updateMeterSubscriptions()
        case .lost:
            linkLost = true
            meters.reset()
        case .connecting:
            break
        }
    }

    @ObservationIgnored private var wasInBackground = false

    /// iOS can quietly kill sockets while the app is in the background, so start fresh on return.
    /// (Going active -> background passes through inactive, so remember that we were in the background.)
    func scenePhaseChanged(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        if newPhase == .background {
            wasInBackground = true
            store.releaseAllTouches()
        }
        if newPhase == .active && wasInBackground {
            wasInBackground = false
            if phase == .connected && !isDemo, let host = currentHost, let transport = try? UDPTransport(host: host) {
                client?.close()
                let fresh = makeClient(transport)
                client = fresh
                resyncOnConnect = true
                // If the desk doesn't answer soon (e.g. we're on another network now), say so.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak fresh] in
                    guard let self = self, let fresh = fresh, self.client === fresh else { return }
                    if fresh.status != .connected {
                        self.linkLost = true
                    }
                }
            }
        }
        applyIdleTimer()
    }

    func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepAwake && phase == .connected
    }

    // MARK: - Incoming

    private func handle(_ message: OSCMessage) {
        guard let value = message.args.first else { return }
        let address = message.address
        let previous = store.value(address)
        if let t = lastLocalSet[address] {
            if X32Client.now() - t < 0.6 { return }
            lastLocalSet[address] = nil
        }
        store.applyRemote(address, value)

        if address.hasPrefix("/-ha/") && address.hasSuffix("/index"), let ha = value.intValue, ha >= 0, ha < 128 {
            client?.get([StripID.headampGainPath(ha), StripID.headampPhantomPath(ha)])
        }
        if address == "/-show/prepos/current", let scene = value.intValue, scene >= 0, scene < 100 {
            client?.get(String(format: "/-show/showfile/scene/%03d/name", scene))
            // A scene recalled on the desk changes almost everything: read it all again.
            if let old = previous, old != value {
                scheduleResync()
            }
        }
    }

    @ObservationIgnored private var resyncScheduled = false

    private func scheduleResync() {
        guard !resyncScheduled else { return }
        resyncScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.resyncScheduled = false
            self?.syncAll()
        }
    }

    // MARK: - Loading

    func updateMeterSubscriptions() {
        client?.setMeterSubscriptions([0, 1, 2])
    }

    /// Everything shown on the fader screens.
    func syncAll() {
        guard let c = client else { return }
        var a: [String] = []
        a.reserveCapacity(800)
        for s in StripID.everything {
            a.append(s.namePath)
            a.append(s.colorPath)
            a.append(s.faderPath)
            a.append(s.onPath)
            if let p = s.panPath { a.append(p) }
            if let p = s.lrAssignPath { a.append(p) }
            if let p = s.dcaGroupsPath { a.append(p) }
            if let p = s.muteGroupsPath { a.append(p) }
            a.append(s.soloPath)
        }
        for n in 1...6 {
            a.append("/config/mute/\(n)")
        }
        a.append("/-show/prepos/current")
        a.append("/-stat/solo")
        c.get(a)

        if let bus = sendsBus {
            loadSends(bus: bus)
        }
        if settings.mode == .monitor {
            loadSends(bus: settings.monitorBus)
        }
        if let d = visibleDetailStrip ?? detailStrip {
            loadDetail(d)
        }
    }

    func loadSends(bus: Int) {
        guard let c = client, bus >= 1, bus <= 16 else { return }
        var a: [String] = []
        for s in StripID.busSources {
            a.append(s.sendLevelPath(bus))
            a.append(s.sendOnPath(bus))
            a.append(s.sendTypePath(bus))
        }
        let b = StripID(.bus, bus)
        a.append(b.faderPath)
        a.append(b.onPath)
        a.append(b.namePath)
        a.append(b.colorPath)
        c.get(a)
    }

    func loadDetail(_ s: StripID) {
        guard let c = client else { return }
        var a: [String] = [s.namePath, s.colorPath, s.faderPath, s.onPath, s.soloPath]
        if let p = s.panPath { a.append(p) }
        if s.hasTrim {
            a.append(s.preampPath("trim"))
        }
        if s.hasPolarity {
            a.append(s.preampPath("invert"))
        }
        if s.hasHighPass {
            a.append(s.preampPath("hpon"))
            a.append(s.preampPath("hpf"))
            a.append(s.preampPath("hpslope"))
        }
        if let ha = s.headampIndexPath {
            a.append(ha)
        }
        if s.kind == .channel || s.kind == .auxIn {
            a.append(s.sourcePath)
        }
        if s.hasEQ {
            a.append(s.eqOnPath)
            for band in 1...s.eqBandCount {
                for field in ["type", "f", "g", "q"] {
                    a.append(s.eqPath(band, field))
                }
            }
        }
        if s.hasGate {
            for field in ["on", "mode", "thr", "range", "attack", "hold", "release"] {
                a.append(s.gatePath(field))
            }
        }
        if s.hasDynamics {
            for field in ["on", "mode", "det", "env", "thr", "ratio", "knee", "mgain", "attack", "hold", "release", "mix", "auto"] {
                a.append(s.dynPath(field))
            }
        }
        if s.sendCount > 0 {
            for n in 1...s.sendCount {
                a.append(s.sendLevelPath(n))
                a.append(s.sendOnPath(n))
                if n % 2 == 1 {
                    a.append(s.sendTypePath(n))
                }
            }
            if s.sendsFeedMatrix {
                for m in 1...6 {
                    let mtx = StripID(.matrix, m)
                    a.append(mtx.namePath)
                    a.append(mtx.colorPath)
                }
            }
        }
        if let p = s.lrAssignPath { a.append(p) }
        if let p = s.monoAssignPath { a.append(p) }
        if let p = s.monoLevelPath { a.append(p) }
        if let p = s.dcaGroupsPath { a.append(p) }
        if let p = s.muteGroupsPath { a.append(p) }
        c.get(a)
    }

    func loadScenes() {
        guard let c = client else { return }
        var a: [String] = ["/-show/prepos/current"]
        for n in 0..<100 {
            a.append(String(format: "/-show/showfile/scene/%03d/hasdata", n))
            a.append(String(format: "/-show/showfile/scene/%03d/name", n))
        }
        c.get(a)
    }

    var pendingRequests: Int {
        client?.pendingRequests ?? 0
    }

    // MARK: - Changing things on the desk

    func param(_ address: String) -> Param {
        store.param(address)
    }

    func set(_ address: String, _ value: OSCArg) {
        store.applyLocal(address, value)
        lastLocalSet[address] = X32Client.now()
        client?.set(address, value)
    }

    /// When each parameter was last changed from this app. Replies to older requests that arrive
    /// shortly afterwards would otherwise undo the change on screen.
    @ObservationIgnored private var lastLocalSet: [String: TimeInterval] = [:]

    func setFloat(_ address: String, _ value: Float, steps: Int) {
        set(address, .float(X32Math.quantize(value, steps: steps)))
    }

    func setInt(_ address: String, _ value: Int) {
        set(address, .int(Int32(value)))
    }

    func setBool(_ address: String, _ on: Bool) {
        set(address, .int(on ? 1 : 0))
    }

    func setString(_ address: String, _ value: String) {
        set(address, .string(value))
    }

    /// Mark a control as being touched so desk updates don't fight the user's finger.
    func touch(_ address: String, _ began: Bool) {
        let p = store.param(address)
        p.touchCount = max(0, p.touchCount + (began ? 1 : -1))
    }

    /// Start a drag on `address`. The drag keeps controlling that parameter until it ends,
    /// even if the view is re-used for another channel mid-gesture.
    func beginDrag(_ address: String, _ target: DragTarget) {
        if let previous = target.address {
            touch(previous, false)
        }
        // Never drag from a value we haven't read from the desk: it would jump the real level.
        target.blocked = !store.param(address).isKnown
        if target.blocked {
            client?.get(address)
        }
        target.address = address
        touch(address, true)
    }

    func endDrag(_ target: DragTarget) {
        if let address = target.address {
            touch(address, false)
        }
        target.address = nil
    }

    /// Set a float on the parameter the current drag started on (or `address` if no drag).
    func dragSet(_ address: String, _ target: DragTarget, _ value: Float, steps: Int) {
        if target.blocked { return }
        setFloat(target.address ?? address, value, steps: steps)
    }

    func toggleMute(_ strip: StripID) {
        let p = store.param(strip.onPath)
        guard p.isKnown else {
            client?.get(strip.onPath)
            return
        }
        setBool(strip.onPath, p.int == 0)
    }

    func toggleSolo(_ strip: StripID) {
        let p = store.param(strip.soloPath)
        setBool(strip.soloPath, !p.bool)
        let anySolo = StripID.everything.contains { store.param($0.soloPath).bool }
        store.applyLocal("/-stat/solo", .int(anySolo ? 1 : 0))
    }

    func clearSolo() {
        client?.send(OSCMessage("/-action/clearsolo", [.int(1)]))
        for s in StripID.everything {
            store.applyLocal(s.soloPath, .int(0))
        }
        store.applyLocal("/-stat/solo", .int(0))
    }

    func recallScene(_ n: Int) {
        client?.send(OSCMessage("/-action/goscene", [.int(Int32(n))]))
        store.applyLocal("/-show/prepos/current", .int(Int32(n)))
        scheduleResync()
    }

    // MARK: - Navigation

    func openDetail(_ strip: StripID) {
        if !strip.hasEQ && detailTab == .eq {
            detailTab = .setup
        }
        loadDetail(strip)
        detailStrip = strip
    }

    func selectLayer(_ newLayer: MixerLayer) {
        layer = newLayer
        if !newLayer.supportsBusSends {
            sendsBus = nil
        }
    }

    func selectSendsBus(_ bus: Int?) {
        sendsBus = bus
        if let b = bus {
            loadSends(bus: b)
            if !layer.supportsBusSends {
                layer = .inputs1
            }
        }
    }

    // MARK: - Launch arguments (used for automated screenshots)

    func applyLaunchArguments() {
        guard !didApplyLaunchArguments else { return }
        didApplyLaunchArguments = true
        let d = UserDefaults.standard
        if let mode = d.string(forKey: "autoMode"), let m = AppMode(rawValue: mode) {
            updateSettings { $0.mode = m }
        }
        if let pin = d.string(forKey: "autoPIN") {
            updateSettings { $0.pin = pin }
        }
        if d.object(forKey: "autoLocked") != nil {
            let locked = d.bool(forKey: "autoLocked")
            updateSettings { $0.locked = locked }
        }
        if d.object(forKey: "autoMonitorBus") != nil {
            let bus = d.integer(forKey: "autoMonitorBus")
            updateSettings { $0.monitorBus = max(1, min(16, bus)) }
        }
        if let orientation = d.string(forKey: "autoOrientation") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                AppModel.requestOrientation(landscape: orientation != "portrait")
            }
        }
        if d.bool(forKey: "autoDemo") {
            startDemo()
        } else if let host = d.string(forKey: "autoHost"), !host.isEmpty {
            connect(host: host)
        } else if settings.autoConnect, !settings.lastHost.isEmpty, d.object(forKey: "autoMode") == nil {
            // Go straight back to the last desk, e.g. for a locked staff or performer iPad.
            connect(host: settings.lastHost)
        }
    }

    static func requestOrientation(landscape: Bool) {
        let mask: UIInterfaceOrientationMask = landscape ? .landscapeRight : .portrait
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            }
        }
    }

    private func applyLaunchActionsAfterConnect() {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "autoLayer"), let l = MixerLayer(rawValue: raw) {
            selectLayer(l)
        }
        if d.object(forKey: "autoSends") != nil {
            let bus = d.integer(forKey: "autoSends")
            selectSendsBus(bus >= 1 && bus <= 16 ? bus : nil)
        }
        if let tabName = d.string(forKey: "autoTab"), let t = DetailTab(rawValue: tabName) {
            detailTab = t
        }
        if let detail = d.string(forKey: "autoDetail") {
            let parts = detail.split(separator: "-")
            if parts.count == 2, let kind = StripKind(rawValue: String(parts[0])), let n = Int(parts[1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.openDetail(StripID(kind, n))
                }
            }
        }
        if let sheetName = d.string(forKey: "autoSheet"), let s = Sheet(rawValue: sheetName) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                if s == .scenes {
                    self?.loadScenes()
                }
                self?.sheet = s
            }
        }
        if let script = d.string(forKey: "autoScript"), script == "selftest" {
            runSelfTest()
        }
    }

    /// Makes a few known changes so an automated test can check they reach the console.
    private func runSelfTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.setFloat(StripID.channel(1).faderPath, X32Math.dbToFader(0), steps: 1023)
            self.setBool(StripID.channel(2).onPath, false)
            self.setString(StripID.channel(3).namePath, "SelfTest")
            self.setFloat(StripID.channel(4).sendLevelPath(5), X32Math.dbToFader(-6), steps: 160)
            self.setInt(StripID.channel(5).colorPath, 4)
            self.setFloat(StripID.channel(6).eqPath(2, "g"), X32Math.linInverse(6, -15, 15), steps: 120)
            self.setBool("/config/mute/3", true)
        }
    }
}

/// Remembers which parameter a drag started on (held in a view's @State).
final class DragTarget {
    var address: String?
    var blocked = false
}

/// Tabs on the channel page.
enum DetailTab: String, CaseIterable, Identifiable {
    case input, eq, dynamics, sends, setup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .input: return "Input"
        case .eq: return "EQ"
        case .dynamics: return "Dynamics"
        case .sends: return "Sends"
        case .setup: return "Setup"
        }
    }

    static func available(for strip: StripID) -> [DetailTab] {
        var tabs: [DetailTab] = []
        if strip.hasInputPage { tabs.append(.input) }
        if strip.hasEQ { tabs.append(.eq) }
        if strip.hasGate || strip.hasDynamics { tabs.append(.dynamics) }
        if strip.hasSendsPage { tabs.append(.sends) }
        tabs.append(.setup)
        return tabs
    }
}
