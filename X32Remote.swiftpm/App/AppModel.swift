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
        case meters
        case effects
        case outputs
        case recorder
        case generator
        case help
        case editUser1
        case editUser2
        var id: String { rawValue }
        /// Big working screens fill the iPad instead of sitting in a small card.
        var fillsScreen: Bool {
            switch self {
            case .effects, .outputs, .meters: return true
            default: return false
            }
        }
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
    /// Faders control preamp gain instead of level (red caps).
    var gainOnFaders = false
    /// A DCA whose member channels are shown instead of the layer.
    var spillDCA: Int?
    var detailStrip: StripID?
    var sheet: Sheet?
    var detailTab: DetailTab = .overview
    /// Fine mode: every fader, slider and pan moves 4x more slowly.
    var fineMode = false
    /// The last channel opened, outlined on the mixer.
    var selectedStrip: StripID?
    /// The precision editor (long-press any control).
    var valueEditor: ValueEditRequest?
    /// A channel to open once the current sheet has finished closing.
    @ObservationIgnored var pendingDetail: StripID?
    /// The page to open `pendingDetail` on.
    @ObservationIgnored var pendingDetailTab: DetailTab = .overview
    /// The slot the effects sheet opens on.
    @ObservationIgnored var effectsSlot = 1
    /// Automation only: the show tab to open, and a top-bar popover to show ("monitor", "mutegroups").
    @ObservationIgnored var autoShowTab: Show.Control?
    var autoPopover: String?
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
        gainOnFaders = false
        spillDCA = nil
        valueEditor = nil
        sheet = nil
        applyIdleTimer()
    }

    private func start(transport: X32Transport, demo: Bool) {
        clearUndo()
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
            // The desk may have been restarted or changed while we were away.
            applyRTASource()
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
            dragOriginals.removeAll()
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
        if address == "/save" {
            // The desk answers a scene save with ("scene", 1) for OK or ("scene", 0) for failure.
            if message.args.count >= 2, message.args[1].intValue == 0 {
                showToast("The desk couldn't save that scene")
                loadScenes()
            }
            return
        }
        if rtaWaking && (address == RTA.screenPath || address == RTA.meterPagePath) && screenReplies[address] == nil {
            // The desk's screen as it was before showing the RTA page (read before any echo filtering).
            screenReplies[address] = value
        }
        let previous = store.value(address)
        if let t = lastLocalSet[address] {
            if X32Client.now() - t < 0.6 { return }
            lastLocalSet[address] = nil
        }
        store.applyRemote(address, value)
        if let old = previous, old != value {
            rereadPreampIfSourceChanged(address)
        }

        if address.hasPrefix("/-ha/") && address.hasSuffix("/index"), let ha = value.intValue, ha >= 0, ha < 128 {
            client?.get([StripID.headampGainPath(ha), StripID.headampPhantomPath(ha)])
        }
        if address == Show.currentPath, let position = value.intValue {
            // The position is a cue, scene or snippet index depending on the desk's show-control mode.
            let control = Show.Control(rawValue: store.value(Show.controlPath)?.intValue ?? -1) ?? .scenes
            if position >= 0 && position < control.count {
                client?.get(control.path(position, "name"))
            }
            // Something recalled on the desk can change almost everything: read it all again.
            if let old = previous, old != value {
                clearUndo()
                scheduleResync()
            }
        }
        if address.hasPrefix("/-show/showfile/cue/"), address.hasSuffix("/name") || address.hasSuffix("/numb") {
            // Once a cue is known to exist, read what it fires.
            let parts = address.split(separator: "/")
            if parts.count == 5, let n = Int(parts[3]), n >= 0, n < Show.Control.cues.count {
                let name = store.value(Show.cuePath(n, "name"))?.stringValue ?? ""
                let numb = store.value(Show.cuePath(n, "numb"))?.intValue ?? 0
                if !name.isEmpty || numb > 0 {
                    let details = Show.cueDetailAddresses(n).filter { store.value($0) == nil }
                    if !details.isEmpty { client?.get(details) }
                }
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
        client?.setMeterSubscriptions(rtaStrip == nil ? [0, 1, 2] : [0, 1, 2, RTA.block])
    }

    // MARK: - Analyser

    /// The strip whose EQ is on screen with the analyser showing.
    @ObservationIgnored private(set) var rtaStrip: StripID?
    /// EQ graphs that want the analyser, oldest first (two can overlap briefly while the
    /// layout changes, so each one owns its claim).
    @ObservationIgnored private var rtaClaims: [(id: UUID, strip: StripID)] = []

    func claimRTA(_ id: UUID, strip: StripID) {
        rtaClaims.removeAll { $0.id == id }
        rtaClaims.append((id, strip))
        updateRTA()
    }

    func releaseRTA(_ id: UUID) {
        rtaClaims.removeAll { $0.id == id }
        updateRTA()
    }

    private func updateRTA() {
        let latest = rtaClaims.last?.strip
        let wanted = settings.showRTA ? latest.flatMap { RTA.sourceValue(for: $0) == nil ? nil : $0 } : nil
        guard wanted != rtaStrip else { return }
        rtaStrip = wanted
        if wanted != nil {
            meters.rta.reset()
            applyRTASource()
        }
        updateMeterSubscriptions()
    }

    /// Points the desk's analyser at `rtaStrip`, after the EQ so the picture matches the curve.
    private func applyRTASource() {
        guard let s = rtaStrip, let source = RTA.sourceValue(for: s) else { return }
        set(RTA.positionPath, .int(1))
        set(RTA.sourcePath, .int(Int32(source)))
    }

    func setShowRTA(_ on: Bool) {
        updateSettings { $0.showRTA = on }
        updateRTA()
    }

    /// True while the desk's screen is briefly showing its RTA page.
    private(set) var rtaWaking = false
    @ObservationIgnored private var screenReplies: [String: OSCArg] = [:]

    /// Starts the desk's analyser by showing its RTA page for a moment, then puts the desk's
    /// screen back exactly as it was. Does nothing if the desk's current screen can't be read.
    func wakeRTA() {
        guard !rtaWaking, let c = client else { return }
        rtaWaking = true
        screenReplies.removeAll()
        c.get([RTA.screenPath, RTA.meterPagePath])
        waitForScreen(until: X32Client.now() + 2)
    }

    private func waitForScreen(until deadline: TimeInterval) {
        if let screen = screenReplies[RTA.screenPath], let page = screenReplies[RTA.meterPagePath] {
            set(RTA.screenPath, .int(Int32(RTA.metersScreen)))
            set(RTA.meterPagePath, .int(Int32(RTA.rtaPage)))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.set(RTA.meterPagePath, page)
                self?.set(RTA.screenPath, screen)
                self?.rtaWaking = false
            }
            return
        }
        guard X32Client.now() < deadline else {
            rtaWaking = false
            showToast("Couldn't read the desk's screen. Open the RTA page on the desk once to start its analyser.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForScreen(until: deadline)
        }
    }

    /// Everything shown on the fader screens.
    func syncAll() {
        guard let c = client else { return }
        c.get(Requests.sync())

        if let bus = sendsBus {
            loadSends(bus: bus)
        }
        if settings.mode == .monitor {
            loadSends(bus: settings.monitorBus)
        }
        if let d = visibleDetailStrip ?? detailStrip {
            loadDetail(d)
        }
        if settings.mode == .mixer {
            c.get(stripOverviewAddresses())
        }
    }

    /// What the strip overviews show: gain, +48, gate/EQ/comp state and the mini EQ and comp graphs.
    func stripOverviewAddresses() -> [String] {
        Requests.stripOverview()
    }

    func loadSends(bus: Int) {
        guard let c = client, bus >= 1, bus <= 16 else { return }
        c.get(Requests.sends(bus: bus))
    }

    func loadDetail(_ s: StripID) {
        client?.get(Requests.detail(s))
    }

    /// FX slot types, sources and the parameters of the editable slots.
    func loadEffects() {
        client?.get(Effects.addresses())
    }

    /// Changing an effect's type resets its parameters on the desk, so read them again.
    func setEffectType(slot: Int, type: Int) {
        setInt(Effects.typePath(slot), type)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.loadEffectParameters(slot: slot, type: type)
        }
    }

    func loadRecorder() {
        client?.get(Recorder.addresses)
    }

    func loadGenerator() {
        client?.get(Oscillator.addresses)
    }

    func loadOutputs() {
        client?.get(InputRouting.addresses + OutputRouting.addresses + Outputs.addresses())
    }

    /// Reads every parameter the slot's effect uses (64 for a dual graphic EQ).
    func loadEffectParameters(slot: Int, type: Int) {
        let count = Effects.parameterCount(slot: slot, type: type)
        client?.get((1...count).map { Effects.parPath(slot, $0) })
    }

    func loadScenes() {
        loadShow(.scenes)
    }

    /// Reads the list for one part of the show (cues also need the scene and snippet names they refer to).
    func loadShow(_ control: Show.Control) {
        guard let c = client else { return }
        var a = Show.listAddresses(control) + [Show.namePath]
        if control == .cues {
            a += (0..<100).flatMap { [Show.scenePath($0, "name"), Show.snippetPath($0, "name")] }
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
        if !restoring && AppModel.recordsUndo(address) && dragOriginals[address] == nil,
           let previous = store.value(address), previous != value {
            undoStack.record(address: address, previous: previous, newValue: value, label: undoName(address), now: X32Client.now())
            undoLabel = undoStack.last?.label
        }
        store.applyLocal(address, value)
        lastLocalSet[address] = X32Client.now()
        client?.set(address, value)
        refreshLinkedPartner(of: address)
        rereadPreampIfSourceChanged(address)
    }

    /// A channel's source decides which preamp feeds it. Whenever the source changes (from here,
    /// an undo, the desk or another app), read the preamp assignment again so gain and +48V
    /// controls never act on the wrong input.
    private func rereadPreampIfSourceChanged(_ address: String) {
        guard address.hasSuffix("/config/source"), let (strip, _) = AddressNames.split(address),
              let ha = strip.headampIndexPath else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.client?.get(ha)
        }
    }

    // MARK: - Stereo links

    /// Changing a channel's source can change which preamp feeds it (set() re-reads that).
    func setSource(_ strip: StripID, _ value: Int) {
        setInt(strip.sourcePath, value)
    }

    /// Linking copies one channel onto the other on the desk; read both again afterwards.
    func reloadAfterLink(_ a: StripID, _ b: StripID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.loadDetail(a)
            self?.loadDetail(b)
        }
    }

    func isLinked(_ strip: StripID) -> Bool {
        guard let path = strip.linkPath else { return false }
        return store.param(path).bool
    }

    @ObservationIgnored private var partnerRefresh: Set<String> = []
    @ObservationIgnored private var partnerRefreshScheduled = false

    /// The desk mirrors changes onto a linked partner but doesn't always tell us, so ask shortly after.
    private func refreshLinkedPartner(of address: String) {
        var partner = LinkSync.partnerAddress(for: address) { isLinked($0) }
        if partner == nil, address.hasPrefix("/headamp/"), address.hasSuffix("/gain") {
            partner = linkedHeadampPartner(address)
        }
        guard let p = partner else { return }
        partnerRefresh.insert(p)
        guard !partnerRefreshScheduled else { return }
        partnerRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.partnerRefreshScheduled = false
            let list = Array(self.partnerRefresh)
            self.partnerRefresh.removeAll()
            self.client?.get(list)
        }
    }

    /// Preamp gain lives on the headamp, so find the channel using it and its linked partner's headamp.
    private func linkedHeadampPartner(_ address: String) -> String? {
        let parts = address.split(separator: "/")
        guard parts.count >= 3, let ha = Int(parts[1]) else { return nil }
        for s in StripID.all(.channel) + StripID.all(.auxIn) {
            guard let path = s.headampIndexPath, store.param(path).int(or: -1) == ha, isLinked(s),
                  let partner = s.linkPartner, let pPath = partner.headampIndexPath else { continue }
            let pha = store.param(pPath).int(or: -1)
            return pha >= 0 && pha < 128 ? StripID.headampGainPath(pha) : nil
        }
        return nil
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
            finishUndoGesture(previous)
        }
        // Never drag from a value we haven't read from the desk: it would jump the real level.
        target.blocked = !store.param(address).isKnown
        if target.blocked {
            client?.get(address)
        }
        target.address = address
        touch(address, true)
        if !target.blocked {
            beginGesture([address])
        }
    }

    func endDrag(_ target: DragTarget) {
        if let address = target.address {
            touch(address, false)
            finishUndoGesture(address)
        }
        target.address = nil
        target.blocked = false
        target.steps = nil
    }

    /// Set a float on the parameter the current drag started on (or `address` if no drag).
    func dragSet(_ address: String, _ target: DragTarget, _ value: Float, steps: Int) {
        if target.blocked { return }
        // Keep the resolution the drag started with, even if the control switched mode mid-drag.
        if target.address != nil && target.steps == nil {
            target.steps = steps
        }
        setFloat(target.address ?? address, value, steps: target.steps ?? steps)
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

    /// Stores the desk's current state as scene `n` (0-99) with a name.
    func saveScene(_ n: Int, name: String) {
        guard (0..<100).contains(n) else { return }
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(31))
        client?.send(OSCMessage("/save", [.string("scene"), .int(Int32(n)), .string(trimmed), .string("")]))
        // Show it straight away, then read the list back from the desk.
        store.applyLocal(String(format: "/-show/showfile/scene/%03d/name", n), .string(trimmed))
        store.applyLocal(String(format: "/-show/showfile/scene/%03d/hasdata", n), .int(1))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.loadScenes()
        }
        showToast(String(format: "Saved scene %02d", n) + (trimmed.isEmpty ? "" : " “\(trimmed)”"))
    }

    func recallScene(_ n: Int) {
        recall(.scenes, n)
    }

    /// Fires a cue, scene or snippet on the desk.
    func recall(_ control: Show.Control, _ n: Int) {
        guard (0..<control.count).contains(n) else { return }
        clearUndo()
        client?.send(OSCMessage(control.goAction, [.int(Int32(n))]))
        // The desk's "current position" only follows the kind its show control is set to.
        if Show.Control(rawValue: store.value(Show.controlPath)?.intValue ?? -1) == control {
            store.applyLocal(Show.currentPath, .int(Int32(n)))
        }
        scheduleResync()
    }

    // MARK: - Undo

    @ObservationIgnored private let undoStack = UndoStack()
    @ObservationIgnored private var dragOriginals: [String: OSCArg] = [:]
    @ObservationIgnored private var restoring = false
    @ObservationIgnored private var toastToken = 0
    /// What the undo button would undo, if anything.
    private(set) var undoLabel: String?
    /// A short message shown at the bottom of the screen.
    var toast: String?

    /// Solo, actions and show/scene state aren't undoable, and neither are stereo links: undoing
    /// an unlink would re-link, which makes the desk copy one channel over the other.
    static func recordsUndo(_ address: String) -> Bool {
        if address.hasPrefix("/-") { return false }
        if address.hasPrefix("/config/") && address.contains("link") { return false }
        return true
    }

    func undoName(_ address: String) -> String {
        if let (strip, rest) = AddressNames.split(address) {
            return stripTitle(strip) + " " + AddressNames.parameterName(rest, strip: strip)
        }
        if let name = Effects.describe(address, type: { store.value(Effects.typePath($0))?.intValue }) {
            return name
        }
        return AddressNames.describe(address)
    }

    /// Remember where a gesture started; until it ends, its moves aren't recorded one by one.
    func beginGesture(_ addresses: [String]) {
        for a in addresses where AppModel.recordsUndo(a) && dragOriginals[a] == nil {
            if let v = store.value(a) {
                dragOriginals[a] = v
            }
        }
    }

    /// A whole gesture is one undo step, back to where the finger first landed.
    func endGesture(_ addresses: [String], label: String) {
        var changes: [UndoEntry.Change] = []
        for a in addresses where store.param(a).touchCount == 0 {
            if let original = dragOriginals.removeValue(forKey: a), let now = store.value(a), now != original {
                changes.append(UndoEntry.Change(address: a, previous: original))
            }
        }
        if !changes.isEmpty {
            undoStack.push(UndoEntry(label: label, changes: changes, time: X32Client.now()))
            undoLabel = undoStack.last?.label
        }
    }

    private func finishUndoGesture(_ address: String) {
        endGesture([address], label: undoName(address))
    }

    func undo() {
        guard let entry = undoStack.last else { return }
        // Undoing something a finger is still moving would be overwritten straight away.
        if entry.changes.contains(where: { store.param($0.address).touchCount > 0 }) {
            showToast("Let go of the control first")
            return
        }
        _ = undoStack.popLast()
        restoring = true
        for change in entry.changes.reversed() {
            set(change.address, change.previous)
        }
        restoring = false
        undoLabel = undoStack.last?.label
        Haptics.click()
        showToast("Undone: \(entry.label)")
    }

    func clearUndo() {
        undoStack.clear()
        dragOriginals.removeAll()
        undoLabel = nil
    }

    /// Sets several parameters as one undoable step (e.g. pasting an EQ).
    func applyBatch(_ changes: [(String, OSCArg)], label: String) {
        var previous: [UndoEntry.Change] = []
        for (address, value) in changes {
            // Nothing to undo for values that were already there.
            if let v = store.value(address), v != value {
                previous.append(UndoEntry.Change(address: address, previous: v))
            }
        }
        restoring = true
        for (address, value) in changes {
            set(address, value)
        }
        restoring = false
        undoStack.push(UndoEntry(label: label, changes: previous, time: X32Client.now()))
        undoLabel = undoStack.last?.label
    }

    func showToast(_ text: String) {
        toastToken += 1
        let token = toastToken
        withAnimation(.easeOut(duration: 0.15)) {
            toast = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, self.toastToken == token else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                self.toast = nil
            }
        }
    }

    // MARK: - Copy and paste

    /// Channel settings copied from the channel view.
    var clipboard: ChannelClipboard?

    /// Addresses of `sections` on `strip` that haven't been read from the desk yet.
    private func missing(_ strip: StripID, _ sections: [ProcessingSection]) -> [String] {
        sections.flatMap { strip.relativePaths($0) }.map { strip.base + $0 }.filter { store.value($0) == nil }
    }

    func copySettings(from strip: StripID, sections: [ProcessingSection]) {
        // Never copy half a section: the paste would mix two channels' settings.
        let gaps = missing(strip, sections)
        if !gaps.isEmpty {
            client?.get(gaps)
            showToast("Still reading \(stripTitle(strip)) from the desk, try again in a moment")
            return
        }
        clipboard = ChannelClipboard.copy(from: strip, sections: sections) { store.value($0) }
        let names = clipboard?.sections.map(\.title).joined(separator: ", ") ?? ""
        showToast("Copied \(names) from \(stripTitle(strip))")
    }

    func pasteSettings(onto strip: StripID) {
        guard let clip = clipboard else { return }
        apply(clip, onto: strip, label: "paste", done: "Pasted")
    }

    private func apply(_ clip: ChannelClipboard, onto strip: StripID, label: String, done: String) {
        let changes = clip.changes(onto: strip)
        guard !changes.isEmpty else { return }
        // Read the target first so the paste can be undone completely.
        let gaps = changes.map(\.0).filter { store.value($0) == nil }
        if !gaps.isEmpty {
            client?.get(gaps)
            showToast("Still reading \(stripTitle(strip)) from the desk, try again in a moment")
            return
        }
        let names = clip.sections(for: strip).map(\.title).joined(separator: ", ")
        applyBatch(changes, label: "\(label) \(names) onto \(stripTitle(strip))")
        showToast("\(done) \(names) onto \(stripTitle(strip))")
    }

    // MARK: - Presets

    private(set) var presets: [ChannelPreset] = PresetLibrary.sorted(PresetLibrary.load())

    func savePreset(name: String, from strip: StripID) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sections = ChannelPreset.sections.filter { strip.supports($0) }
        guard !sections.isEmpty else { return }
        let gaps = missing(strip, sections)
        if !gaps.isEmpty {
            client?.get(gaps)
            showToast("Still reading \(stripTitle(strip)) from the desk, try again in a moment")
            return
        }
        let clip = ChannelClipboard.copy(from: strip, sections: sections) { store.value($0) }
        // Saving under an existing name replaces that preset.
        var list = presets.filter { $0.name.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.append(ChannelPreset(name: trimmed, clip: clip))
        presets = PresetLibrary.sorted(list)
        PresetLibrary.save(presets)
        showToast("Saved preset \"\(trimmed)\"")
    }

    func loadPreset(_ preset: ChannelPreset, only sections: [ProcessingSection]? = nil, onto strip: StripID) {
        apply(preset.clipboard(only: sections), onto: strip, label: "preset \(preset.name):", done: "Loaded \(preset.name):")
    }

    func deletePreset(_ preset: ChannelPreset) {
        presets.removeAll { $0.id == preset.id }
        PresetLibrary.save(presets)
    }

    // MARK: - Navigation

    func openDetail(_ strip: StripID, tab: DetailTab? = nil) {
        if let tab {
            detailTab = tab
        }
        if !DetailTab.available(for: strip).contains(detailTab) {
            detailTab = DetailTab.available(for: strip).first ?? .setup
        }
        loadDetail(strip)
        valueEditor = nil
        selectedStrip = strip
        detailStrip = strip
        selectOnDesk(strip)
    }

    /// Selects the strip on the desk's own screen, if that's turned on in Settings.
    func selectOnDesk(_ strip: StripID) {
        guard settings.selectOnDesk, strip.kind != .dca else { return }
        // The desk numbers strips 0-71 in the same order as its solo switches (1-72).
        client?.set("/-stat/selidx", .int(Int32(strip.soloIndex - 1)))
    }

    func selectLayer(_ newLayer: MixerLayer) {
        layer = newLayer
        spillDCA = nil
        if !newLayer.supportsBusSends {
            sendsBus = nil
            gainOnFaders = false
        }
    }

    func selectSendsBus(_ bus: Int?) {
        sendsBus = bus
        gainOnFaders = false
        if let b = bus {
            loadSends(bus: b)
            if !layer.supportsBusSends && spillDCA == nil {
                layer = .inputs1
            }
        }
    }

    /// Faders become preamp gain for the input channels (tap again to go back).
    func toggleGainOnFaders() {
        gainOnFaders.toggle()
        if gainOnFaders {
            sendsBus = nil
            if !layer.supportsBusSends && spillDCA == nil {
                layer = .inputs1
            }
        }
    }

    /// Shows the channels assigned to a DCA (tap the same DCA again to go back).
    func spill(_ dca: Int) {
        spillDCA = spillDCA == dca ? nil : dca
        if spillDCA == nil && !layer.supportsBusSends {
            sendsBus = nil
            gainOnFaders = false
        }
    }

    func layerTitle(_ l: MixerLayer) -> String {
        if let i = l.userIndex, i < settings.userLayerNames.count {
            let name = settings.userLayerNames[i].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? l.title : name
        }
        return l.title
    }

    func strips(for l: MixerLayer) -> [StripID] {
        if let i = l.userIndex {
            guard i < settings.userLayers.count else { return [] }
            return settings.userLayers[i].compactMap { StripID(id: $0) }
        }
        return l.strips
    }

    /// What the mixer shows right now: a DCA spill, or the selected layer.
    var visibleStrips: [StripID] {
        if let d = spillDCA {
            return StripID.dcaMembers(d) { s in
                guard let path = s.dcaGroupsPath else { return nil }
                let p = store.param(path)
                return p.isKnown ? p.int : nil
            }
        }
        return strips(for: layer)
    }

    func setUserLayer(_ index: Int, strips: [StripID]) {
        updateSettings { s in
            while s.userLayers.count <= index { s.userLayers.append([]) }
            s.userLayers[index] = strips.map(\.id)
        }
    }

    func setUserLayerName(_ index: Int, _ name: String) {
        updateSettings { s in
            while s.userLayerNames.count <= index { s.userLayerNames.append("User \(s.userLayerNames.count + 1)") }
            s.userLayerNames[index] = name
        }
    }

    // MARK: - Precision editing

    func editValue(_ title: String, _ address: String, _ spec: ParamSpec, reset: Float? = nil, style: ValueEditRequest.Style = .normal) {
        if !store.param(address).isKnown {
            client?.get(address)
        }
        valueEditor = ValueEditRequest(title: title, address: address, spec: spec, resetNorm: reset, style: style)
    }

    /// Short name for a strip, e.g. "Ch 16 Lead Vox".
    func stripTitle(_ strip: StripID) -> String {
        let name = param(strip.namePath).string
        return name.isEmpty ? strip.footLabel : "\(strip.footLabel) \(name)"
    }

    // MARK: - Launch arguments (used for automated screenshots)

    func applyLaunchArguments() {
        guard !didApplyLaunchArguments else { return }
        didApplyLaunchArguments = true
        let d = UserDefaults.standard
        if let mode = d.string(forKey: "autoMode"), let m = AppMode(rawValue: mode) {
            updateSettings { $0.mode = m }
        }
        if d.object(forKey: "autoRTA") != nil {
            let on = d.bool(forKey: "autoRTA")
            updateSettings { $0.showRTA = on }
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
        if let tabName = d.string(forKey: "autoTab"), let t = DetailTab(rawValue: tabName == "dynamics" ? "comp" : tabName) {
            detailTab = t
        }
        if let detail = d.string(forKey: "autoDetail") {
            let parts = detail.split(separator: "-")
            if parts.count == 2, let kind = StripKind(rawValue: String(parts[0])), let n = Int(parts[1]), (1...kind.count).contains(n) {
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
                if s == .outputs {
                    self?.loadOutputs()
                }
                if s == .recorder {
                    self?.loadRecorder()
                }
                if s == .generator {
                    self?.loadGenerator()
                }
                if s == .scenes, let tab = d.string(forKey: "autoShowTab") {
                    self?.autoShowTab = ["cues": .cues, "scenes": .scenes, "snippets": .snippets][tab]
                }
                if s == .effects {
                    let slot = d.integer(forKey: "autoFXSlot")
                    if Effects.slots.contains(slot) { self?.effectsSlot = slot }
                    if d.object(forKey: "autoFXType") != nil, Effects.slots.contains(slot) {
                        self?.setEffectType(slot: slot, type: d.integer(forKey: "autoFXType"))
                    }
                    self?.loadEffects()
                }
                self?.sheet = s
            }
        }
        if let popover = d.string(forKey: "autoPopover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.autoPopover = popover
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

/// What the precision editor is editing.
struct ValueEditRequest: Identifiable {
    enum Style { case normal, pan }

    let id = UUID()
    let title: String
    let address: String
    let spec: ParamSpec
    let resetNorm: Float?
    var style: Style = .normal
}

/// Remembers which parameter a drag started on (held in a view's @State).
final class DragTarget {
    var address: String?
    var blocked = false
    var steps: Int?
}

/// Pages of the channel view, one per processing block.
enum DetailTab: String, CaseIterable, Identifiable {
    case overview, input, gate, eq, comp, sends, setup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .input: return "Input"
        case .gate: return "Gate"
        case .eq: return "EQ"
        case .comp: return "Compressor"
        case .sends: return "Sends"
        case .setup: return "Config"
        }
    }

    static func available(for strip: StripID) -> [DetailTab] {
        if strip.kind == .dca { return [.setup] }
        var tabs: [DetailTab] = [.overview]
        if strip.hasInputPage { tabs.append(.input) }
        if strip.hasGate { tabs.append(.gate) }
        if strip.hasEQ { tabs.append(.eq) }
        if strip.hasDynamics { tabs.append(.comp) }
        if strip.hasSendsPage { tabs.append(.sends) }
        tabs.append(.setup)
        return tabs
    }
}
