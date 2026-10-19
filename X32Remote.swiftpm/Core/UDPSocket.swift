import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum UDPSocketError: Error {
    case createFailed(Int32)
    case bindFailed(Int32)
}

// Small platform shims so the networking code can also be tested on Linux.
#if canImport(Darwin)
private let udpSocketType = SOCK_DGRAM
private let udpProtocol = Int32(IPPROTO_UDP)
private func closeSocket(_ fd: Int32) { _ = Darwin.close(fd) }
private func bindSocket(_ fd: Int32, _ address: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 {
    Darwin.bind(fd, address, length)
}
#else
private let udpSocketType = Int32(SOCK_DGRAM.rawValue)
private let udpProtocol = Int32(IPPROTO_UDP)
private func closeSocket(_ fd: Int32) { _ = Glibc.close(fd) }
private func bindSocket(_ fd: Int32, _ address: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 {
    Glibc.bind(fd, address, length)
}
#endif

private func makeSockaddrIn(port: UInt16, address: in_addr) -> sockaddr_in {
    var addr = sockaddr_in()
    #if canImport(Darwin)
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr = address
    return addr
}

/// A small non-blocking IPv4 UDP socket built on BSD sockets and a GCD read source.
/// Sending is safe from any thread; `onReceive` is called on the socket's private queue.
final class UDPSocket {
    private let fd: Int32
    private let queue: DispatchQueue
    private var readSource: DispatchSourceRead?
    private var closed = false
    private let lock = NSLock()

    /// (payload, sender IPv4 address)
    var onReceive: ((Data, String) -> Void)?

    init(label: String = "x32remote.udp") throws {
        queue = DispatchQueue(label: label, qos: .userInteractive)
        let s = socket(AF_INET, udpSocketType, udpProtocol)
        guard s >= 0 else {
            throw UDPSocketError.createFailed(errno)
        }
        fd = s

        var on: Int32 = 1
        _ = setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        #if canImport(Darwin)
        var noSigPipe: Int32 = 1
        _ = setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        #endif
        var bufferSize: Int32 = 1 << 20
        _ = setsockopt(s, SOL_SOCKET, SO_RCVBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(s, F_GETFL, 0)
        _ = fcntl(s, F_SETFL, flags | O_NONBLOCK)

        var addr = makeSockaddrIn(port: 0, address: in_addr(s_addr: 0))
        let bound = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa -> Int32 in
                bindSocket(s, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 {
            let err = errno
            closeSocket(s)
            throw UDPSocketError.bindFailed(err)
        }
    }

    deinit {
        invalidate()
    }

    /// Starts delivering incoming datagrams to `onReceive`.
    func start() {
        guard readSource == nil else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.drain()
        }
        let s = fd
        source.setCancelHandler {
            closeSocket(s)
        }
        readSource = source
        source.resume()
    }

    /// Stops receiving and closes the socket.
    func invalidate() {
        lock.lock()
        let wasClosed = closed
        closed = true
        lock.unlock()
        if wasClosed { return }
        onReceive = nil
        if let source = readSource {
            source.cancel()
            readSource = nil
        } else {
            closeSocket(fd)
        }
    }

    @discardableResult
    func send(_ data: Data, to host: String, port: UInt16) -> Bool {
        lock.lock()
        let isClosed = closed
        lock.unlock()
        if isClosed { return false }

        var target = in_addr()
        guard inet_pton(AF_INET, host, &target) == 1 else {
            return false
        }
        var addr = makeSockaddrIn(port: port, address: target)
        let s = fd
        let sent: Int = data.withUnsafeBytes { raw -> Int in
            withUnsafePointer(to: &addr) { ptr -> Int in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa -> Int in
                    sendto(s, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == data.count
    }

    private func drain() {
        let s = fd
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            var from = sockaddr_in()
            var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n: Int = buffer.withUnsafeMutableBytes { raw -> Int in
                withUnsafeMutablePointer(to: &from) { ptr -> Int in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa -> Int in
                        recvfrom(s, raw.baseAddress, raw.count, 0, sa, &fromLength)
                    }
                }
            }
            if n <= 0 { break }
            let data = Data(buffer[0..<n])
            let ip = String(cString: inet_ntoa(from.sin_addr))
            onReceive?(data, ip)
        }
    }
}

/// An IPv4 address and netmask of one local network interface (host byte order).
struct LocalIPv4Interface: Equatable {
    let name: String
    let address: UInt32
    let netmask: UInt32

    var addressString: String { LocalIPv4Interface.format(address) }

    /// Hosts on this interface's subnet, capped to the /24 around our own address for large subnets.
    var scanTargets: [String] {
        var mask = netmask
        if mask < 0xFFFF_FC00 {   // bigger than /22: only sweep our own /24
            mask = 0xFFFF_FF00
        }
        let network = address & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        var result: [String] = []
        var host = network + 1
        while host < broadcast {
            if host != address {
                result.append(LocalIPv4Interface.format(host))
            }
            host += 1
        }
        return result
    }

    static func format(_ v: UInt32) -> String {
        let a = (v >> 24) & 0xFF
        let b = (v >> 16) & 0xFF
        let c = (v >> 8) & 0xFF
        let d = v & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }

    /// Broadcast-capable, running IPv4 interfaces (Wi-Fi, Ethernet). Excludes loopback, VPN and cellular.
    static func all() -> [LocalIPv4Interface] {
        var result: [LocalIPv4Interface] = []
        var listPointer: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&listPointer) == 0, let first = listPointer else {
            return []
        }
        defer { freeifaddrs(first) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let flags = Int32(truncatingIfNeeded: entry.pointee.ifa_flags)
            let isUp = (flags & Int32(IFF_UP)) != 0 && (flags & Int32(IFF_RUNNING)) != 0
            let isLoopback = (flags & Int32(IFF_LOOPBACK)) != 0
            let canBroadcast = (flags & Int32(IFF_BROADCAST)) != 0
            if isUp && !isLoopback && canBroadcast,
               let sa = entry.pointee.ifa_addr,
               let nm = entry.pointee.ifa_netmask,
               sa.pointee.sa_family == sa_family_t(AF_INET) {
                let rawAddress = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                let rawMask = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                let item = LocalIPv4Interface(
                    name: String(cString: entry.pointee.ifa_name),
                    address: UInt32(bigEndian: rawAddress),
                    netmask: UInt32(bigEndian: rawMask)
                )
                if !result.contains(item) {
                    result.append(item)
                }
            }
            cursor = entry.pointee.ifa_next
        }
        return result
    }
}
