import Foundation

/// Finds X32/M32 consoles by sending /xinfo to every address on the local subnets.
/// (iOS needs a special entitlement for broadcast, so this uses plain unicast.)
final class X32Discovery {
    struct Console: Identifiable, Equatable {
        var id: String { ip }
        let ip: String
        let name: String
        let model: String
        let firmware: String
    }

    private(set) var consoles: [Console] = []
    var onChange: (([Console]) -> Void)?

    private var socket: UDPSocket?
    private var timer: Timer?
    private var generation = 0

    var isRunning: Bool { socket != nil }

    func start() {
        stop()
        guard let s = try? UDPSocket(label: "x32remote.discovery") else { return }
        s.onReceive = { [weak self] data, sender in
            guard let message = OSCCodec.decode(data),
                  message.address == "/xinfo" || message.address == "/info" else { return }
            let strings = message.args.compactMap { $0.stringValue }
            DispatchQueue.main.async {
                self?.add(sender: sender, strings: strings)
            }
        }
        s.start()
        socket = s
        sweep()
        let t = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            self?.sweep()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        generation += 1
        timer?.invalidate()
        timer = nil
        socket?.invalidate()
        socket = nil
    }

    private func add(sender: String, strings: [String]) {
        guard strings.count >= 4 else { return }
        let console = Console(ip: sender, name: strings[1], model: strings[2], firmware: strings[3])
        if let i = consoles.firstIndex(where: { $0.ip == sender }) {
            if consoles[i] == console { return }
            consoles[i] = console
        } else {
            consoles.append(console)
            consoles.sort { $0.ip.compare($1.ip, options: .numeric) == .orderedAscending }
        }
        onChange?(consoles)
    }

    private func sweep() {
        guard socket != nil else { return }
        var targets: [String] = []
        for interface in LocalIPv4Interface.all() {
            for ip in interface.scanTargets where !targets.contains(ip) {
                targets.append(ip)
            }
        }
        let packet = OSCCodec.encode(OSCMessage("/xinfo"))
        let batchSize = 32
        let currentGeneration = generation
        var batchIndex = 0
        var start = 0
        while start < targets.count {
            let end = min(start + batchSize, targets.count)
            let batch = Array(targets[start..<end])
            let delay = Double(batchIndex) * 0.03
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.generation == currentGeneration, let s = self.socket else { return }
                for ip in batch {
                    s.send(packet, to: ip, port: 10023)
                }
            }
            batchIndex += 1
            start = end
        }
    }
}
