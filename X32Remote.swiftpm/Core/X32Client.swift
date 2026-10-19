import Foundation

struct ConsoleInfo: Equatable {
    var ip: String
    var name: String
    var model: String
    var firmware: String
}

/// Something that can carry OSC messages to and from a console (real UDP or the demo desk).
protocol X32Transport: AnyObject {
    /// Always delivered on the main queue.
    var onMessage: ((OSCMessage) -> Void)? { get set }
    var displayAddress: String { get }
    func send(_ message: OSCMessage)
    func close()
}

/// Talks to a real console on UDP port 10023.
final class UDPTransport: X32Transport {
    let host: String
    let port: UInt16
    private let socket: UDPSocket
    var onMessage: ((OSCMessage) -> Void)?
    var displayAddress: String { host }

    init(host: String, port: UInt16 = 10023) throws {
        self.host = host
        self.port = port
        self.socket = try UDPSocket()
        let expectedSender = host
        socket.onReceive = { [weak self] data, sender in
            guard sender == expectedSender, let message = OSCCodec.decode(data) else { return }
            DispatchQueue.main.async {
                self?.onMessage?(message)
            }
        }
        socket.start()
    }

    func send(_ message: OSCMessage) {
        socket.send(OSCCodec.encode(message), to: host, port: port)
    }

    func close() {
        onMessage = nil
        socket.invalidate()
    }
}

/// Keeps a session with one X32 alive: /xremote renewals, meter subscriptions,
/// a windowed queue of parameter requests with retries, and coalesced parameter changes.
/// Use from the main thread only.
final class X32Client {
    enum Status: Equatable {
        case connecting
        case connected
        case lost
    }

    let transport: X32Transport
    private(set) var status: Status = .connecting
    private(set) var info: ConsoleInfo?

    var onStatus: ((Status) -> Void)?
    var onInfo: ((ConsoleInfo) -> Void)?
    var onMessage: ((OSCMessage) -> Void)?
    var onMeters: ((Int, [Float]) -> Void)?

    private struct Outstanding {
        var sentAt: TimeInterval
        var attempts: Int
    }

    private var requestQueue: [String] = []
    private var queueHead = 0
    private var queued: Set<String> = []
    private var outstanding: [String: Outstanding] = [:]
    private let window = 32
    private let retryAfter: TimeInterval = 0.5
    private let maxAttempts = 3

    private var pendingSets: [String: OSCArg] = [:]
    private var pendingOrder: [String] = []
    private var flushScheduled = false

    private var meterRequests: [OSCMessage] = []
    private var lastMeterRenew: TimeInterval = 0
    private var lastXRemote: TimeInterval = 0
    private var lastReceive: TimeInterval = 0
    private var lastPing: TimeInterval = 0
    private let createdAt: TimeInterval
    private var timer: Timer?

    static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    init(transport: X32Transport) {
        self.transport = transport
        self.createdAt = X32Client.now()
        transport.onMessage = { [weak self] message in
            self?.receive(message)
        }
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        ping()
    }

    deinit {
        timer?.invalidate()
    }

    var secondsSinceStart: TimeInterval {
        X32Client.now() - createdAt
    }

    /// Number of parameter requests not yet answered.
    var pendingRequests: Int {
        (requestQueue.count - queueHead) + outstanding.count
    }

    func close() {
        timer?.invalidate()
        timer = nil
        onStatus = nil
        onInfo = nil
        onMessage = nil
        onMeters = nil
        transport.close()
    }

    // MARK: - Requests and changes

    /// Ask the desk for the current value of a parameter.
    func get(_ address: String) {
        get([address])
    }

    func get(_ addresses: [String]) {
        for address in addresses where outstanding[address] == nil && !queued.contains(address) {
            queued.insert(address)
            requestQueue.append(address)
        }
        pump()
    }

    /// Change a parameter. Rapid changes to the same address are coalesced (about 80 per second max).
    func set(_ address: String, _ value: OSCArg) {
        if pendingSets[address] == nil {
            pendingOrder.append(address)
        }
        pendingSets[address] = value
        if !flushScheduled {
            flushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { [weak self] in
                self?.flushSets()
            }
        }
    }

    /// Send a message immediately (actions such as scene recall).
    func send(_ message: OSCMessage) {
        transport.send(message)
    }

    /// Meter blocks to keep subscribed (renewed every 8 s).
    func setMeterSubscriptions(_ blocks: [Int]) {
        meterRequests = blocks.map { block in
            OSCMessage("/meters", [.string("/meters/\(block)"), .int(0), .int(0), .int(1)])
        }
        if status == .connected {
            renewMeters()
        }
    }

    // MARK: - Internals

    private func flushSets() {
        flushScheduled = false
        let order = pendingOrder
        let values = pendingSets
        pendingOrder.removeAll()
        pendingSets.removeAll()
        for address in order {
            if let v = values[address] {
                transport.send(OSCMessage(address, [v]))
            }
        }
    }

    private func pump() {
        guard status == .connected else { return }
        let t = X32Client.now()
        while outstanding.count < window && queueHead < requestQueue.count {
            let address = requestQueue[queueHead]
            queueHead += 1
            queued.remove(address)
            outstanding[address] = Outstanding(sentAt: t, attempts: 1)
            transport.send(OSCMessage(address))
        }
        if queueHead >= requestQueue.count {
            requestQueue.removeAll(keepingCapacity: true)
            queueHead = 0
        } else if queueHead > 1024 {
            requestQueue.removeFirst(queueHead)
            queueHead = 0
        }
    }

    private func ping() {
        lastPing = X32Client.now()
        transport.send(OSCMessage("/xinfo"))
    }

    private func sendXRemote() {
        lastXRemote = X32Client.now()
        transport.send(OSCMessage("/xremote"))
    }

    private func renewMeters() {
        lastMeterRenew = X32Client.now()
        for request in meterRequests {
            transport.send(request)
        }
    }

    private func setStatus(_ s: Status) {
        guard s != status else { return }
        status = s
        onStatus?(s)
    }

    private func receive(_ message: OSCMessage) {
        lastReceive = X32Client.now()
        if status != .connected {
            setStatus(.connected)
            sendXRemote()
            renewMeters()
            pump()
        }

        let address = message.address
        if address.hasPrefix("/meters/") {
            if let block = Int(address.dropFirst(8)), case .blob(let data)? = message.args.first {
                onMeters?(block, MeterBlob.floats(from: data))
            }
            return
        }
        if address == "/xinfo" || address == "/info" {
            let strings = message.args.compactMap { $0.stringValue }
            if strings.count >= 4 {
                let parsed: ConsoleInfo
                if address == "/xinfo" {
                    parsed = ConsoleInfo(ip: strings[0], name: strings[1], model: strings[2], firmware: strings[3])
                } else {
                    parsed = ConsoleInfo(ip: transport.displayAddress, name: strings[1], model: strings[2], firmware: strings[3])
                }
                if parsed != info {
                    info = parsed
                    onInfo?(parsed)
                }
            }
            return
        }
        if address == "/status" {
            return
        }
        if outstanding.removeValue(forKey: address) != nil {
            pump()
        }
        onMessage?(message)
    }

    private func tick() {
        let t = X32Client.now()
        if status != .connecting {
            if t - lastXRemote >= 8 {
                sendXRemote()
            }
            if !meterRequests.isEmpty && t - lastMeterRenew >= 8 {
                renewMeters()
            }
        }
        if t - lastReceive >= 1.5 && t - lastPing >= 1.0 {
            ping()
        }
        if status == .connected && t - lastReceive > 5 {
            setStatus(.lost)
        }
        guard status == .connected, !outstanding.isEmpty else { return }
        var expired: [String] = []
        for (address, entry) in outstanding where t - entry.sentAt > retryAfter {
            expired.append(address)
        }
        for address in expired {
            guard var entry = outstanding[address] else { continue }
            if entry.attempts >= maxAttempts {
                outstanding.removeValue(forKey: address)
            } else {
                entry.attempts += 1
                entry.sentAt = t
                outstanding[address] = entry
                transport.send(OSCMessage(address))
            }
        }
        pump()
    }
}
