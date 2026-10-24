// Integration test: drives the app's real networking stack (UDPTransport + X32Client)
// against an X32 emulator listening on 127.0.0.1:10023.
import Foundation

func spin(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

var failures = 0
func check(_ condition: Bool, _ message: String) {
    print((condition ? "PASS " : "FAIL ") + message)
    if !condition { failures += 1 }
}

let host = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "127.0.0.1"
let transport = try UDPTransport(host: host)
let client = X32Client(transport: transport)
var values: [String: OSCArg] = [:]
var meterCounts: [Int: Int] = [:]
var info: ConsoleInfo?
client.onInfo = { info = $0 }
client.onMessage = { m in if let v = m.args.first { values[m.address] = v } }
client.onMeters = { block, floats in meterCounts[block] = floats.count }
client.setMeterSubscriptions([0, 1, 2])

let start = Date()
while client.status != .connected && Date().timeIntervalSince(start) < 5 { spin(0.05) }
check(client.status == .connected, "connected to \(host) in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
check(info != nil, "console info: \(info.map { "\($0.name) \($0.model) \($0.firmware)" } ?? "none")")

// The same requests the app makes when it connects.
var addresses: [String] = []
for s in StripID.everything {
    addresses += [s.namePath, s.colorPath, s.faderPath, s.onPath, s.soloPath]
    if let p = s.panPath { addresses.append(p) }
    if let p = s.lrAssignPath { addresses.append(p) }
    if let p = s.dcaGroupsPath { addresses.append(p) }
    if let p = s.muteGroupsPath { addresses.append(p) }
}
for n in 1...6 { addresses.append("/config/mute/\(n)") }
let syncStart = Date()
client.get(addresses)
while client.pendingRequests > 0 && Date().timeIntervalSince(syncStart) < 20 { spin(0.02) }
let answered = addresses.filter { values[$0] != nil }
check(answered.count == addresses.count, "initial sync answered \(answered.count)/\(addresses.count) in \(String(format: "%.2f", Date().timeIntervalSince(syncStart)))s")
let missing = addresses.filter { values[$0] == nil }
if !missing.isEmpty { print("  unanswered: \(missing.prefix(20))") }
check(values["/ch/13/config/name"] == .string("Lead Vox"), "reads seeded name ch13 = \(String(describing: values["/ch/13/config/name"]))")

// Detail page requests for a channel and a bus.
let detail: [String] = {
    var a: [String] = []
    for s in [StripID(.channel, 1), StripID(.bus, 1), StripID.mainLR] {
        if s.hasEQ { a.append(s.eqOnPath); for b in 1...s.eqBandCount { for f in ["type", "f", "g", "q"] { a.append(s.eqPath(b, f)) } } }
        if s.hasGate { for f in ["on", "mode", "thr", "range", "attack", "hold", "release", "keysrc", "filter/on", "filter/type", "filter/f"] { a.append(s.gatePath(f)) } }
        if s.hasDynamics { for f in ["on", "mode", "det", "env", "thr", "ratio", "knee", "mgain", "attack", "hold", "release", "mix", "auto", "pos", "filter/on", "filter/type", "filter/f"] { a.append(s.dynPath(f)) } }
        if s.hasDynKeySource { a.append(s.dynPath("keysrc")) }
        if s.hasInsert { a += ["on", "pos", "sel"].map { s.insertPath($0) } }
        for n in 1...s.sendCount { a.append(s.sendLevelPath(n)); a.append(s.sendOnPath(n)); if n % 2 == 1 { a.append(s.sendTypePath(n)) } }
        if s.hasTrim { a.append(s.preampPath("trim")) }
        if s.hasHighPass { a += [s.preampPath("hpon"), s.preampPath("hpf"), s.preampPath("hpslope")] }
        if let ha = s.headampIndexPath { a.append(ha) }
        if let p = s.monoLevelPath { a.append(p) }
    }
    for n in 0..<100 {
        a.append(String(format: "/-show/showfile/scene/%03d/hasdata", n))
        a.append(String(format: "/-show/showfile/scene/%03d/name", n))
    }
    a.append("/-show/prepos/current")
    return a
}()
let detailStart = Date()
client.get(detail)
while client.pendingRequests > 0 && Date().timeIntervalSince(detailStart) < 20 { spin(0.02) }
let detailMissing = detail.filter { values[$0] == nil }
check(detailMissing.isEmpty, "detail params answered \(detail.count - detailMissing.count)/\(detail.count)")
if !detailMissing.isEmpty { print("  unanswered: \(detailMissing.prefix(30))") }
if case .int(let ha)? = values["/-ha/00/index"] {
    client.get([StripID.headampGainPath(Int(ha)), StripID.headampPhantomPath(Int(ha))])
    spin(0.3)
    check(values[StripID.headampGainPath(Int(ha))] != nil, "headamp gain for ch1 (headamp \(ha))")
}

// Changes from the app reach the desk (checked from a second, independent client).
client.set("/ch/01/mix/fader", .float(X32Math.quantize(0.75, steps: 1023)))
client.set("/ch/02/mix/on", .int(0))
client.set("/ch/03/config/name", .string("SelfTest"))
client.set("/ch/04/mix/05/level", .float(X32Math.quantize(X32Math.dbToFader(-6), steps: 160)))
client.set("/ch/05/config/color", .int(4))
client.set("/ch/06/eq/2/g", .float(X32Math.quantize(X32Math.linInverse(6, -15, 15), steps: 120)))
client.set("/config/mute/3", .int(1))
for i in 0..<40 { client.set("/ch/07/mix/fader", .float(Float(i) / 40)) }
spin(0.3)

let other = X32Client(transport: try UDPTransport(host: host))
var otherValues: [String: OSCArg] = [:]
other.onMessage = { m in if let v = m.args.first { otherValues[m.address] = v } }
let checks = ["/ch/01/mix/fader", "/ch/02/mix/on", "/ch/03/config/name", "/ch/04/mix/05/level", "/ch/05/config/color", "/ch/06/eq/2/g", "/config/mute/3", "/ch/07/mix/fader"]
spin(0.3)
other.get(checks)
spin(0.6)
check(otherValues["/ch/01/mix/fader"] == .float(X32Math.quantize(0.75, steps: 1023)), "fader set reached desk")
check(otherValues["/ch/02/mix/on"] == .int(0), "mute reached desk")
check(otherValues["/ch/03/config/name"] == .string("SelfTest"), "name reached desk")
check(otherValues["/ch/05/config/color"] == .int(4), "colour reached desk")
check(otherValues["/config/mute/3"] == .int(1), "mute group reached desk")
check(otherValues["/ch/07/mix/fader"] == .float(39.0 / 40.0), "rapid fader moves end on the last value")

// A change made elsewhere (the "desk") arrives through /xremote.
values["/ch/08/mix/fader"] = nil
other.set("/ch/08/mix/fader", .float(0.5))
spin(0.5)
check(values["/ch/08/mix/fader"] == .float(0.5), "change from another client arrives via /xremote")

spin(0.5)
check(meterCounts[0] == 70 && meterCounts[1] == 96 && meterCounts[2] == 49, "meters received: \(meterCounts.sorted { $0.key < $1.key })")

other.close()
client.close()
print(failures == 0 ? "ALL INTEGRATION CHECKS PASSED" : "\(failures) INTEGRATION CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
