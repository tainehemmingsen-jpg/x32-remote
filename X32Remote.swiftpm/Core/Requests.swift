import Foundation

/// Every list of addresses the app asks the desk for, in one place, so the integration run can
/// check that each one is something a real desk answers.
enum Requests {
    /// Everything shown on the fader screens.
    static func sync() -> [String] {
        var a: [String] = []
        a.reserveCapacity(800)
        for s in StripID.everything {
            a.append(s.namePath)
            a.append(s.colorPath)
            a.append(s.faderPath)
            a.append(s.onPath)
            if let p = s.panPath { a.append(p) }
            if let p = s.lrAssignPath { a.append(p) }
            if let p = s.dcaGroupsPath { a.append(p) }
            if let p = s.muteGroupsPath { a.append(p) }
            a.append(s.soloPath)
        }
        for n in 1...6 {
            a.append("/config/mute/\(n)")
        }
        a += ["/config/solo/level", "/config/solo/dim", "/-stat/talk/A", "/-stat/talk/B", "/config/talk/A/level", "/config/talk/B/level"]
        a += Monitoring.addresses
        a += [Show.controlPath, Show.currentPath, Show.namePath]
        a += StripID.allLinkPaths
        a.append("/-stat/solo")
        return a
    }

    /// What the strip overviews show: gain, +48, gate/EQ/comp state and the mini EQ and comp graphs.
    static func stripOverview() -> [String] {
        var a: [String] = []
        for s in StripID.everything where s.kind != .dca {
            if let ha = s.headampIndexPath { a.append(ha) }
            if s.kind == .channel || s.kind == .auxIn { a.append(s.sourcePath) }
            if s.hasTrim { a.append(s.preampPath("trim")) }
            if s.hasHighPass {
                a.append(s.preampPath("hpon"))
                a.append(s.preampPath("hpf"))
                a.append(s.preampPath("hpslope"))
            }
            if s.hasGate {
                for field in ["on", "mode", "thr", "range"] {
                    a.append(s.gatePath(field))
                }
            }
            if s.hasEQ {
                a.append(s.eqOnPath)
                for band in 1...s.eqBandCount {
                    for field in ["type", "f", "g", "q"] {
                        a.append(s.eqPath(band, field))
                    }
                }
            }
            if s.hasDynamics {
                for field in ["on", "mode", "thr", "ratio", "knee", "mgain"] {
                    a.append(s.dynPath(field))
                }
            }
        }
        return a
    }

    /// One mix bus's sends from every source, plus the bus itself.
    static func sends(bus: Int) -> [String] {
        guard bus >= 1, bus <= 16 else { return [] }
        var a: [String] = []
        for s in StripID.busSources {
            a.append(s.sendLevelPath(bus))
            a.append(s.sendOnPath(bus))
            a.append(s.sendTypePath(bus))
        }
        let b = StripID(.bus, bus)
        a.append(b.faderPath)
        a.append(b.onPath)
        a.append(b.namePath)
        a.append(b.colorPath)
        return a
    }

    /// Everything on a strip's channel page.
    static func detail(_ s: StripID) -> [String] {
        var a: [String] = [s.namePath, s.colorPath, s.faderPath, s.onPath, s.soloPath]
        if let p = s.panPath { a.append(p) }
        if s.hasTrim {
            a.append(s.preampPath("trim"))
        }
        if s.hasPolarity {
            a.append(s.preampPath("invert"))
        }
        if s.hasHighPass {
            a.append(s.preampPath("hpon"))
            a.append(s.preampPath("hpf"))
            a.append(s.preampPath("hpslope"))
        }
        if s.hasDelay {
            a.append(s.delayPath("on"))
            a.append(s.delayPath("time"))
        }
        if let ha = s.headampIndexPath {
            a.append(ha)
        }
        if s.kind == .channel || s.kind == .auxIn {
            a.append(s.sourcePath)
        }
        if s.hasEQ {
            a.append(s.eqOnPath)
            for band in 1...s.eqBandCount {
                for field in ["type", "f", "g", "q"] {
                    a.append(s.eqPath(band, field))
                }
            }
        }
        if s.hasGate {
            for field in ["on", "mode", "thr", "range", "attack", "hold", "release", "keysrc", "filter/on", "filter/type", "filter/f"] {
                a.append(s.gatePath(field))
            }
        }
        if s.hasDynamics {
            for field in ["on", "mode", "det", "env", "thr", "ratio", "knee", "mgain", "attack", "hold", "release", "mix", "auto", "pos", "filter/on", "filter/type", "filter/f"] {
                a.append(s.dynPath(field))
            }
            if s.hasDynKeySource {
                a.append(s.dynPath("keysrc"))
            }
        }
        if s.hasInsert {
            for field in ["on", "pos", "sel"] {
                a.append(s.insertPath(field))
            }
        }
        if s.sendCount > 0 {
            for n in 1...s.sendCount {
                a.append(s.sendLevelPath(n))
                a.append(s.sendOnPath(n))
                if n % 2 == 1 {
                    a.append(s.sendTypePath(n))
                    a.append(s.sendPanPath(n))
                }
            }
            if s.sendsFeedMatrix {
                for m in 1...6 {
                    let mtx = StripID(.matrix, m)
                    a.append(mtx.namePath)
                    a.append(mtx.colorPath)
                }
            }
        }
        if let p = s.lrAssignPath { a.append(p) }
        if let p = s.monoAssignPath { a.append(p) }
        if let p = s.monoLevelPath { a.append(p) }
        if let p = s.dcaGroupsPath { a.append(p) }
        if let p = s.muteGroupsPath { a.append(p) }
        a += Automix.addresses(s)
        if s.kind == .channel { a += Automix.globalAddresses }
        return a
    }

    /// The sheets and tools, for the integration run.
    static func everythingElse() -> [String] {
        var a = Effects.addresses() + Outputs.addresses() + InputRouting.addresses + OutputRouting.addresses
        a += Monitoring.addresses + Recorder.addresses + Oscillator.addresses + Automix.globalAddresses
        a += [RTA.sourcePath, RTA.positionPath, RTA.screenPath, RTA.meterPagePath]
        for control in Show.Control.allCases {
            a += Show.listAddresses(control)
        }
        a += Show.cueDetailAddresses(0)
        return a
    }
}
