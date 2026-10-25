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

final class LayerAndEntryTests: XCTestCase {
    func testStripIDRoundTrip() {
        for s in StripID.everything {
            XCTAssertEqual(StripID(id: s.id), s)
        }
        XCTAssertNil(StripID(id: "channel-33"))
        XCTAssertNil(StripID(id: "channel-0"))
        XCTAssertNil(StripID(id: "nonsense"))
        XCTAssertNil(StripID(id: "bus-x"))
    }

    func testDCAMembers() {
        var masks: [StripID: Int] = [:]
        masks[StripID(.channel, 1)] = 0b0000_0001
        masks[StripID(.channel, 2)] = 0b0000_0011
        masks[StripID(.bus, 3)] = 0b0000_0010
        masks[StripID(.auxIn, 4)] = 0
        let dca1 = StripID.dcaMembers(1) { masks[$0] }
        XCTAssertEqual(dca1, [StripID(.channel, 1), StripID(.channel, 2)])
        let dca2 = StripID.dcaMembers(2) { masks[$0] }
        XCTAssertEqual(dca2, [StripID(.channel, 2), StripID(.bus, 3)])
        XCTAssertEqual(StripID.dcaMembers(9) { masks[$0] }, [])
        // Unknown masks are left out rather than guessed.
        XCTAssertEqual(StripID.dcaMembers(3) { _ in nil }, [])
    }

    func testUserLayersHaveNoBuiltInStrips() {
        XCTAssertEqual(MixerLayer.user1.strips, [])
        XCTAssertEqual(MixerLayer.user1.userIndex, 0)
        XCTAssertEqual(MixerLayer.user2.userIndex, 1)
        XCTAssertNil(MixerLayer.inputs1.userIndex)
        XCTAssertEqual(MixerLayer.aux.strips.count, 16)
    }

    func testTypedValues() {
        let fader = Specs.fader
        XCTAssertEqual(fader.parse("0")!, X32Math.quantize(X32Math.dbToFader(0), steps: 1023), accuracy: 0.0001)
        XCTAssertEqual(fader.parse("-6 dB")!, X32Math.quantize(X32Math.dbToFader(-6), steps: 1023), accuracy: 0.0001)
        XCTAssertEqual(fader.parse("+10")!, 1, accuracy: 0.0001)
        XCTAssertNil(fader.parse("+20"))
        XCTAssertEqual(fader.parse("off"), 0)
        XCTAssertEqual(fader.parse("-inf"), 0)
        XCTAssertNil(fader.parse("loud"))
        XCTAssertNil(fader.parse(""))

        let freq = Specs.eqFreq
        XCTAssertEqual(freq.value(freq.parse("1.2k")!), 1200, accuracy: 40)
        XCTAssertEqual(freq.value(freq.parse("250 Hz")!), 250, accuracy: 10)
        XCTAssertNil(freq.parse("99999"))
        XCTAssertEqual(freq.value(freq.parse("20khz")!), 20000, accuracy: 1)

        let gain = Specs.headampGain
        XCTAssertEqual(gain.value(gain.parse("32,5")!), 32.5, accuracy: 0.26)
        XCTAssertNil(gain.parse("−20"))
        XCTAssertNil(gain.parse("1k"), "k only means thousand for frequencies")
        XCTAssertNil(gain.parse("65"))
        XCTAssertEqual(gain.value(gain.parse("-12")!), -12, accuracy: 0.01)

        let release = Specs.release
        XCTAssertEqual(release.value(release.parse("1.5s")!), 1500, accuracy: 120)
        XCTAssertEqual(Specs.dynMix.value(Specs.dynMix.parse("50%")!), 50, accuracy: 3)
    }

    func testDelayHasDemoValue() {
        let s = StripID(.channel, 3)
        XCTAssertTrue(s.hasDelay)
        XCTAssertFalse(StripID(.bus, 1).hasDelay)
        XCTAssertNotNil(DemoTransport.defaultValue(for: s.delayPath("on")))
        XCTAssertNotNil(DemoTransport.defaultValue(for: s.delayPath("time")))
        XCTAssertEqual(Specs.delay.value(0), 0.3, accuracy: 0.001)
        XCTAssertEqual(Specs.delay.value(1), 500, accuracy: 0.001)
    }

    func testInsertAndKeyAddressesHaveDemoValuesAndNames() {
        var missing: [String] = []
        for strip in StripID.everything {
            var addresses: [String] = []
            if strip.hasInsert { addresses += ["on", "pos", "sel"].map { strip.insertPath($0) } }
            if strip.hasGate { addresses += ["keysrc", "filter/on", "filter/type", "filter/f"].map { strip.gatePath($0) } }
            if strip.hasDynamics { addresses += ["pos", "filter/on", "filter/type", "filter/f"].map { strip.dynPath($0) } }
            if strip.hasDynKeySource { addresses.append(strip.dynPath("keysrc")) }
            missing += addresses.filter { DemoTransport.defaultValue(for: $0) == nil }
        }
        XCTAssertEqual(missing, [])
        XCTAssertTrue(StripID.mainLR.hasInsert)
        XCTAssertFalse(StripID(.auxIn, 1).hasInsert)
        XCTAssertFalse(StripID(.matrix, 1).hasDynKeySource)
        XCTAssertEqual(StripID(.channel, 4).insertPath("sel"), "/ch/04/insert/sel")
        XCTAssertEqual(X32Enums.insertSelections.count, 23)
        XCTAssertEqual(X32Enums.keyFilterTypes.count, 9)
        XCTAssertEqual(AddressNames.describe("/ch/04/insert/sel"), "Ch 4 insert slot")
        XCTAssertEqual(AddressNames.describe("/ch/04/gate/keysrc"), "Ch 4 gate key source")
        XCTAssertEqual(AddressNames.describe("/bus/02/dyn/filter/f"), "Mix 2 comp key filter freq")
        XCTAssertEqual(AddressNames.describe("/ch/01/dyn/pos"), "Ch 1 comp position")
    }

    func testDynamicsCopyCarriesKeySettings() {
        let ch = StripID(.channel, 1)
        XCTAssertTrue(ch.relativePaths(.gate).contains("/gate/keysrc"))
        XCTAssertTrue(ch.relativePaths(.comp).contains("/dyn/filter/f"))
        XCTAssertTrue(ch.relativePaths(.comp).contains("/dyn/keysrc"))
        XCTAssertFalse(StripID(.matrix, 1).relativePaths(.comp).contains("/dyn/keysrc"))
    }
}

final class UndoTests: XCTestCase {
    func testCoalescesRepeatedChangesToOneControl() {
        let u = UndoStack(limit: 10, coalesceWindow: 1.5)
        u.record(address: "/ch/01/mix/fader", previous: .float(0.5), newValue: .float(0.55), label: "Ch 1 fader", now: 100)
        u.record(address: "/ch/01/mix/fader", previous: .float(0.55), newValue: .float(0.6), label: "Ch 1 fader", now: 100.5)
        XCTAssertEqual(u.entries.count, 1)
        XCTAssertEqual(u.last?.changes.first?.previous, .float(0.5), "undo goes back to before the burst")
        u.record(address: "/ch/01/mix/fader", previous: .float(0.6), newValue: .float(0.7), label: "Ch 1 fader", now: 103)
        XCTAssertEqual(u.entries.count, 2, "a later change is its own step")
        u.record(address: "/ch/02/mix/on", previous: .int(1), newValue: .int(0), label: "Ch 2 mute", now: 103.1)
        XCTAssertEqual(u.entries.count, 3, "a different control is its own step")
        u.record(address: "/ch/02/mix/on", previous: .int(0), newValue: .int(1), label: "Ch 2 mute", now: 103.4)
        XCTAssertEqual(u.entries.count, 2, "tapped on and straight off again leaves nothing to undo")
    }

    func testLimitAndPop() {
        let u = UndoStack(limit: 3)
        for i in 0..<5 {
            u.push(UndoEntry(label: "\(i)", changes: [UndoEntry.Change(address: "/a/\(i)", previous: .int(0))], time: Double(i * 10)))
        }
        XCTAssertEqual(u.entries.map(\.label), ["2", "3", "4"])
        XCTAssertEqual(u.popLast()?.label, "4")
        XCTAssertEqual(u.entries.count, 2)
        u.push(UndoEntry(label: "empty", changes: [], time: 0))
        XCTAssertEqual(u.entries.count, 2, "empty steps are ignored")
        u.clear()
        XCTAssertTrue(u.isEmpty)
    }

    func testAddressNames() {
        XCTAssertEqual(AddressNames.describe("/ch/16/mix/fader"), "Ch 16 fader")
        XCTAssertEqual(AddressNames.describe("/ch/01/mix/on"), "Ch 1 mute")
        XCTAssertEqual(AddressNames.describe("/ch/03/mix/05/level"), "Ch 3 send to Mix 5")
        XCTAssertEqual(AddressNames.describe("/bus/02/mix/03/level"), "Mix 2 send to Mtx 3")
        XCTAssertEqual(AddressNames.describe("/ch/16/eq/2/g"), "Ch 16 EQ 2 gain")
        XCTAssertEqual(AddressNames.describe("/ch/01/dyn/thr"), "Ch 1 comp threshold")
        XCTAssertEqual(AddressNames.describe("/ch/01/gate/range"), "Ch 1 gate depth")
        XCTAssertEqual(AddressNames.describe("/main/st/mix/fader"), "LR fader")
        XCTAssertEqual(AddressNames.describe("/dca/3/fader"), "DCA 3 fader")
        XCTAssertEqual(AddressNames.describe("/headamp/033/gain"), "A 02 gain")
        XCTAssertEqual(AddressNames.describe("/config/mute/2"), "Mute group 2")
        XCTAssertEqual(AddressNames.describe("/config/solo/level"), "Solo level")
        XCTAssertEqual(AddressNames.describe("/ch/05/preamp/hpf"), "Ch 5 low cut freq")
        XCTAssertNil(AddressNames.split("/ch/99/mix/fader"))
        XCTAssertEqual(StripID.headampLabel(0), "Loc 01")
        XCTAssertEqual(StripID.headampLabel(127), "B 48")
    }
}

final class ClipboardTests: XCTestCase {
    func testCopyEQFromChannelToChannel() {
        let src = StripID(.channel, 1)
        let dst = StripID(.channel, 2)
        var store: [String: OSCArg] = [:]
        for rel in src.relativePaths(.eq) { store[src.base + rel] = .float(0.25) }
        store[src.base + "/eq/1/type"] = .int(1)
        let clip = ChannelClipboard.copy(from: src, sections: [.eq]) { store[$0] }
        let changes = clip.changes(onto: dst)
        XCTAssertEqual(changes.count, src.relativePaths(.eq).count)
        XCTAssertTrue(changes.allSatisfy { $0.0.hasPrefix("/ch/02/eq/") })
        XCTAssertTrue(changes.contains { $0.0 == "/ch/02/eq/1/type" && $0.1 == .int(1) })
    }

    func testBusEQOntoChannelSkipsExtraBandsAndTypes() {
        let bus = StripID(.bus, 1)
        let ch = StripID(.channel, 5)
        var store: [String: OSCArg] = [:]
        for rel in bus.relativePaths(.eq) { store[bus.base + rel] = .float(0.5) }
        store[bus.base + "/eq/1/type"] = .int(7)   // a bus-only crossover type
        store[bus.base + "/eq/2/type"] = .int(2)
        let clip = ChannelClipboard.copy(from: bus, sections: [.eq]) { store[$0] }
        let changes = clip.changes(onto: ch)
        XCTAssertFalse(changes.contains { $0.0.contains("/eq/5/") || $0.0.contains("/eq/6/") })
        XCTAssertFalse(changes.contains { $0.0 == "/ch/05/eq/1/type" }, "bus-only types are not pasted")
        XCTAssertTrue(changes.contains { $0.0 == "/ch/05/eq/2/type" && $0.1 == .int(2) })
    }

    func testSendsOnlyBetweenSameKind() {
        let ch = StripID(.channel, 1)
        var store: [String: OSCArg] = [:]
        for rel in ch.relativePaths(.sends) { store[ch.base + rel] = .float(0.3) }
        let clip = ChannelClipboard.copy(from: ch, sections: [.sends, .gate]) { store[$0] }
        XCTAssertEqual(clip.sections(for: StripID(.auxIn, 2)), [.sends], "aux has sends but no gate")
        XCTAssertEqual(clip.sections(for: StripID(.bus, 2)), [], "channel sends never go onto bus->matrix sends")
        XCTAssertTrue(clip.changes(onto: StripID(.bus, 2)).isEmpty)
    }

    func testOnlyKnownValuesAreCopiedAndGainIsNever() {
        let ch = StripID(.channel, 3)
        let clip = ChannelClipboard.copy(from: ch, sections: [.preamp]) { $0.hasSuffix("/trim") ? .float(0.6) : nil }
        XCTAssertEqual(clip.values.count, 1)
        XCTAssertFalse(ch.relativePaths(.preamp).contains { $0.contains("headamp") || $0.contains("gain") })
        XCTAssertEqual(clip.changes(onto: StripID(.channel, 4)).map(\.0), ["/ch/04/preamp/trim"])
        XCTAssertTrue(ch.relativePaths(.sends).contains("/mix/01/type"), "send tap points travel with the levels")
        XCTAssertFalse(ch.relativePaths(.sends).contains("/mix/02/type"))
    }
}

final class LinkTests: XCTestCase {
    func testLinkPathsAndPartners() {
        XCTAssertEqual(StripID(.channel, 1).linkPath, "/config/chlink/1-2")
        XCTAssertEqual(StripID(.channel, 2).linkPath, "/config/chlink/1-2")
        XCTAssertEqual(StripID(.channel, 32).linkPartner, StripID(.channel, 31))
        XCTAssertEqual(StripID(.auxIn, 7).linkPath, "/config/auxlink/7-8")
        XCTAssertEqual(StripID(.fxReturn, 3).linkPartner, StripID(.fxReturn, 4))
        XCTAssertEqual(StripID(.bus, 16).linkPath, "/config/buslink/15-16")
        XCTAssertEqual(StripID(.matrix, 5).linkPath, "/config/mtxlink/5-6")
        XCTAssertNil(StripID.mainLR.linkPath)
        XCTAssertNil(StripID(.dca, 1).linkPartner)
        // 16 + 4 + 4 + 8 + 3 pairs, plus the four link settings.
        XCTAssertEqual(StripID.allLinkPaths.count, 35 + 4)
        XCTAssertEqual(Set(StripID.allLinkPaths).count, StripID.allLinkPaths.count)
    }

    func testPartnerAddressOnlyWhenLinked() {
        let linked: Set<StripID> = [StripID(.channel, 1), StripID(.channel, 2)]
        let isLinked: (StripID) -> Bool = { linked.contains($0) }
        XCTAssertEqual(LinkSync.partnerAddress(for: "/ch/01/mix/fader", isLinked: isLinked), "/ch/02/mix/fader")
        XCTAssertEqual(LinkSync.partnerAddress(for: "/ch/02/eq/3/g", isLinked: isLinked), "/ch/01/eq/3/g")
        XCTAssertNil(LinkSync.partnerAddress(for: "/ch/03/mix/fader", isLinked: isLinked))
        XCTAssertNil(LinkSync.partnerAddress(for: "/ch/01/config/name", isLinked: isLinked), "names stay separate")
        XCTAssertNil(LinkSync.partnerAddress(for: "/main/st/mix/fader", isLinked: { _ in true }))
        XCTAssertNil(LinkSync.partnerAddress(for: "/config/chlink/1-2", isLinked: { _ in true }))
    }

    func testLinkUndoNames() {
        XCTAssertEqual(AddressNames.describe("/config/chlink/3-4"), "Ch 3-4 link")
        XCTAssertEqual(AddressNames.describe("/config/buslink/1-2"), "Mix 1-2 link")
    }

    func testDemoAnswersLinkState() {
        for p in StripID.allLinkPaths {
            XCTAssertNotNil(DemoTransport.defaultValue(for: p), p)
        }
    }
}

final class EffectsTests: XCTestCase {
    /// Parameter layouts per type from the X32 protocol ('f' float, 'i' int), first 16 parameters.
    let layouts: [Int: String] = [
        0: "ffffffffffff", 1: "ffffffffff", 2: "ffffffffffffffff", 3: "ffffffffffffffff",
        4: "ffffffffffffffff", 5: "ffffffffffff", 6: "fffiifffff", 7: "ffffffffffffi",
        8: "ffffffffff", 9: "fffffffff", 10: "ffiiifffffff", 11: "ffffffiffiffiii",
        12: "ffffffifififiii", 13: "fffffffffff", 14: "ffffffffffff"
    ]

    func testParameterLayoutsMatchTheDesk() {
        for (type, layout) in layouts {
            guard let params = Effects.parameters(type: type) else {
                XCTFail("missing type \(type)")
                continue
            }
            XCTAssertEqual(params.count, layout.count, "type \(type) parameter count")
            for (i, ch) in layout.enumerated() where i < params.count {
                let isInt: Bool
                if case .choice = params[i].kind { isInt = true } else { isInt = false }
                XCTAssertEqual(isInt, ch == "i", "type \(type) parameter \(i + 1) (\(params[i].name))")
                XCTAssertEqual(params[i].number, i + 1)
            }
        }
        XCTAssertNil(Effects.parameters(type: 15))
    }

    /// Each type's parameters as the X32 emulator sends them ('f' float, 'i' int).
    let wire: [String: String] = [
        "HALL": "ffffffffffff", "AMBI": "ffffffffff", "RPLT": "ffffffffffffffff", "ROOM": "ffffffffffffffff",
        "CHAM": "ffffffffffffffff", "PLAT": "ffffffffffff", "VREV": "fffiifffff", "VRM": "ffffffffffffi",
        "GATE": "ffffffffff", "RVRS": "fffffffff", "DLY": "ffiiifffffff", "CRS": "fffffffffff", "FLNG": "ffffffffffff",
        "PHAS": "ffffffffffff", "DIMC": "iiiiiii", "FILT": "ffffififffffii", "ROTA": "ffffffii", "PAN": "fffffffff",
        "SUB": "iifffiifff", "MODD": "fifffffiiffff", "DES2": "ffffii", "DES": "ffffii", "P1A": "iffifffifii",
        "P1A2": "iffifffifiiiffifffifii", "PQ5": "ififififi", "PQ5S": "ififififiififififi", "WAVD": "ffffff",
        "LIM": "ffffffii", "FAC": "iffffff", "FAC2": "iffffffiffffff", "LEC": "iffif", "LEC2": "iffififfif",
        "ULC": "iffffi", "ULC2": "iffffiiffffi", "ENH": "ffffffffi", "EXC2": "ffffffiffffffi", "EXC": "ffffffi",
        "IMG": "fffffff", "EDI": "iiifffff", "SON": "ifffifff", "AMP2": "ffffffffiffffffffi", "AMP": "ffffffffi",
        "DRV2": "ffffffffffffffffffff", "DRV": "ffffffffff", "PIT2": "ffffffffffff", "PIT": "ffffff"
    ]

    func testEveryEditableTypeMatchesTheDesk() {
        var editable = 0
        for (slot, codes) in [(1, Effects.typeCodes1), (5, Effects.typeCodes2)] {
            for (type, code) in codes.enumerated() {
                guard let params = Effects.parameters(slot: slot, type: type) else { continue }
                editable += 1
                let kinds = params.map { p -> Character in
                    if case .choice = p.kind { return "i" } else { return "f" }
                }
                if let expected = wire[code] {
                    XCTAssertEqual(String(kinds), expected, "\(code) in slot \(slot)")
                }
                XCTAssertEqual(params.map(\.number), Array(1...params.count))
                XCTAssertEqual(Effects.parameterCount(slot: slot, type: type), params.count)
            }
        }
        XCTAssertGreaterThan(editable, 70)
        for code in Effects.uncertainTypes {
            let t = Effects.typeCodes1.firstIndex(of: code)!
            XCTAssertNil(Effects.parameters(slot: 1, type: t), code)
        }
        XCTAssertNil(Effects.parameters(slot: 5, type: 0), "graphic EQs use their own editor")
        XCTAssertEqual(Effects.parameterCount(slot: 5, type: 0), 64)
        // Every type appears exactly once in the type menu.
        for (slot, codes) in [(1, Effects.typeCodes1), (5, Effects.typeCodes2)] {
            let listed = Effects.typeMenu(slot: slot).flatMap { $0.1.map(\.0) }
            XCTAssertEqual(listed.sorted(), Array(0..<codes.count), "slot \(slot)")
        }
        XCTAssertEqual(Set(Effects.typeCodes1).subtracting(Effects.friendlyNames.keys), [])
    }

    func testNamesAndSources() {
        XCTAssertEqual(Effects.typeName(slot: 1, type: 0), "Hall Reverb")
        XCTAssertEqual(Effects.typeName(slot: 3, type: 10), "Stereo Delay")
        XCTAssertEqual(Effects.typeName(slot: 2, type: 27), "Dual Graphic EQ")
        XCTAssertEqual(Effects.typeName(slot: 6, type: 0), "Dual Graphic EQ")
        XCTAssertEqual(Effects.typeName(slot: 6, type: 11), "Precision Limiter")
        XCTAssertEqual(Effects.typeCodes1.count, 61)
        XCTAssertEqual(Effects.sourceName(0), "Insert")
        XCTAssertEqual(Effects.sourceName(13), "Mix 13")
        XCTAssertEqual(Effects.feedingBus(sourceValue: 13), 13)
        XCTAssertNil(Effects.feedingBus(sourceValue: 17))
        XCTAssertEqual(Effects.returnStrips(slot: 2), [StripID(.fxReturn, 3), StripID(.fxReturn, 4)])
        XCTAssertEqual(Effects.parPath(3, 2), "/fx/3/par/02")
    }

    func testDemoAnswersEffects() {
        for a in Effects.addresses() {
            XCTAssertNotNil(DemoTransport.defaultValue(for: a), a)
        }
        XCTAssertEqual(DemoTransport.defaultValue(for: "/fx/3/type"), .int(10))
        XCTAssertEqual(DemoTransport.defaultValue(for: "/fx/3/par/03"), .int(0), "delay mode is an int")
    }
}

final class SceneSaveTests: XCTestCase {
    func testGraphicEQLayout() {
        XCTAssertEqual(Effects.geqBands.count, 31)
        XCTAssertEqual(Effects.graphicEQSides(slot: 1, type: 27), 2, "GEQ2 in slots 1-4")
        XCTAssertEqual(Effects.graphicEQSides(slot: 2, type: 30), 1, "TEQ in slots 1-4")
        XCTAssertNil(Effects.graphicEQSides(slot: 1, type: 0))
        XCTAssertEqual(Effects.graphicEQSides(slot: 5, type: 0), 2, "GEQ2 in slots 5-8")
        XCTAssertEqual(Effects.graphicEQSides(slot: 8, type: 1), 1)
        XCTAssertNil(Effects.graphicEQSides(slot: 6, type: 4), "De-esser")
        XCTAssertEqual(Effects.typeCodes1[27], "GEQ2")
        XCTAssertEqual(Effects.typeCodes2[3], "TEQ")
        XCTAssertEqual(Effects.geqParNumber(side: 1, band: 1), 33)
        XCTAssertEqual(Effects.geqMasterNumber(side: 1), 64)
        XCTAssertEqual(Effects.parameterCount(slot: 5, type: 0), 64)
        XCTAssertEqual(Effects.parameterCount(slot: 1, type: 0), 12, "Hall has 12")
        XCTAssertEqual(Effects.parPath(5, 64), "/fx/5/par/64")
        XCTAssertEqual(Effects.geqBandLabel(0), "20")
        XCTAssertEqual(Effects.geqBandLabel(2), "31.5")
        XCTAssertEqual(Effects.geqBandLabel(17), "1k")
        XCTAssertEqual(Effects.geqBandLabel(18), "1.25k")
        XCTAssertEqual(Effects.geqBandLabel(30), "20k")
        XCTAssertEqual(Effects.geqSpec.value(0), -15, accuracy: 0.001)
        XCTAssertEqual(Effects.geqSpec.value(1), 15, accuracy: 0.001)
    }

    func testInsertedOnAndKeySources() {
        let sel: [String: Int] = ["/bus/01/insert/sel": 9, "/bus/02/insert/sel": 10, "/ch/05/insert/sel": 3, "/ch/06/insert/sel": 4,
                                  "/bus/01/insert/on": 1, "/bus/02/insert/on": 1, "/ch/05/insert/on": 1, "/ch/06/insert/on": 0]
        XCTAssertEqual(Effects.insertedOn(slot: 5) { sel[$0] }, [StripID(.bus, 1), StripID(.bus, 2)])
        XCTAssertEqual(Effects.insertedOn(slot: 2) { sel[$0] }, [StripID(.channel, 5)], "switched-off inserts don't count")
        XCTAssertTrue(Effects.addresses().contains("/main/st/insert/sel"))
        XCTAssertNil(StripID.keySource(0))
        XCTAssertEqual(StripID.keySource(1), StripID(.channel, 1))
        XCTAssertEqual(StripID.keySource(40), StripID(.auxIn, 8))
        XCTAssertEqual(StripID.keySource(41), StripID(.fxReturn, 1))
        XCTAssertEqual(StripID.keySource(64), StripID(.bus, 16))
        XCTAssertEqual(DemoTransport.defaultValue(for: "/bus/02/insert/sel"), .int(10))
        XCTAssertEqual(DemoTransport.defaultValue(for: "/bus/05/insert/on"), .int(0))
    }

    func testRTABlobAndSources() {
        let levels: [Float] = (0..<100).map { -Float($0) * 0.5 }
        let blob = RTA.encode(levels)
        XCTAssertEqual(blob.count, 4 + 200)
        XCTAssertEqual(Array(blob.prefix(4)), [50, 0, 0, 0], "count is in 32-bit words")
        XCTAssertEqual(RTA.decode(blob), levels)
        // -93.0 dB as the desk sends it: 0xA3 0x00 little-endian bytes of Int16(-93 * 256).
        let raw = UInt16(bitPattern: Int16(-93 * 256))
        XCTAssertEqual(RTA.decode(Data([1, 0, 0, 0, UInt8(raw & 0xff), UInt8(raw >> 8), 0, 0])), [-93, 0])
        XCTAssertEqual(RTA.decode(Data([50, 0, 0, 0, 1])), [], "truncated blobs don't crash")
        XCTAssertEqual(RTA.frequency(90), 10000, accuracy: 0.01)
        XCTAssertEqual(RTA.frequency(0), 19.53, accuracy: 0.01)
        XCTAssertEqual(RTA.sourceValue(for: StripID(.channel, 1)), 2)
        XCTAssertEqual(RTA.sourceValue(for: StripID(.channel, 32)), 33)
        XCTAssertEqual(RTA.sourceValue(for: StripID(.auxIn, 1)), 34)
        XCTAssertEqual(RTA.sourceValue(for: StripID(.fxReturn, 8)), 49)
        XCTAssertEqual(RTA.sourceValue(for: StripID(.bus, 1)), 50)
        XCTAssertEqual(RTA.sourceValue(for: StripID(.matrix, 6)), 71)
        XCTAssertEqual(RTA.sourceValue(for: StripID.mainLR), 72)
        XCTAssertEqual(RTA.sourceValue(for: StripID.monoC), 73)
        XCTAssertNil(RTA.sourceValue(for: StripID(.dca, 1)))
    }

    func testPresetsRoundTripAndFit() throws {
        let ch = StripID(.channel, 3)
        var store: [String: OSCArg] = [:]
        for section in ChannelPreset.sections {
            for rel in ch.relativePaths(section) { store[ch.base + rel] = .float(0.3) }
        }
        store[ch.base + "/eq/2/type"] = .int(2)
        store[ch.base + "/gate/keysrc"] = .int(0)
        let clip = ChannelClipboard.copy(from: ch, sections: ChannelPreset.sections) { store[$0] }
        let preset = ChannelPreset(name: "Vox", clip: clip)
        let defaults = UserDefaults(suiteName: "presets-test-\(UUID().uuidString)")!
        PresetLibrary.save([preset], to: defaults)
        let loaded = PresetLibrary.load(from: defaults)
        XCTAssertEqual(loaded, [preset])
        XCTAssertEqual(loaded.first?.clip.values["/eq/2/type"], .int(2))
        XCTAssertEqual(preset.summary, "Preamp, Gate, EQ, Compressor")
        // Onto a bus: only EQ and compressor fit.
        XCTAssertEqual(preset.clip.sections(for: StripID(.bus, 1)), [.eq, .comp])
        XCTAssertEqual(preset.clipboard(only: [.eq]).sections, [.eq])
        XCTAssertTrue(preset.clipboard(only: [.eq]).changes(onto: StripID(.channel, 9)).allSatisfy { $0.0.hasPrefix("/ch/09/eq/") })
        XCTAssertEqual(PresetLibrary.sorted([ChannelPreset(name: "b", clip: clip), ChannelPreset(name: "A", clip: clip)]).map(\.name), ["A", "b"])
    }

    func testOutputPatch() {
        XCTAssertEqual(Outputs.sourceNames.count, 77)
        XCTAssertEqual(Outputs.sourceName(0), "Off")
        XCTAssertEqual(Outputs.sourceName(4), "Mix 1")
        XCTAssertEqual(Outputs.sourceName(25), "Mtx 6")
        XCTAssertEqual(Outputs.sourceName(26), "Ch 1 direct")
        XCTAssertEqual(Outputs.sourceName(66), "FX 1L direct")
        XCTAssertEqual(Outputs.sourceName(73), "FX 4R direct")
        XCTAssertEqual(Outputs.sourceName(76), "Talkback")
        XCTAssertEqual(Outputs.sourceStrip(19), StripID(.bus, 16))
        XCTAssertEqual(Outputs.sourceStrip(57), StripID(.channel, 32))
        XCTAssertEqual(Outputs.sourceStrip(65), StripID(.auxIn, 8))
        XCTAssertNil(Outputs.sourceStrip(74))
        XCTAssertTrue(Outputs.isDirectOut(26))
        XCTAssertFalse(Outputs.isDirectOut(19))
        XCTAssertEqual(Outputs.tapNames.count, 9)
        XCTAssertEqual(Outputs.path(.p16, 3, "src"), "/outputs/p16/03/src")
        XCTAssertEqual(Outputs.addresses().count, 42 * 3 + 16 * 2, "src, pos, invert for every output; delay on local outs")
        XCTAssertEqual(AddressNames.describe("/outputs/main/02/delay/time"), "Out 2 delay time")
        XCTAssertEqual(AddressNames.describe("/outputs/aux/01/invert"), "Aux 1 polarity")
        XCTAssertTrue(Outputs.hasDelay(.main))
        XCTAssertFalse(Outputs.hasDelay(.p16))
        XCTAssertEqual(AddressNames.describe("/outputs/main/03/src"), "Out 3 source")
        XCTAssertEqual(AddressNames.describe("/outputs/p16/12/pos"), "P16 12 tap point")
        XCTAssertTrue(Outputs.addresses().allSatisfy { DemoTransport.defaultValue(for: $0) != nil })
        XCTAssertEqual(Set(Outputs.sourceGroups.flatMap { Array($0.1) }).count, 76, "every source but Off is in a group")
    }

    func testMonitoringSettings() {
        XCTAssertEqual(Monitoring.sources.count, 7)
        XCTAssertEqual(Monitoring.talkDestinations.count, 18, "the desk's destination map is 18 bits")
        XCTAssertEqual(Monitoring.talkDestinations[16], "LR")
        XCTAssertTrue(Monitoring.addresses.allSatisfy { DemoTransport.defaultValue(for: $0) != nil })
    }

    func testEffectUndoNames() {
        let types = [1: 10, 5: 0, 7: 1]
        XCTAssertEqual(Effects.describe("/fx/1/par/02", type: { types[$0] }), "FX 1 Time")
        XCTAssertEqual(Effects.describe("/fx/5/par/33", type: { types[$0] }), "FX 5 GEQ B 20 Hz")
        XCTAssertEqual(Effects.describe("/fx/5/par/32", type: { types[$0] }), "FX 5 GEQ A level")
        XCTAssertEqual(Effects.describe("/fx/7/par/18", type: { types[$0] }), "FX 7 GEQ 1k Hz")
        XCTAssertEqual(Effects.describe("/fx/2/par/03", type: { _ in nil }), "FX 2 parameter 3")
        XCTAssertEqual(Effects.describe("/fx/2/type", type: { _ in nil }), "FX 2 type")
        XCTAssertNil(Effects.describe("/ch/01/mix/fader", type: { _ in nil }))
    }

    func testPresetStoreSurvivesABadEntry() throws {
        let defaults = UserDefaults(suiteName: "presets-bad-\(UUID().uuidString)")!
        let clip = ChannelClipboard(source: StripID(.channel, 1), sections: [.eq], values: ["/eq/on": .int(1)])
        let good = try JSONEncoder().encode([ChannelPreset(name: "Good", clip: clip)])
        var array = try JSONSerialization.jsonObject(with: good) as! [Any]
        array.append(["name": "Broken"])
        defaults.set(try JSONSerialization.data(withJSONObject: array), forKey: PresetLibrary.key)
        let loaded = PresetLibrary.load(from: defaults)
        XCTAssertEqual(loaded.map(\.name), ["Good"])
        XCTAssertNotNil(defaults.data(forKey: PresetLibrary.key + ".backup"), "the original is kept")
        defaults.set(Data("not json".utf8), forKey: PresetLibrary.key)
        XCTAssertEqual(PresetLibrary.load(from: defaults), [])
    }

    func testRecorderStates() {
        XCTAssertEqual(Recorder.State.record.rawValue, 4)
        XCTAssertEqual(Recorder.pauseTarget(from: .play), .playPaused)
        XCTAssertEqual(Recorder.pauseTarget(from: .recordPaused), .record)
        XCTAssertNil(Recorder.pauseTarget(from: .stop))
        XCTAssertTrue(Recorder.addresses.allSatisfy { DemoTransport.defaultValue(for: $0) != nil })
    }

    func testInputRouting() {
        XCTAssertEqual(InputRouting.blocks.count, 5)
        XCTAssertEqual(InputRouting.label("AN9-16"), "Local in 9–16")
        XCTAssertEqual(InputRouting.label("A33-40"), "AES50-A 33–40")
        XCTAssertEqual(InputRouting.label("B1-8"), "AES50-B 1–8")
        XCTAssertEqual(InputRouting.label("CARD25-32"), "Card 25–32")
        XCTAssertEqual(InputRouting.label("AUX1-4"), "Local aux in 1–4")
        XCTAssertEqual(InputRouting.channelCodes.count, 24)
        XCTAssertEqual(InputRouting.channelCodes[19], "CARD25-32", "the 20 options every firmware has come first")
        XCTAssertEqual(InputRouting.auxCodes[12], "CARD1-6")
        XCTAssertTrue(InputRouting.addresses.allSatisfy { DemoTransport.defaultValue(for: $0) != nil })
        XCTAssertEqual(AddressNames.describe("/config/routing/IN/9-16"), "Ch 9–16 input routing")
        XCTAssertEqual(OutputRouting.local.count + OutputRouting.aes50A.count + OutputRouting.aes50B.count + OutputRouting.card.count, 20)
        XCTAssertEqual(OutputRouting.aes50A[5].path, "/config/routing/AES50A/41-48")
        XCTAssertEqual(OutputRouting.card[3].path, "/config/routing/CARD/25-32")
        XCTAssertEqual(OutputRouting.local[1].options[20], "OUT5-8")
        XCTAssertEqual(OutputRouting.localCodesA.count, 26)
        XCTAssertEqual(OutputRouting.digitalCodes.count, 26)
        XCTAssertEqual(InputRouting.label("OUT9-16"), "Out 9–16")
        XCTAssertEqual(InputRouting.label("P165-8"), "P16 5–8")
        XCTAssertEqual(InputRouting.label("AUX/CR"), "Aux out / Control room")
        XCTAssertEqual(InputRouting.offered(OutputRouting.card[0]), 26)
        XCTAssertEqual(OutputRouting.play[4].path, "/config/routing/PLAY/AUX")
        XCTAssertTrue(OutputRouting.addresses.allSatisfy { DemoTransport.defaultValue(for: $0) != nil })
        XCTAssertTrue(Outputs.addresses().allSatisfy { DemoTransport.defaultValue(for: $0) != nil })
        XCTAssertEqual(AddressNames.describe("/config/routing/AES50B/9-16"), "AES50 B 9–16 routing")
    }

    func testAutomixAndOscillator() {
        XCTAssertEqual(Automix.groupPath(StripID(.channel, 7)), "/ch/07/automix/group")
        XCTAssertNil(Automix.groupPath(StripID(.bus, 1)), "only channels have automix")
        XCTAssertEqual(Automix.weightSpec.value(Automix.weightSpec.norm(3.5)), 3.5, accuracy: 0.01)
        XCTAssertEqual(Automix.addresses(StripID(.channel, 1)).count, 2)
        XCTAssertTrue((Automix.globalAddresses + Automix.addresses(StripID(.channel, 1))).allSatisfy { DemoTransport.defaultValue(for: $0) != nil })
        XCTAssertEqual(Oscillator.destinations.count, 26)
        XCTAssertEqual(Oscillator.destinationName(16), "Main L")
        XCTAssertEqual(Oscillator.destinationName(19), "M/C")
        XCTAssertEqual(Oscillator.destinationName(25), "Mtx 6")
        XCTAssertEqual(Oscillator.frequencySpec.value(0), 20, accuracy: 0.01)
        XCTAssertEqual(Oscillator.frequencySpec.value(1), 20000, accuracy: 1)
        XCTAssertEqual(Oscillator.frequencySpec.steps, 120)
        XCTAssertTrue(Oscillator.addresses.allSatisfy { DemoTransport.defaultValue(for: $0) != nil })
        XCTAssertEqual(AddressNames.describe(Oscillator.onPath), "Generator on")
        XCTAssertEqual(AddressNames.describe("/ch/03/automix/weight"), "Ch 3 automix weight")
    }

    func testTapTempo() {
        var t = TapTempo()
        XCTAssertNil(t.tap(at: 10))
        XCTAssertEqual(t.tap(at: 10.5) ?? 0, 500, accuracy: 0.01)
        XCTAssertEqual(t.tap(at: 11.0) ?? 0, 500, accuracy: 0.01)
        XCTAssertEqual(t.tap(at: 11.6) ?? 0, 533.33, accuracy: 0.01, "averages the gaps")
        XCTAssertNil(t.tap(at: 20), "a long pause starts again")
        XCTAssertEqual(TapTempo().resetAfter > 3, true, "slow tempos up to 3 s can be tapped")
        XCTAssertEqual(t.tap(at: 20.25) ?? 0, 250, accuracy: 0.01)
        for i in 1...10 { _ = t.tap(at: 20.25 + Double(i) * 0.4) }
        XCTAssertEqual(t.taps.count, 5, "only the last few taps count")
        XCTAssertEqual(t.tap(at: 24.65) ?? 0, 400, accuracy: 0.01)
        XCTAssertEqual(TapTempo.bpm(ms: 500), 120, accuracy: 0.001)
        XCTAssertEqual(Effects.tapTimeParameter(slot: 3, type: 10), 2)
        XCTAssertEqual(Effects.tapTimeParameter(slot: 1, type: 12), 1)
        XCTAssertNil(Effects.tapTimeParameter(slot: 1, type: 0))
        XCTAssertNil(Effects.tapTimeParameter(slot: 5, type: 10))
        XCTAssertEqual(Effects.delayTimeSpec.value(Effects.delayTimeSpec.norm(500)), 500, accuracy: 0.01)
    }

    func testRTAIdleAndFall() {
        let rta = RTAData()
        let flat = [Float](repeating: -97, count: 100)
        for i in 0..<12 { rta.ingest(flat, now: Double(i)) }
        XCTAssertTrue(rta.idle, "an unchanging flat frame means the desk's analyser isn't running")
        XCTAssertEqual(rta.levels.first, RTA.floorDB)
        var live = flat
        live[10] = -20
        rta.ingest(live, now: 20)
        XCTAssertFalse(rta.idle)
        XCTAssertEqual(rta.levels[10], -20, "rises instantly")
        rta.ingest(flat, now: 21)
        XCTAssertEqual(rta.levels[10], -22, "falls gently")
    }

    func testDemoDeskSendsRTA() {
        let demo = DemoTransport()
        let client = X32Client(transport: demo)
        var rta: [Float] = []
        client.onMeters = { block, values in
            if block == RTA.block { rta = values }
        }
        client.setMeterSubscriptions([RTA.block])
        client.set(RTA.sourcePath, .int(2))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(rta.count, 100)
        XCTAssertTrue(rta.allSatisfy { $0 <= 0 && $0 >= -128 })
        XCTAssertNotNil(DemoTransport.defaultValue(for: RTA.positionPath))
        client.close()
    }

    func testShowCuesAndPositions() {
        XCTAssertEqual(Show.cueNumber(100), "1.0.0")
        XCTAssertEqual(Show.cueNumber(123), "1.2.3")
        XCTAssertEqual(Show.cueNumber(1000), "10.0.0")
        XCTAssertEqual(Show.cueNumber(-1), "—")
        XCTAssertEqual(Show.cuePath(7, "numb"), "/-show/showfile/cue/007/numb")
        XCTAssertEqual(Show.snippetPath(3, "hasdata"), "/-show/showfile/snippet/003/hasdata")
        XCTAssertEqual(Show.Control.cues.goAction, "/-action/gocue")
        XCTAssertEqual(Show.listAddresses(.cues).count, 2 + 500 * 2)
        XCTAssertEqual(Show.listAddresses(.snippets).count, 2 + 100 * 2)
        XCTAssertNil(Show.cueScene(scene: -1))
        XCTAssertEqual(Show.cueSnippet(bit: 4), 4)
        // GO skips cues flagged skip and stops at the end; unknown entries mean "not read yet".
        let exists: [Int: Bool] = [0: true, 1: true, 2: false, 3: true]
        XCTAssertEqual(Show.nextCue(after: 0, exists: { exists[$0] ?? false }, skipped: { $0 == 1 }), 3)
        XCTAssertEqual(Show.nextCue(after: -1, exists: { exists[$0] ?? false }, skipped: { _ in false }), 0)
        XCTAssertNil(Show.nextCue(after: 3, exists: { exists[$0] ?? false }, skipped: { _ in false }))
        XCTAssertNil(Show.nextCue(after: 0, exists: { $0 == 1 ? nil : (exists[$0] ?? false) }, skipped: { _ in false }), "unread cue")
        for a in Show.listAddresses(.cues) + Show.listAddresses(.snippets) + Show.cueDetailAddresses(0) + [Show.namePath] {
            XCTAssertNotNil(DemoTransport.defaultValue(for: a), a)
        }
    }

    func testDemoDeskFiresCues() {
        let demo = DemoTransport()
        let client = X32Client(transport: demo)
        var values: [String: OSCArg] = [:]
        client.onMessage = { m in if let v = m.args.first { values[m.address] = v } }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        client.get([Show.cuePath(2, "name"), Show.cuePath(2, "scene"), Show.controlPath, Show.snippetPath(0, "hasdata")])
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(values[Show.cuePath(2, "name")], .string("Band on"))
        XCTAssertEqual(values[Show.cuePath(2, "scene")], .int(1))
        XCTAssertEqual(values[Show.snippetPath(0, "hasdata")], .int(1))
        // Cue 1 fires scene 3 ("Speeches": band muted). Show control is scenes, so the position follows the scene.
        client.send(OSCMessage("/-action/gocue", [.int(1)]))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(values["/ch/01/mix/on"], .int(0))
        XCTAssertEqual(values[Show.currentPath], .int(3))
        client.close()
    }

    func testDemoDeskSavesScenes() {
        let demo = DemoTransport()
        var received: [OSCMessage] = []
        demo.onMessage = { received.append($0) }
        demo.send(OSCMessage("/save", [.string("scene"), .int(7), .string("Band"), .string("")]))
        let deadline = Date().addingTimeInterval(2)
        while !received.contains(where: { $0.address == "/save" }) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(received.contains(OSCMessage("/-show/showfile/scene/007/name", [.string("Band")])))
        XCTAssertTrue(received.contains(OSCMessage("/-show/showfile/scene/007/hasdata", [.int(1)])))
        demo.close()
    }
}

