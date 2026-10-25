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
let addresses = Requests.sync() + Requests.stripOverview() + Requests.sends(bus: 1)
let syncStart = Date()
client.get(addresses)
while client.pendingRequests > 0 && Date().timeIntervalSince(syncStart) < 20 { spin(0.02) }
let answered = addresses.filter { values[$0] != nil }
check(answered.count == addresses.count, "initial sync answered \(answered.count)/\(addresses.count) in \(String(format: "%.2f", Date().timeIntervalSince(syncStart)))s")
let missing = addresses.filter { values[$0] == nil }
if !missing.isEmpty { print("  unanswered: \(missing.prefix(20))") }
check(values["/ch/13/config/name"] == .string("Lead Vox"), "reads seeded name ch13 = \(String(describing: values["/ch/13/config/name"]))")

// Every strip's channel page, plus every sheet and tool. A desk answers all of these; an address
// it doesn't know would leave a control showing "—" forever.
let detail: [String] = {
    var a: [String] = []
    for s in StripID.everything { a += Requests.detail(s) }
    a += Requests.everythingElse()
    var seen = Set<String>()
    return a.filter { seen.insert($0).inserted }
}()
let detailStart = Date()
client.get(detail)
while client.pendingRequests > 0 && Date().timeIntervalSince(detailStart) < 20 { spin(0.02) }
let detailMissing = detail.filter { values[$0] == nil }
check(detailMissing.isEmpty, "every address the app can ask for is answered: \(detail.count - detailMissing.count)/\(detail.count)")
if !detailMissing.isEmpty { print("  unanswered: \(detailMissing.prefix(30))") }
if case .int(let ha)? = values["/-ha/00/index"] {
    client.get([StripID.headampGainPath(Int(ha)), StripID.headampPhantomPath(Int(ha))])
    spin(0.3)
    check(values[StripID.headampGainPath(Int(ha))] != nil, "headamp gain for ch1 (headamp \(ha))")
}

// Load effect types and check every parameter comes back as the type the app sends (int or float).
// (Slots 5-8 stop at type 11: the emulator's own table for later 5-8 types is out of step with its type list.)
for (slot, type) in [(1, 15), (2, 21), (3, 55), (4, 47), (5, 11), (6, 6)] {
    client.set(Effects.typePath(slot), .int(Int32(type)))
    spin(0.2)
    guard let params = Effects.parameters(slot: slot, type: type) else {
        check(false, "FX \(slot) type \(type) has parameters")
        continue
    }
    let paths = params.map { Effects.parPath(slot, $0.number) }
    paths.forEach { values[$0] = nil }
    client.get(paths)
    let t0 = Date()
    while client.pendingRequests > 0 && Date().timeIntervalSince(t0) < 5 { spin(0.02) }
    var wrong: [String] = []
    for p in params {
        let v = values[Effects.parPath(slot, p.number)]
        let isInt: Bool
        if case .choice = p.kind { isInt = true } else { isInt = false }
        switch v {
        case .int?: if !isInt { wrong.append(p.name) }
        case .float?: if isInt { wrong.append(p.name) }
        default: wrong.append(p.name + " (no answer)")
        }
    }
    check(wrong.isEmpty, "FX \(slot) \(Effects.typeName(slot: slot, type: type)): \(params.count) parameters match the desk \(wrong)")
}

// Changes from the app reach the desk (checked from a second, independent client).
client.set("/ch/01/mix/fader", .float(X32Math.quantize(0.75, steps: 1023)))
client.set("/ch/02/mix/on", .int(0))
client.set("/ch/03/config/name", .string("SelfTest"))
client.set("/ch/04/mix/05/level", .float(X32Math.quantize(X32Math.dbToFader(-6), steps: 160)))
client.set("/ch/05/config/color", .int(4))
client.set("/ch/06/eq/2/g", .float(X32Math.quantize(X32Math.linInverse(6, -15, 15), steps: 120)))
client.set("/config/mute/3", .int(1))
client.set(Outputs.path(.main, 5, "src"), .int(30))
client.set(Monitoring.talkDestinationPath("A"), .int(0b11))
for i in 0..<40 { client.set("/ch/07/mix/fader", .float(Float(i) / 40)) }
spin(0.3)

let other = X32Client(transport: try UDPTransport(host: host))
var otherValues: [String: OSCArg] = [:]
other.onMessage = { m in if let v = m.args.first { otherValues[m.address] = v } }
let checks = ["/ch/01/mix/fader", "/ch/02/mix/on", "/ch/03/config/name", "/ch/04/mix/05/level", "/ch/05/config/color", "/ch/06/eq/2/g", "/config/mute/3", "/ch/07/mix/fader",
              Outputs.path(.main, 5, "src"), Monitoring.talkDestinationPath("A")]
spin(0.3)
other.get(checks)
spin(0.6)
check(otherValues["/ch/01/mix/fader"] == .float(X32Math.quantize(0.75, steps: 1023)), "fader set reached desk")
check(otherValues["/ch/02/mix/on"] == .int(0), "mute reached desk")
check(otherValues["/ch/03/config/name"] == .string("SelfTest"), "name reached desk")
check(otherValues["/ch/05/config/color"] == .int(4), "colour reached desk")
check(otherValues["/config/mute/3"] == .int(1), "mute group reached desk")
check(otherValues["/ch/07/mix/fader"] == .float(39.0 / 40.0), "rapid fader moves end on the last value")
check(otherValues[Outputs.path(.main, 5, "src")] == .int(30), "output patch reached desk")
check(otherValues[Monitoring.talkDestinationPath("A")] == .int(0b11), "talkback destinations reached desk")

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
