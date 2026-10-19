import Foundation

/// One OSC argument, limited to the types the X32 uses.
enum OSCArg: Equatable {
    case int(Int32)
    case float(Float)
    case string(String)
    case blob(Data)

    var floatValue: Float? {
        switch self {
        case .float(let f): return f
        case .int(let i): return Float(i)
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let i): return Int(i)
        case .float(let f):
            guard f.isFinite, abs(f) < 1_000_000_000 else { return nil }
            return Int(f.rounded())
        default: return nil
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var typeTag: Character {
        switch self {
        case .int: return "i"
        case .float: return "f"
        case .string: return "s"
        case .blob: return "b"
        }
    }
}

/// An OSC message: an address pattern plus arguments.
struct OSCMessage: Equatable {
    var address: String
    var args: [OSCArg]

    init(_ address: String, _ args: [OSCArg] = []) {
        self.address = address
        self.args = args
    }
}

/// Encodes and decodes OSC 1.0 messages (big-endian, 4-byte aligned).
enum OSCCodec {

    static func encode(_ message: OSCMessage) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        appendString(message.address, to: &bytes)
        var tags = ","
        for arg in message.args {
            tags.append(arg.typeTag)
        }
        appendString(tags, to: &bytes)
        for arg in message.args {
            switch arg {
            case .int(let v):
                appendUInt32(UInt32(bitPattern: v), to: &bytes)
            case .float(let v):
                appendUInt32(v.bitPattern, to: &bytes)
            case .string(let s):
                appendString(s, to: &bytes)
            case .blob(let d):
                appendUInt32(UInt32(d.count), to: &bytes)
                bytes.append(contentsOf: [UInt8](d))
                while bytes.count % 4 != 0 {
                    bytes.append(0)
                }
            }
        }
        return Data(bytes)
    }

    static func decode(_ data: Data) -> OSCMessage? {
        let bytes = [UInt8](data)
        var offset = 0
        guard let address = readString(bytes, &offset), address.hasPrefix("/") else {
            return nil
        }
        if offset >= bytes.count {
            return OSCMessage(address)
        }
        guard let tags = readString(bytes, &offset), tags.hasPrefix(",") else {
            return OSCMessage(address)
        }
        var args: [OSCArg] = []
        for tag in tags.dropFirst() {
            switch tag {
            case "i":
                guard let v = readUInt32(bytes, &offset) else { return nil }
                args.append(.int(Int32(bitPattern: v)))
            case "f":
                guard let v = readUInt32(bytes, &offset) else { return nil }
                args.append(.float(Float(bitPattern: v)))
            case "s":
                guard let s = readString(bytes, &offset) else { return nil }
                args.append(.string(s))
            case "b":
                guard let n = readUInt32(bytes, &offset) else { return nil }
                let length = Int(n)
                guard offset + length <= bytes.count else { return nil }
                args.append(.blob(Data(bytes[offset..<(offset + length)])))
                offset += (length + 3) & ~3
            case "T", "F", "N", "I":
                continue
            default:
                return OSCMessage(address, args)
            }
        }
        return OSCMessage(address, args)
    }

    // MARK: - Helpers

    private static func appendString(_ s: String, to bytes: inout [UInt8]) {
        bytes.append(contentsOf: Array(s.utf8))
        bytes.append(0)
        while bytes.count % 4 != 0 {
            bytes.append(0)
        }
    }

    private static func appendUInt32(_ v: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8(truncatingIfNeeded: v >> 24))
        bytes.append(UInt8(truncatingIfNeeded: v >> 16))
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
        bytes.append(UInt8(truncatingIfNeeded: v))
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: inout Int) -> UInt32? {
        guard offset + 4 <= bytes.count else { return nil }
        let b0 = UInt32(bytes[offset]) << 24
        let b1 = UInt32(bytes[offset + 1]) << 16
        let b2 = UInt32(bytes[offset + 2]) << 8
        let b3 = UInt32(bytes[offset + 3])
        offset += 4
        return b0 | b1 | b2 | b3
    }

    private static func readString(_ bytes: [UInt8], _ offset: inout Int) -> String? {
        guard offset < bytes.count else { return nil }
        var end = offset
        while end < bytes.count && bytes[end] != 0 {
            end += 1
        }
        guard end < bytes.count else { return nil }
        let s = String(decoding: bytes[offset..<end], as: UTF8.self)
        offset = (end + 4) & ~3
        return s
    }
}

/// Decodes the blob the X32 sends for /meters/N: a little-endian count followed by little-endian floats.
enum MeterBlob {
    static func floats(from blob: Data) -> [Float] {
        let bytes = [UInt8](blob)
        guard bytes.count >= 4 else { return [] }
        let count = Int(littleEndianUInt32(bytes, 0))
        let available = (bytes.count - 4) / 4
        let n = max(0, min(count, available))
        var result: [Float] = []
        result.reserveCapacity(n)
        var offset = 4
        for _ in 0..<n {
            result.append(Float(bitPattern: littleEndianUInt32(bytes, offset)))
            offset += 4
        }
        return result
    }

    static func encode(_ values: [Float]) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(4 + values.count * 4)
        appendLE(UInt32(values.count), &bytes)
        for v in values {
            appendLE(v.bitPattern, &bytes)
        }
        return Data(bytes)
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        let b0 = UInt32(bytes[offset])
        let b1 = UInt32(bytes[offset + 1]) << 8
        let b2 = UInt32(bytes[offset + 2]) << 16
        let b3 = UInt32(bytes[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    private static func appendLE(_ v: UInt32, _ bytes: inout [UInt8]) {
        bytes.append(UInt8(truncatingIfNeeded: v))
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
        bytes.append(UInt8(truncatingIfNeeded: v >> 16))
        bytes.append(UInt8(truncatingIfNeeded: v >> 24))
    }
}
