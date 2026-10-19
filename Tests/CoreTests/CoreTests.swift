import XCTest
@testable import X32Core

final class OSCTests: XCTestCase {
    func testEncodeFaderMatchesWireFormat() {
        let data = OSCCodec.encode(OSCMessage("/ch/01/mix/fader", [.float(0.75)]))
        // "/ch/01/mix/fader" is 16 chars -> 20 bytes padded; ",f" -> 4 bytes; float -> 4 bytes
        XCTAssertEqual(data.count, 28)
        let bytes = [UInt8](data)
        XCTAssertEqual(Array(bytes[0..<16]), Array("/ch/01/mix/fader".utf8))
        XCTAssertEqual(Array(bytes[16..<20]), [0, 0, 0, 0])
        XCTAssertEqual(Array(bytes[20..<24]), [0x2C, 0x66, 0, 0])
        XCTAssertEqual(Array(bytes[24..<28]), [0x3F, 0x40, 0x00, 0x00])
    }

    func testGetRequestHasEmptyTypeTag() {
        let data = OSCCodec.encode(OSCMessage("/xinfo"))
        XCTAssertEqual([UInt8](data), Array("/xinfo".utf8) + [0, 0] + [0x2C, 0, 0, 0])
    }

    func testRoundTripAllTypes() {
        let blob = Data([1, 2, 3, 4, 5])
        let message = OSCMessage("/test/path", [.int(-42), .float(0.125), .string("Lead Vox"), .blob(blob), .string("")])
        let decoded = OSCCodec.decode(OSCCodec.encode(message))
        XCTAssertEqual(decoded, message)
    }

    func testDecodeAddressOnly() {
        var bytes = Array("/xremote".utf8)
        bytes += [0, 0, 0, 0]
        let decoded = OSCCodec.decode(Data(bytes))
        XCTAssertEqual(decoded?.address, "/xremote")
        XCTAssertEqual(decoded?.args.count, 0)
    }

    func testDecodeRejectsGarbage() {
        XCTAssertNil(OSCCodec.decode(Data([0x41, 0x42, 0x43])))
        XCTAssertNil(OSCCodec.decode(Data()))
    }

    func testDecodeTruncatedArgumentFails() {
        var data = OSCCodec.encode(OSCMessage("/ch/01/mix/fader", [.float(0.5)]))
        data.removeLast(2)
        XCTAssertNil(OSCCodec.decode(data))
    }

    func testMeterBlobIsLittleEndianWithCount() {
        let blob = MeterBlob.encode([1.0, 0.5])
        let bytes = [UInt8](blob)
        XCTAssertEqual(Array(bytes[0..<4]), [2, 0, 0, 0])
        XCTAssertEqual(Array(bytes[4..<8]), [0x00, 0x00, 0x80, 0x3F])
        XCTAssertEqual(MeterBlob.floats(from: blob), [1.0, 0.5])
    }

    func testMeterBlobToleratesShortData() {
        XCTAssertEqual(MeterBlob.floats(from: Data([5, 0, 0, 0, 0, 0, 0x80, 0x3F])), [1.0])
        XCTAssertEqual(MeterBlob.floats(from: Data([1, 2])), [])
    }
}

final class ValueTests: XCTestCase {
    func testFaderLawKeyPoints() {
        XCTAssertEqual(X32Math.dbToFader(0), 0.75, accuracy: 1e-6)
        XCTAssertEqual(X32Math.dbToFader(10), 1.0, accuracy: 1e-6)
        XCTAssertEqual(X32Math.dbToFader(-10), 0.5, accuracy: 1e-6)
        XCTAssertEqual(X32Math.dbToFader(-30), 0.25, accuracy: 1e-6)
        XCTAssertEqual(X32Math.dbToFader(-60), 0.0625, accuracy: 1e-6)
        XCTAssertEqual(X32Math.dbToFader(-90), 0, accuracy: 1e-6)
        XCTAssertEqual(X32Math.dbToFader(-.infinity), 0)
        XCTAssertEqual(X32Math.faderToDB(0.75), 0, accuracy: 1e-4)
        XCTAssertEqual(X32Math.faderToDB(0.5), -10, accuracy: 1e-4)
        XCTAssertEqual(X32Math.faderToDB(0.25), -30, accuracy: 1e-4)
        XCTAssertEqual(X32Math.faderToDB(0.0625), -60, accuracy: 1e-4)
        XCTAssertTrue(X32Math.faderToDB(0).isInfinite)
    }

    func testFaderLawRoundTrips() {
        var db: Float = -85
        while db <= 10 {
            XCTAssertEqual(X32Math.faderToDB(X32Math.dbToFader(db)), db, accuracy: 0.01, "at \(db)")
            db += 0.5
        }
    }

    func testFormatting() {
        XCTAssertEqual(X32Math.formatFader(0.75), "0.0")
        XCTAssertEqual(X32Math.formatFader(X32Math.quantize(0.75, steps: 1023)), "0.0")
        XCTAssertEqual(X32Math.formatFader(1.0), "+10.0")
        XCTAssertEqual(X32Math.formatFader(0.5), "-10.0")
        XCTAssertEqual(X32Math.formatFader(0), "-∞")
        XCTAssertEqual(ParamSpec.formatHz(1000), "1.00k")
        XCTAssertEqual(ParamSpec.formatHz(12500), "12.5k")
        XCTAssertEqual(ParamSpec.formatHz(80), "80.0")
    }

    func testQuantize() {
        XCTAssertEqual(X32Math.quantize(0.75, steps: 1023), Float(767) / 1023, accuracy: 1e-7)
        XCTAssertEqual(X32Math.quantize(1.2, steps: 100), 1)
        XCTAssertEqual(X32Math.quantize(-0.1, steps: 100), 0)
    }

    func testFrequencyScale() {
        XCTAssertEqual(Specs.eqFreq.value(0), 20, accuracy: 0.01)
        XCTAssertEqual(Specs.eqFreq.value(1), 20000, accuracy: 0.5)
        XCTAssertEqual(Specs.eqFreq.value(0.5), 632.46, accuracy: 0.1)
        XCTAssertEqual(Specs.eqFreq.norm(1000), 0.56634, accuracy: 1e-4)
        XCTAssertEqual(Specs.hpf.value(0), 20, accuracy: 0.01)
        XCTAssertEqual(Specs.hpf.value(1), 400, accuracy: 0.05)
    }

    func testQScaleRunsFromTenDownToPointThree() {
        XCTAssertEqual(Specs.eqQ.value(0), 10, accuracy: 0.001)
        XCTAssertEqual(Specs.eqQ.value(1), 0.3, accuracy: 0.001)
        XCTAssertEqual(Specs.eqQ.value(Specs.eqQ.norm(2)), 2, accuracy: 0.001)
    }

    func testLinearScales() {
        XCTAssertEqual(Specs.eqGain.value(0.5), 0, accuracy: 1e-6)
        XCTAssertEqual(Specs.eqGain.value(1), 15, accuracy: 1e-6)
        XCTAssertEqual(Specs.trim.value(0), -18, accuracy: 1e-6)
        XCTAssertEqual(Specs.headampGain.value(1), 60, accuracy: 1e-6)
        XCTAssertEqual(Specs.headampGain.value(Specs.headampGain.defaultNorm), 0, accuracy: 1e-4)
        XCTAssertEqual(Specs.gateThreshold.value(0), -80, accuracy: 1e-6)
        XCTAssertEqual(Specs.dynThreshold.value(0), -60, accuracy: 1e-6)
        XCTAssertEqual(Specs.pan.value(0.5), 0, accuracy: 1e-6)
    }

    func testDisplayStrings() {
        XCTAssertEqual(Specs.eqGain.display(0.5), "0.0 dB")
        XCTAssertEqual(Specs.attack.display(1), "120 ms")
        XCTAssertEqual(Specs.release.display(1), "4.00 s")
        XCTAssertEqual(Specs.fader.display(0.75), "0.0 dB")
    }

    func testSourceNames() {
        XCTAssertEqual(X32Enums.sourceName(0), "Off")
        XCTAssertEqual(X32Enums.sourceName(5), "In 5")
        XCTAssertEqual(X32Enums.sourceName(33), "Aux 1")
        XCTAssertEqual(X32Enums.sourceName(39), "USB L")
        XCTAssertEqual(X32Enums.sourceName(41), "FX 1L")
        XCTAssertEqual(X32Enums.sourceName(48), "FX 4R")
        XCTAssertEqual(X32Enums.sourceName(49), "Bus 1")
    }
}

final class StripTests: XCTestCase {
    func testChannelPaths() {
        let ch = StripID(.channel, 5)
        XCTAssertEqual(ch.faderPath, "/ch/05/mix/fader")
        XCTAssertEqual(ch.onPath, "/ch/05/mix/on")
        XCTAssertEqual(ch.namePath, "/ch/05/config/name")
        XCTAssertEqual(ch.colorPath, "/ch/05/config/color")
        XCTAssertEqual(ch.panPath, "/ch/05/mix/pan")
        XCTAssertEqual(ch.lrAssignPath, "/ch/05/mix/st")
        XCTAssertEqual(ch.sendLevelPath(3), "/ch/05/mix/03/level")
        XCTAssertEqual(ch.sendOnPath(12), "/ch/05/mix/12/on")
        XCTAssertEqual(ch.sendTypePath(4), "/ch/05/mix/03/type")
        XCTAssertEqual(ch.sendPanPath(3), "/ch/05/mix/03/pan")
        XCTAssertEqual(ch.eqPath(2, "g"), "/ch/05/eq/2/g")
        XCTAssertEqual(ch.gatePath("thr"), "/ch/05/gate/thr")
        XCTAssertEqual(ch.dynPath("ratio"), "/ch/05/dyn/ratio")
        XCTAssertEqual(ch.preampPath("hpf"), "/ch/05/preamp/hpf")
        XCTAssertEqual(ch.headampIndexPath, "/-ha/04/index")
        XCTAssertEqual(ch.soloPath, "/-stat/solosw/05")
        XCTAssertEqual(ch.meters0Index, 4)
        XCTAssertEqual(ch.eqBandCount, 4)
    }

    func testOtherStripPaths() {
        XCTAssertEqual(StripID(.auxIn, 2).faderPath, "/auxin/02/mix/fader")
        XCTAssertEqual(StripID(.auxIn, 2).headampIndexPath, "/-ha/33/index")
        XCTAssertEqual(StripID(.fxReturn, 8).namePath, "/fxrtn/08/config/name")
        XCTAssertEqual(StripID(.bus, 16).faderPath, "/bus/16/mix/fader")
        XCTAssertEqual(StripID(.bus, 1).sendLevelPath(6), "/bus/01/mix/06/level")
        XCTAssertEqual(StripID(.matrix, 6).onPath, "/mtx/06/mix/on")
        XCTAssertNil(StripID(.matrix, 1).panPath)
        XCTAssertEqual(StripID.mainLR.faderPath, "/main/st/mix/fader")
        XCTAssertEqual(StripID.monoC.onPath, "/main/m/mix/on")
        XCTAssertEqual(StripID(.dca, 3).faderPath, "/dca/3/fader")
        XCTAssertEqual(StripID(.dca, 3).onPath, "/dca/3/on")
        XCTAssertEqual(StripID(.dca, 3).namePath, "/dca/3/config/name")
        XCTAssertNil(StripID(.dca, 3).dcaGroupsPath)
        XCTAssertEqual(StripID(.bus, 1).eqBandCount, 6)
    }

    func testSoloIndices() {
        XCTAssertEqual(StripID(.channel, 32).soloIndex, 32)
        XCTAssertEqual(StripID(.auxIn, 1).soloIndex, 33)
        XCTAssertEqual(StripID(.fxReturn, 1).soloIndex, 41)
        XCTAssertEqual(StripID(.bus, 16).soloIndex, 64)
        XCTAssertEqual(StripID(.matrix, 6).soloIndex, 70)
        XCTAssertEqual(StripID.mainLR.soloIndex, 71)
        XCTAssertEqual(StripID.monoC.soloIndex, 72)
        XCTAssertEqual(StripID(.dca, 8).soloIndex, 80)
    }

    func testMeterIndices() {
        XCTAssertEqual(StripID(.auxIn, 1).meters0Index, 32)
        XCTAssertEqual(StripID(.fxReturn, 8).meters0Index, 47)
        XCTAssertEqual(StripID(.bus, 1).meters0Index, 48)
        XCTAssertEqual(StripID(.matrix, 6).meters0Index, 69)
        XCTAssertNil(StripID.mainLR.meters0Index)
    }

    func testEveryStripHasUniqueAddresses() {
        let all = StripID.everything
        XCTAssertEqual(all.count, 32 + 8 + 8 + 16 + 6 + 1 + 1 + 8)
        XCTAssertEqual(Set(all.map { $0.faderPath }).count, all.count)
        XCTAssertEqual(Set(all.map { $0.soloIndex }).count, all.count)
    }

    func testLabels() {
        XCTAssertEqual(StripID(.fxReturn, 1).shortLabel, "FX 1L")
        XCTAssertEqual(StripID(.fxReturn, 4).shortLabel, "FX 2R")
        XCTAssertEqual(StripID(.auxIn, 7).shortLabel, "USB L")
        XCTAssertEqual(StripID(.channel, 7).shortLabel, "Ch 07")
    }

    func testCodable() throws {
        let id = StripID(.bus, 4)
        let data = try JSONEncoder().encode(id)
        XCTAssertEqual(try JSONDecoder().decode(StripID.self, from: data), id)
    }
}

final class NetworkMathTests: XCTestCase {
    func testScanTargetsForSlash24() {
        let iface = LocalIPv4Interface(name: "en0", address: 0xC0A8_0132, netmask: 0xFFFF_FF00) // 192.168.1.50/24
        let targets = iface.scanTargets
        XCTAssertEqual(targets.count, 253)
        XCTAssertEqual(targets.first, "192.168.1.1")
        XCTAssertEqual(targets.last, "192.168.1.254")
        XCTAssertFalse(targets.contains("192.168.1.50"))
    }

    func testScanTargetsLargeSubnetIsCapped() {
        let iface = LocalIPv4Interface(name: "en0", address: 0x0A00_0505, netmask: 0xFF00_0000) // 10.0.5.5/8
        let targets = iface.scanTargets
        XCTAssertEqual(targets.count, 253)
        XCTAssertEqual(targets.first, "10.0.5.1")
    }

    func testScanTargetsSlash22() {
        let iface = LocalIPv4Interface(name: "en0", address: 0xAC10_0101, netmask: 0xFFFF_FC00) // 172.16.1.1/22
        XCTAssertEqual(iface.scanTargets.count, 1021)
    }
}

final class StoreTests: XCTestCase {
    func testRemoteValuesIgnoredWhileTouched() {
        let store = ParamStore()
        store.applyRemote("/ch/01/mix/fader", .float(0.5))
        XCTAssertEqual(store.param("/ch/01/mix/fader").float, 0.5)
        store.param("/ch/01/mix/fader").touchCount = 1
        store.applyRemote("/ch/01/mix/fader", .float(0.1))
        XCTAssertEqual(store.param("/ch/01/mix/fader").float, 0.5)
        store.param("/ch/01/mix/fader").touchCount = 0
        store.applyRemote("/ch/01/mix/fader", .float(0.1))
        XCTAssertEqual(store.param("/ch/01/mix/fader").float, 0.1)
    }

    func testDefaultsWhenUnknown() {
        let store = ParamStore()
        let p = store.param("/ch/01/mix/on")
        XCTAssertFalse(p.isKnown)
        XCTAssertEqual(p.int(or: 1), 1)
        store.clear()
        XCTAssertNil(store.value("/ch/01/mix/on"))
    }

    func testMeterIngest() {
        let meters = MeterStore()
        var block0 = [Float](repeating: 0, count: 70)
        block0[0] = 1.0          // ch 1 at 0 dBFS
        block0[48] = 0.1         // bus 1 at -20 dBFS
        meters.ingest(block: 0, values: block0)
        XCTAssertEqual(meters.meter(.channel(1)).level, 0, accuracy: 0.01)
        XCTAssertEqual(meters.meter(.bus(1)).level, -20, accuracy: 0.01)

        var block2 = [Float](repeating: 1, count: 49)
        block2[22] = 0.5
        block2[23] = 0.25
        meters.ingest(block: 2, values: block2)
        XCTAssertEqual(meters.meter(.mainLR).level, -6.02, accuracy: 0.05)
        XCTAssertEqual(meters.meter(.mainLR).level2, -12.04, accuracy: 0.05)

        var block1 = [Float](repeating: 1, count: 96)
        block1[64] = 0.5        // ch 1 dynamics gain 0.5 = 6 dB reduction
        meters.ingest(block: 1, values: block1)
        XCTAssertEqual(meters.meter(.channel(1)).dynReduction, 6.02, accuracy: 0.05)
        XCTAssertEqual(meters.meter(.channel(1)).gateReduction, 0, accuracy: 0.01)
    }

    func testMeterReleaseIsSmoothed() {
        let meters = MeterStore()
        var block = [Float](repeating: 0, count: 70)
        block[0] = 1.0
        meters.ingest(block: 0, values: block)
        block[0] = 0
        meters.ingest(block: 0, values: block)
        XCTAssertEqual(meters.meter(.channel(1)).level, -1.5, accuracy: 0.01)
    }
}

/// Records what the client sends and lets the test reply as the console.
final class MockTransport: X32Transport {
    var onMessage: ((OSCMessage) -> Void)?
    var displayAddress: String { "mock" }
    var sent: [OSCMessage] = []
    var autoReply = true

    func send(_ message: OSCMessage) {
        sent.append(message)
        guard autoReply else { return }
        if message.address == "/xinfo" {
            reply(OSCMessage("/xinfo", [.string("10.0.0.2"), .string("Test X32"), .string("X32"), .string("4.06")]))
        } else if message.args.isEmpty, message.address.hasPrefix("/ch/") {
            reply(OSCMessage(message.address, [.float(0.5)]))
        }
    }

    func reply(_ message: OSCMessage) {
        DispatchQueue.main.async {
            self.onMessage?(message)
        }
    }

    func close() {}
}

final class ClientTests: XCTestCase {
    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testConnectsAndRegistersForUpdates() {
        let transport = MockTransport()
        let client = X32Client(transport: transport)
        var statuses: [X32Client.Status] = []
        var info: ConsoleInfo?
        client.onStatus = { statuses.append($0) }
        client.onInfo = { info = $0 }
        client.setMeterSubscriptions([0, 2])
        spin(0.3)
        XCTAssertEqual(client.status, .connected)
        XCTAssertEqual(statuses, [.connected])
        XCTAssertEqual(info?.name, "Test X32")
        XCTAssertEqual(info?.ip, "10.0.0.2")
        let addresses = transport.sent.map { $0.address }
        XCTAssertTrue(addresses.contains("/xremote"))
        let meterRequests = transport.sent.filter { $0.address == "/meters" }
        XCTAssertEqual(meterRequests.count, 2)
        XCTAssertEqual(meterRequests.first?.args.first, .string("/meters/0"))
        client.close()
    }

    func testRequestsAreWindowedAndAnswered() {
        let transport = MockTransport()
        let client = X32Client(transport: transport)
        var received: [String] = []
        client.onMessage = { received.append($0.address) }
        spin(0.2)
        let addresses = (1...32).flatMap { n in [StripID(.channel, n).faderPath, StripID(.channel, n).panPath ?? ""] }
        client.get(addresses)
        spin(0.5)
        XCTAssertEqual(Set(received), Set(addresses))
        XCTAssertEqual(client.pendingRequests, 0)
        client.close()
    }

    func testUnansweredRequestsAreRetriedThenDropped() {
        let transport = MockTransport()
        let client = X32Client(transport: transport)
        spin(0.2)
        transport.sent.removeAll()
        client.get("/nonexistent/thing")
        spin(2.2)
        let tries = transport.sent.filter { $0.address == "/nonexistent/thing" }.count
        XCTAssertEqual(tries, 3)
        XCTAssertEqual(client.pendingRequests, 0)
        client.close()
    }

    func testSetsAreCoalesced() {
        let transport = MockTransport()
        let client = X32Client(transport: transport)
        spin(0.2)
        transport.sent.removeAll()
        for i in 0..<50 {
            client.set("/ch/01/mix/fader", .float(Float(i) / 100))
        }
        client.set("/ch/02/mix/on", .int(0))
        spin(0.1)
        let faderSets = transport.sent.filter { $0.address == "/ch/01/mix/fader" }
        XCTAssertEqual(faderSets.count, 1)
        XCTAssertEqual(faderSets.first?.args, [.float(0.49)])
        XCTAssertEqual(transport.sent.filter { $0.address == "/ch/02/mix/on" }.count, 1)
        client.close()
    }

    func testLostAndRecovered() {
        let transport = MockTransport()
        let client = X32Client(transport: transport)
        var statuses: [X32Client.Status] = []
        client.onStatus = { statuses.append($0) }
        spin(0.2)
        transport.autoReply = false
        spin(5.6)
        XCTAssertEqual(client.status, .lost)
        transport.autoReply = true
        spin(1.6)
        XCTAssertEqual(client.status, .connected)
        XCTAssertEqual(statuses, [.connected, .lost, .connected])
        client.close()
    }
}

final class DemoDeskTests: XCTestCase {
    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testDemoDeskBehavesLikeAConsole() {
        let demo = DemoTransport()
        let client = X32Client(transport: demo)
        var values: [String: OSCArg] = [:]
        var meterBlocks: Set<Int> = []
        client.onMessage = { m in
            if let v = m.args.first { values[m.address] = v }
        }
        client.onMeters = { block, floats in
            meterBlocks.insert(block)
            if block == 0 { XCTAssertEqual(floats.count, 70) }
            if block == 1 { XCTAssertEqual(floats.count, 96) }
            if block == 2 { XCTAssertEqual(floats.count, 49) }
        }
        client.setMeterSubscriptions([0, 1, 2])
        spin(0.3)
        XCTAssertEqual(client.status, .connected)
        XCTAssertEqual(client.info?.name, "Demo X32")

        client.get(["/ch/16/config/name", "/bus/01/config/name", "/dca/1/config/name", "/ch/05/eq/2/type", "/-ha/03/index", "/headamp/003/gain"])
        spin(0.3)
        XCTAssertEqual(values["/ch/16/config/name"], .string("Lead Vox"))
        XCTAssertEqual(values["/bus/01/config/name"], .string("Vox Wedge"))
        XCTAssertEqual(values["/dca/1/config/name"], .string("Drums"))
        XCTAssertEqual(values["/ch/05/eq/2/type"], .int(2))
        XCTAssertEqual(values["/-ha/03/index"], .int(3))
        XCTAssertNotNil(values["/headamp/003/gain"])

        client.set("/ch/03/mix/fader", .float(0.6))
        spin(0.1)
        values["/ch/03/mix/fader"] = nil
        client.get("/ch/03/mix/fader")
        spin(0.2)
        XCTAssertEqual(values["/ch/03/mix/fader"], .float(0.6))

        client.send(OSCMessage("/-action/goscene", [.int(3)]))
        spin(0.2)
        XCTAssertEqual(values["/-show/prepos/current"], .int(3))
        XCTAssertEqual(values["/ch/01/mix/on"], .int(0))

        spin(0.3)
        XCTAssertEqual(meterBlocks, [0, 1, 2])
        client.close()
        demo.close()
    }

    func testEveryAddressTheAppLoadsHasADemoValue() {
        var missing: [String] = []
        let demo = DemoTransport()
        for strip in StripID.everything {
            var addresses = [strip.namePath, strip.colorPath, strip.faderPath, strip.onPath, strip.soloPath]
            if let p = strip.panPath { addresses.append(p) }
            if let p = strip.lrAssignPath { addresses.append(p) }
            if let p = strip.dcaGroupsPath { addresses.append(p) }
            if strip.hasEQ {
                addresses.append(strip.eqOnPath)
                for b in 1...strip.eqBandCount {
                    for f in ["type", "f", "g", "q"] { addresses.append(strip.eqPath(b, f)) }
                }
            }
            if strip.hasDynamics {
                for f in ["on", "mode", "det", "env", "thr", "ratio", "knee", "mgain", "attack", "hold", "release", "mix", "auto"] {
                    addresses.append(strip.dynPath(f))
                }
            }
            if strip.hasGate {
                for f in ["on", "mode", "thr", "range", "attack", "hold", "release"] { addresses.append(strip.gatePath(f)) }
            }
            for a in addresses where DemoTransport.defaultValue(for: a) == nil {
                missing.append(a)
            }
        }
        demo.close()
        XCTAssertEqual(missing, [])
    }
}

final class AddressTests: XCTestCase {
    func testIPv4Normalisation() {
        XCTAssertEqual(IPv4.normalized("192.168.1.50"), "192.168.1.50")
        XCTAssertEqual(IPv4.normalized(" 192.168.001.050\n"), "192.168.1.50")
        XCTAssertEqual(IPv4.normalized("10.0.0.255"), "10.0.0.255")
        XCTAssertNil(IPv4.normalized("192.168.1"))
        XCTAssertNil(IPv4.normalized("192.168.1.256"))
        XCTAssertNil(IPv4.normalized("192.168..1"))
        XCTAssertNil(IPv4.normalized("192.168.1.-1"))
        XCTAssertNil(IPv4.normalized("x32.local"))
        XCTAssertNil(IPv4.normalized("1.2.3.+4"))
    }
}
