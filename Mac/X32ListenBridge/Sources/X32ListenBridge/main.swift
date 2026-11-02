// X32 Listen Bridge
//
// Runs on a Mac plugged into the X32's USB port. Takes the two USB channels carrying the desk's
// solo bus (set up from X32 Remote: Listen › On the desk) and streams them over the local
// network to X32 Remote, which plays them into the earphones plugged into the iPad.
//
//     swift run -c release                       # finds the X32 by itself, channels 31/32
//     swift run -c release -- --channels 23,24   # if solo is on outputs 7/8 instead
//     swift run -c release -- --list             # the Mac's audio inputs
//     swift run -c release -- --device "X-USB"   # pick the input by (part of) its name
//     swift run -c release -- --tone             # a test tone, no desk needed

import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import Network

setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - Options

struct Options {
    var deviceMatch: String?
    var left = 31
    var right = 32
    var listOnly = false
    /// Stream a quiet test tone instead of the desk (checks the Wi-Fi and the iPad without a desk).
    var tone = false
}

func printUsage() {
    print("""
    X32 Listen Bridge: streams the X32's solo bus to X32 Remote on an iPad.

      --channels L,R   USB channels carrying solo (default 31,32: desk outputs 15/16)
      --device NAME    the audio input to use (default: the first one called X-USB, X32 or M32)
      --list           show this Mac's audio inputs and stop
      --tone           send a quiet test tone instead (check the Wi-Fi and the iPad without a desk)
    """)
}

func parseOptions() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--list", "-l":
            o.listOnly = true
        case "--tone", "-t":
            o.tone = true
        case "--device", "-d":
            guard !args.isEmpty else { printUsage(); exit(1) }
            o.deviceMatch = args.removeFirst()
        case "--channels", "-c":
            guard !args.isEmpty else { printUsage(); exit(1) }
            let parts = args.removeFirst().split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard let first = parts.first, first >= 1 else { printUsage(); exit(1) }
            o.left = first
            o.right = parts.count > 1 ? parts[1] : first
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            print("Unknown option \(a)\n")
            printUsage()
            exit(1)
        }
    }
    return o
}

// MARK: - Audio devices

struct InputDevice {
    let id: AudioDeviceID
    let name: String
    let channels: Int
}

func propertyAddress(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func inputDevices() -> [InputDevice] {
    var address = propertyAddress(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.compactMap { id in
        let channels = inputChannelCount(id)
        return channels > 0 ? InputDevice(id: id, name: deviceName(id), channels: channels) : nil
    }
}

func deviceName(_ id: AudioDeviceID) -> String {
    var address = propertyAddress(kAudioObjectPropertyName)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let n = name else { return "Device \(id)" }
    return n.takeRetainedValue() as String
}

func inputChannelCount(_ id: AudioDeviceID) -> Int {
    var address = propertyAddress(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeInput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

/// Smaller hardware buffers mean less delay.
func requestBufferFrames(_ id: AudioDeviceID, _ frames: UInt32) {
    var address = propertyAddress(kAudioDevicePropertyBufferFrameSize)
    var f = frames
    _ = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &f)
}

struct BridgeError: Error, CustomStringConvertible {
    let description: String
}

func check(_ status: OSStatus, _ what: String) throws {
    if status != noErr { throw BridgeError(description: "Couldn't \(what) (error \(status))") }
}

// MARK: - Capture (two channels from the desk's USB card)

/// Reads two channels of an input device with the HAL audio unit (input only, no output).
final class Capture {
    let device: InputDevice
    let left: Int
    let right: Int
    private(set) var sampleRate: Double = 48000
    /// Called on the audio thread with each block of the two channels.
    var onAudio: ((UnsafePointer<Float>, UnsafePointer<Float>, Int) -> Void)?

    private var unit: AudioUnit?
    private let maxFrames = 4096
    private let leftData: UnsafeMutablePointer<Float>
    private let rightData: UnsafeMutablePointer<Float>
    private let buffers: UnsafeMutableAudioBufferListPointer

    init(device: InputDevice, left: Int, right: Int) {
        self.device = device
        self.left = left
        self.right = right
        leftData = .allocate(capacity: maxFrames)
        rightData = .allocate(capacity: maxFrames)
        buffers = AudioBufferList.allocate(maximumBuffers: 2)
    }

    func start() throws {
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { throw BridgeError(description: "No audio input unit on this Mac") }
        var created: AudioUnit?
        try check(AudioComponentInstanceNew(component, &created), "open audio input")
        guard let unit = created else { throw BridgeError(description: "Couldn't open audio input") }
        self.unit = unit

        var on: UInt32 = 1
        var off: UInt32 = 0
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, 4), "turn on input")
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, 4), "turn off output")
        var deviceID = device.id
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                       &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)), "use \(device.name)")

        var hardware = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardware, &size), "read the input format")
        sampleRate = hardware.mSampleRate

        // Only the two solo channels, as 32-bit float, one buffer each.
        var map: [Int32] = [Int32(left - 1), Int32(right - 1)]
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Output, 1,
                                       &map, UInt32(map.count * MemoryLayout<Int32>.size)), "pick channels \(left) and \(right)")
        var client = AudioStreamBasicDescription(
            mSampleRate: hardware.mSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                       &client, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "set the capture format")
        var maxSlice = UInt32(maxFrames)
        _ = AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxSlice, 4)

        var callback = AURenderCallbackStruct(inputProc: captureCallback, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                                       &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "set up the capture callback")
        try check(AudioUnitInitialize(unit), "start the audio input")
        try check(AudioOutputUnitStart(unit), "start capturing")
    }

    fileprivate func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ time: UnsafePointer<AudioTimeStamp>, _ frames: UInt32) -> OSStatus {
        guard let unit, Int(frames) <= maxFrames else { return noErr }
        buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: UnsafeMutableRawPointer(leftData))
        buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: UnsafeMutableRawPointer(rightData))
        let status = AudioUnitRender(unit, flags, time, 1, frames, buffers.unsafeMutablePointer)
        if status == noErr {
            onAudio?(leftData, rightData, Int(frames))
        }
        return status
    }
}

private let captureCallback: AURenderCallback = { refCon, flags, time, _, frames, _ in
    Unmanaged<Capture>.fromOpaque(refCon).takeUnretainedValue().render(flags, time, frames)
}

// MARK: - Network

/// Answers iPads looking for a bridge, and streams to every iPad that has said hello recently.
final class Server {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "x32listen.net")
    private var clients: [String: (connection: NWConnection, lastHello: Date)] = [:]
    let name: String

    init(name: String) throws {
        self.name = name
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: ListenProtocol.port) else { throw BridgeError(description: "Bad port") }
        listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receive(on: connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("\nThe network listener stopped: \(error). Is another copy of the bridge already running?")
                exit(1)
            }
        }
        listener.start(queue: queue)
    }

    var listenerCount: Int {
        queue.sync { clients.count }
    }

    private func key(_ c: NWConnection) -> String { "\(c.endpoint)" }

    private func host(_ c: NWConnection) -> String {
        if case .hostPort(let host, _) = c.endpoint { return "\(host)" }
        return "\(c.endpoint)"
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let message = ListenProtocol.decode(data) {
                self.handle(message, from: connection)
            }
            if error == nil {
                self.receive(on: connection)
            }
        }
    }

    private func handle(_ message: ListenProtocol.Message, from connection: NWConnection) {
        switch message {
        case .probe:
            connection.send(content: ListenProtocol.encode(.info(name: name)), completion: .idempotent)
        case .hello:
            let k = key(connection)
            if clients[k] == nil { print("\n▶ Streaming to \(host(connection))") }
            clients[k] = (connection, Date())
        case .bye:
            if clients.removeValue(forKey: key(connection)) != nil { print("\n■ \(host(connection)) stopped listening") }
        default:
            break
        }
    }

    /// Sends one packet to everyone listening (from any thread).
    func broadcast(_ data: Data) {
        queue.async {
            let now = Date()
            for (k, c) in self.clients {
                if now.timeIntervalSince(c.lastHello) > ListenProtocol.helloTimeout {
                    self.clients.removeValue(forKey: k)
                    print("\n■ \(self.host(c.connection)) went quiet")
                    continue
                }
                c.connection.send(content: data, completion: .idempotent)
            }
        }
    }
}

// MARK: - Test tone

/// Streams a quiet 440 Hz tone (beeping once a second) to any iPad that listens. Never returns.
func runTestTone() -> Never {
    let server: Server
    do {
        server = try Server(name: (Host.current().localizedName ?? "Mac") + " (test tone)")
    } catch {
        print("Couldn't listen on the network: \(error)")
        exit(1)
    }
    print("""
    X32 Listen Bridge: test tone
      Network:  “\(server.name)” on port \(ListenProtocol.port)
    In X32 Remote: Listen on this iPad › Audio from › Mac on Wi-Fi. You should hear a beep every second.
    Press Ctrl-C to stop.
    """)
    let rate = 48000.0
    var phase = 0.0
    var sample = 0
    var sequence: UInt32 = 0
    let frames = ListenProtocol.framesPerPacket
    let timer = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue(label: "x32listen.tone"))
    timer.schedule(deadline: .now(), repeating: .microseconds(Int(Double(frames) / rate * 1_000_000)), leeway: .microseconds(200))
    timer.setEventHandler {
        var samples = [Int16](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            // On for 0.2 s of every second, about -26 dB.
            let on = (sample % 48000) < 9600
            let v = on ? Float(sin(phase)) * 0.05 : 0
            phase += 2 * Double.pi * 440 / rate
            if phase > 2 * Double.pi { phase -= 2 * Double.pi }
            sample += 1
            samples[i * 2] = ListenProtocol.int16(v)
            samples[i * 2 + 1] = ListenProtocol.int16(v)
        }
        server.broadcast(ListenProtocol.encode(.audio(.init(channels: 2, sequence: sequence, sampleRate: Int(rate), samples: samples))))
        sequence &+= 1
    }
    timer.resume()
    let status = DispatchSource.makeTimerSource(queue: .main)
    status.schedule(deadline: .now() + 1, repeating: 1)
    status.setEventHandler {
        let n = server.listenerCount
        print("\r  " + (n == 0 ? "no iPads listening" : (n == 1 ? "1 iPad listening" : "\(n) iPads listening")) + "      ", terminator: "")
        fflush(stdout)
    }
    status.resume()
    dispatchMain()
}

// MARK: - Main

let options = parseOptions()

if options.tone {
    runTestTone()
}

let devices = inputDevices()

if options.listOnly || devices.isEmpty {
    print(devices.isEmpty ? "No audio inputs found." : "Audio inputs on this Mac:")
    for d in devices { print("  \(d.name)  (\(d.channels) channels)") }
    exit(devices.isEmpty ? 1 : 0)
}

let match = options.deviceMatch?.lowercased()
let chosen: InputDevice? = match.map { m in devices.first { $0.name.lowercased().contains(m) } }
    ?? devices.first { d in ["x-usb", "x32", "m32", "x-live"].contains { d.name.lowercased().contains($0) } }

guard let device = chosen else {
    print(options.deviceMatch == nil
          ? "Couldn't find the X32's USB audio. Is the Mac plugged into the USB port on the back of the desk?"
          : "No audio input called “\(options.deviceMatch!)”.")
    print("Audio inputs on this Mac:")
    for d in devices { print("  \(d.name)  (\(d.channels) channels)") }
    print("Use --device NAME to pick one.")
    exit(1)
}

guard max(options.left, options.right) <= device.channels else {
    print("\(device.name) has \(device.channels) channels, so it can't send channel \(max(options.left, options.right)).")
    exit(1)
}

// Reading an audio input needs permission (the first run asks; it's listed under Terminal).
let permission = DispatchSemaphore(value: 0)
var granted = false
AVCaptureDevice.requestAccess(for: .audio) { ok in
    granted = ok
    permission.signal()
}
permission.wait()
guard granted else {
    print("This Mac didn't allow reading audio inputs. Turn on Terminal (or the app you ran this from) in System Settings › Privacy & Security › Microphone, then run it again.")
    exit(1)
}

requestBufferFrames(device.id, 256)

let server: Server
do {
    server = try Server(name: Host.current().localizedName ?? "Mac")
} catch {
    print("Couldn't listen on the network: \(error)")
    exit(1)
}

let capture = Capture(device: device, left: options.left, right: options.right)
let stateLock = NSLock()
var pending: [Int16] = []
pending.reserveCapacity(16384)
var sequence: UInt32 = 0
var peak: Float = 0
let samplesPerPacket = ListenProtocol.framesPerPacket * 2

capture.onAudio = { left, right, frames in
    stateLock.lock()
    for i in 0..<frames {
        pending.append(ListenProtocol.int16(left[i]))
        pending.append(ListenProtocol.int16(right[i]))
        peak = max(peak, abs(left[i]), abs(right[i]))
    }
    var packets: [Data] = []
    while pending.count >= samplesPerPacket {
        let audio = ListenProtocol.Audio(channels: 2, sequence: sequence, sampleRate: Int(capture.sampleRate),
                                         samples: Array(pending[0..<samplesPerPacket]))
        pending.removeFirst(samplesPerPacket)
        sequence &+= 1
        packets.append(ListenProtocol.encode(.audio(audio)))
    }
    stateLock.unlock()
    for p in packets { server.broadcast(p) }
}

do {
    try capture.start()
} catch {
    print("\(error)")
    exit(1)
}

print("""
X32 Listen Bridge
  Input:    \(device.name), channels \(options.left)/\(options.right) at \(Int(capture.sampleRate)) Hz
  Network:  “\(server.name)” on port \(ListenProtocol.port)

In X32 Remote: Listen on this iPad › Audio from › Mac on Wi-Fi. This Mac shows up there.
Press Ctrl-C to stop.
""")

// A level meter on one line, so it's obvious the solo bus is arriving.
let meterTimer = DispatchSource.makeTimerSource(queue: .main)
meterTimer.schedule(deadline: .now() + 1, repeating: 0.5)
meterTimer.setEventHandler {
    stateLock.lock()
    let p = peak
    peak = 0
    stateLock.unlock()
    let db: Double = p > 0 ? 20 * log10(Double(p)) : -90
    let width = 30
    let lit = max(0, min(width, Int((db + 60) / 60 * Double(width))))
    let bar = String(repeating: "█", count: lit) + String(repeating: "·", count: width - lit)
    let listeners = server.listenerCount
    let who = listeners == 0 ? "no iPads listening" : (listeners == 1 ? "1 iPad listening" : "\(listeners) iPads listening")
    print(String(format: "\r  Solo %@ %4.0f dB   %@      ", bar, max(db, -90), who), terminator: "")
    fflush(stdout)
}
meterTimer.resume()

dispatchMain()
