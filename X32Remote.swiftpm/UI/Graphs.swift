import SwiftUI

/// Transfer curves for the gate and compressor, shared by the strip thumbnails and the big pages.
enum Dynamics {
    struct Gate {
        var on: Bool
        var threshold: Double
        var range: Double
        var mode: Int

        init(app: AppModel, strip: StripID) {
            on = app.param(strip.gatePath("on")).bool
            threshold = Double(Specs.gateThreshold.value(app.param(strip.gatePath("thr")).float(or: 0.5)))
            range = Double(Specs.gateRange.value(app.param(strip.gatePath("range")).float(or: 1)))
            mode = app.param(strip.gatePath("mode")).int(or: 3)
        }

        func output(_ input: Double) -> Double {
            guard on else { return input }
            switch mode {
            case 0, 1, 2:
                // Expanders with ratio 2, 3 and 4, never cutting more than the range.
                guard input < threshold else { return input }
                let ratio = Double(mode + 2)
                return max(threshold + (input - threshold) * ratio, input - range)
            case 4:
                // Ducker: turns the signal down by the range above the threshold.
                return input > threshold ? input - range : input
            default:
                return input < threshold ? input - range : input
            }
        }
    }

    struct Comp {
        var on: Bool
        var threshold: Double
        var ratio: Double
        var knee: Double
        var expander: Bool
        var makeup: Double

        init(app: AppModel, strip: StripID) {
            on = app.param(strip.dynPath("on")).bool
            threshold = Double(Specs.dynThreshold.value(app.param(strip.dynPath("thr")).float(or: 1)))
            let index = min(max(app.param(strip.dynPath("ratio")).int(or: 3), 0), X32Enums.ratioValues.count - 1)
            ratio = Double(X32Enums.ratioValues[index])
            knee = Double(Specs.knee.value(app.param(strip.dynPath("knee")).float(or: 0.2))) * 2
            expander = app.param(strip.dynPath("mode")).int == 1
            makeup = Double(Specs.makeup.value(app.param(strip.dynPath("mgain")).float(or: 0)))
        }

        func output(_ input: Double) -> Double {
            guard on else { return input }
            let over = input - threshold
            if expander {
                if over >= 0 { return input }
                return threshold + over * ratio
            }
            if knee > 0 && abs(over) < knee / 2 {
                let t = over + knee / 2
                return input + (1 / ratio - 1) * t * t / (2 * knee)
            }
            if over <= 0 { return input }
            return threshold + over / ratio
        }
    }

    /// Draws an input/output curve in `rect`, from `-range` dB to 0 dB on both axes.
    static func drawTransfer(
        _ ctx: inout GraphicsContext,
        _ rect: CGRect,
        range: Double,
        on: Bool,
        detailed: Bool,
        handles: [Double] = [],
        level: Double? = nil,
        output: (Double) -> Double
    ) {
        func x(_ db: Double) -> CGFloat { rect.minX + CGFloat((db + range) / range) * rect.width }
        func y(_ db: Double) -> CGFloat { rect.maxY - CGFloat((max(-range, min(0, db)) + range) / range) * rect.height }

        ctx.fill(Path(rect), with: .color(Theme.graphBack))
        if detailed {
            var grid = Path()
            for i in 1..<8 {
                let gx = rect.minX + rect.width * CGFloat(i) / 8
                let gy = rect.minY + rect.height * CGFloat(i) / 8
                grid.move(to: CGPoint(x: gx, y: rect.minY))
                grid.addLine(to: CGPoint(x: gx, y: rect.maxY))
                grid.move(to: CGPoint(x: rect.minX, y: gy))
                grid.addLine(to: CGPoint(x: rect.maxX, y: gy))
            }
            ctx.stroke(grid, with: .color(Theme.graphGrid), lineWidth: 1)
            // dB labels: input along the bottom, output up the left.
            let step = range / 4
            for i in 1..<4 {
                let db = -range + step * Double(i)
                let label = Text("\(Int(db))").font(.system(size: 10).monospacedDigit()).foregroundColor(Theme.tertiary)
                ctx.draw(label, at: CGPoint(x: x(db), y: rect.maxY - 3), anchor: .bottom)
                ctx.draw(label, at: CGPoint(x: rect.minX + 4, y: y(db)), anchor: .leading)
            }
            ctx.draw(Text("IN").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.tertiary),
                     at: CGPoint(x: rect.maxX - 4, y: rect.maxY - 3), anchor: .bottomTrailing)
            ctx.draw(Text("OUT").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.tertiary),
                     at: CGPoint(x: rect.minX + 4, y: rect.minY + 4), anchor: .topLeading)
        }

        var curve = Path()
        var area = Path()
        let steps = detailed ? 240 : 60
        area.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for i in 0...steps {
            let input = -range + range * Double(i) / Double(steps)
            let p = CGPoint(x: x(input), y: y(output(input)))
            if i == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
            area.addLine(to: p)
        }
        area.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        area.closeSubpath()
        let color = on ? Theme.curve : Theme.tertiary
        ctx.fill(area, with: .linearGradient(
            Gradient(colors: [color.opacity(on ? 0.42 : 0.15), color.opacity(0.04)]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
        ))
        ctx.stroke(curve, with: .color(color), lineWidth: detailed ? 2.5 : 1.5)

        if detailed {
            for h in handles {
                let c = CGPoint(x: x(h), y: y(output(h)))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)), with: .color(color), lineWidth: 2.5)
            }
            if let level, level > -range {
                // Where the signal is on the curve right now, with a trail down to the input axis.
                let c = CGPoint(x: x(level), y: y(output(level)))
                ctx.fill(Path(CGRect(x: c.x - 0.75, y: c.y, width: 1.5, height: rect.maxY - c.y)), with: .color(Theme.text.opacity(0.25)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)), with: .color(Theme.text.opacity(0.18)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(Theme.text))
            }
        }
    }
}

/// Gate curve for a strip. Small in the mixer; large with grid and handles on the channel pages.
struct GateGraph: View {
    let app: AppModel
    let strip: StripID
    var detailed = false
    /// Drag the top handle sideways for the threshold, the bottom one up and down for the depth.
    var interactive = false

    var body: some View {
        let gate = Dynamics.Gate(app: app, strip: strip)
        let meter = app.meters.meter(strip)
        let gr = Double(meter.gateReduction)
        // Only the big graph shows the live input dot; reading it in thumbnails would redraw them on every meter tick.
        let level: Double? = detailed ? Double(strip.kind == .channel ? meter.input : meter.level) : nil
        Canvas { ctx, size in
            let grWidth: CGFloat = detailed ? 6 : 4
            let rect = CGRect(x: 0, y: 0, width: size.width - grWidth - 2, height: size.height)
            Dynamics.drawTransfer(&ctx, rect, range: 80, on: gate.on, detailed: detailed, handles: [gate.threshold], level: level) { gate.output($0) }
            if detailed {
                // Second handle at the bottom of the step (threshold minus range).
                let x = rect.minX + CGFloat((gate.threshold + 80) / 80) * rect.width
                let yb = rect.maxY - CGFloat((max(-80, gate.threshold - gate.range) + 80) / 80) * rect.height
                ctx.stroke(Path(ellipseIn: CGRect(x: x - 9, y: yb - 9, width: 18, height: 18)), with: .color(gate.on ? Theme.curve : Theme.tertiary), lineWidth: 2.5)
            }
            drawGR(&ctx, CGRect(x: size.width - grWidth, y: 0, width: grWidth, height: size.height), gr: gate.on ? gr : 0)
        }
        .overlay {
            if interactive {
                DynamicsDragLayer(app: app, strip: strip, kind: .gate, grWidth: detailed ? 6 : 4)
            }
        }
    }
}

/// Compressor curve for a strip.
struct CompGraph: View {
    let app: AppModel
    let strip: StripID
    var detailed = false
    /// Drag the threshold handle sideways, and the top-right handle up and down for the ratio.
    var interactive = false

    var body: some View {
        let comp = Dynamics.Comp(app: app, strip: strip)
        let meter = app.meters.meter(strip)
        let gr = Double(meter.dynReduction)
        let level: Double? = detailed ? Double(strip.kind == .channel ? meter.input : meter.level) : nil
        Canvas { ctx, size in
            let grWidth: CGFloat = detailed ? 6 : 4
            let rect = CGRect(x: 0, y: 0, width: size.width - grWidth - 2, height: size.height)
            Dynamics.drawTransfer(&ctx, rect, range: 60, on: comp.on, detailed: detailed, handles: [comp.threshold, 0], level: level) { comp.output($0) }
            drawGR(&ctx, CGRect(x: size.width - grWidth, y: 0, width: grWidth, height: size.height), gr: comp.on ? gr : 0)
        }
        .overlay {
            if interactive {
                DynamicsDragLayer(app: app, strip: strip, kind: .comp, grWidth: detailed ? 6 : 4)
            }
        }
    }
}

/// Touch handling for the big gate and compressor graphs. The finger grabs the nearest handle
/// and moves it; the whole drag is one undo step.
private struct DynamicsDragLayer: View {
    enum Kind { case gate, comp }

    let app: AppModel
    let strip: StripID
    let kind: Kind
    let grWidth: CGFloat

    enum Handle { case threshold, range, ratio }

    @State private var handle: Handle?
    @State private var dragStrip: StripID?
    @State private var label: String?
    /// Handle position minus where the finger landed, so the handle doesn't jump to the finger.
    @State private var grabOffset: CGSize = .zero
    /// Depth when the drag began (its handle can sit pinned at the bottom of the graph).
    @State private var startDepth: Double = 0
    @State private var labelToken = 0
    @GestureState private var active = false

    private var range: Double { kind == .gate ? 80 : 60 }

    private func address(_ h: Handle, _ s: StripID) -> String {
        switch h {
        case .threshold: return kind == .gate ? s.gatePath("thr") : s.dynPath("thr")
        case .range: return s.gatePath("range")
        case .ratio: return s.dynPath("ratio")
        }
    }

    private func finish() {
        guard let h = handle, let s = dragStrip else { return }
        let a = address(h, s)
        app.touch(a, false)
        app.endGesture([a], label: app.undoName(a))
        handle = nil
        dragStrip = nil
        labelToken += 1
        let token = labelToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if handle == nil && labelToken == token { label = nil }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(x: 0, y: 0, width: max(geo.size.width - grWidth - 2, 1), height: max(geo.size.height, 1))
            let r = range
            let xFor: (Double) -> CGFloat = { db in rect.minX + CGFloat((db + r) / r) * rect.width }
            let yFor: (Double) -> CGFloat = { db in rect.maxY - CGFloat((max(-r, min(0, db)) + r) / r) * rect.height }
            let dbAtX: (CGFloat) -> Double = { x in Double(min(max(x, rect.minX), rect.maxX) - rect.minX) / Double(rect.width) * r - r }
            let dbAtY: (CGFloat) -> Double = { y in Double(rect.maxY - min(max(y, rect.minY), rect.maxY)) / Double(rect.height) * r - r }
            Color.clear
                .contentShape(Rectangle())
                .overlay(alignment: .topLeading) {
                    if let label {
                        Text(label)
                            .font(Theme.mono(13, .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.65)))
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($active) { _, state, _ in state = true }
                        .onChanged { g in
                            if handle == nil {
                                // Pick the handle nearest the finger.
                                var candidates: [(Handle, CGPoint)] = []
                                switch kind {
                                case .gate:
                                    let gate = Dynamics.Gate(app: app, strip: strip)
                                    candidates.append((.threshold, CGPoint(x: xFor(gate.threshold), y: yFor(gate.output(gate.threshold)))))
                                    candidates.append((.range, CGPoint(x: xFor(gate.threshold), y: yFor(gate.threshold - gate.range))))
                                case .comp:
                                    let comp = Dynamics.Comp(app: app, strip: strip)
                                    candidates.append((.threshold, CGPoint(x: xFor(comp.threshold), y: yFor(comp.output(comp.threshold)))))
                                    // In expander mode the top end doesn't move with the ratio, so there's no ratio handle.
                                    if !comp.expander {
                                        candidates.append((.ratio, CGPoint(x: xFor(0), y: yFor(comp.output(0)))))
                                    }
                                }
                                let start = g.startLocation
                                guard let best = candidates.min(by: { hypot($0.1.x - start.x, $0.1.y - start.y) < hypot($1.1.x - start.x, $1.1.y - start.y) }),
                                      hypot(best.1.x - start.x, best.1.y - start.y) < 60 else { return }
                                // Only grab once the finger actually moves: a tap changes nothing.
                                guard hypot(g.translation.width, g.translation.height) >= 3 else { return }
                                let a = address(best.0, strip)
                                guard app.param(a).isKnown else { return }
                                handle = best.0
                                dragStrip = strip
                                grabOffset = CGSize(width: best.1.x - start.x, height: best.1.y - start.y)
                                startDepth = Double(Specs.gateRange.value(app.param(strip.gatePath("range")).float(or: 1)))
                                app.touch(a, true)
                                app.beginGesture([a])
                            }
                            guard let h = handle, let s = dragStrip else { return }
                            let a = address(h, s)
                            let at = CGPoint(x: g.location.x + grabOffset.width, y: g.location.y + grabOffset.height)
                            switch h {
                            case .threshold:
                                let db = dbAtX(at.x)
                                let spec = kind == .gate ? Specs.gateThreshold : Specs.dynThreshold
                                app.setFloat(a, spec.norm(Float(db)), steps: spec.steps)
                                label = "Threshold " + spec.display(app.param(a).float)
                            case .range:
                                // The bottom of the step: depth is how far below the threshold it sits.
                                // Down makes it deeper, from wherever it started.
                                let dbPerPoint = r / Double(rect.height)
                                let depth = min(max(startDepth + Double(g.translation.height) * dbPerPoint, 3), 60)
                                app.setFloat(a, Specs.gateRange.norm(Float(depth)), steps: Specs.gateRange.steps)
                                label = "Depth " + Specs.gateRange.display(app.param(a).float)
                            case .ratio:
                                // Output at 0 dB in = threshold + (0 - threshold) / ratio.
                                let comp = Dynamics.Comp(app: app, strip: s)
                                let out = min(dbAtY(at.y), -0.01)
                                let rise = out - comp.threshold
                                let ratio = rise <= 0.05 ? 100 : -comp.threshold / rise
                                let values = X32Enums.ratioValues.map(Double.init)
                                let index = values.indices.min(by: { abs(log(values[$0]) - log(max(ratio, 1))) < abs(log(values[$1]) - log(max(ratio, 1))) }) ?? 0
                                if app.param(a).int != index {
                                    app.setInt(a, index)
                                    Haptics.tick()
                                }
                                label = "Ratio " + X32Enums.ratios[index] + ":1"
                            }
                        }
                        .onEnded { _ in finish() }
                )
                .onChange(of: active) { _, isActive in
                    if !isActive { finish() }
                }
                .onChange(of: strip) { _, _ in finish() }
                .onDisappear { finish() }
        }
        .accessibilityHidden(true)
    }
}

private func drawGR(_ ctx: inout GraphicsContext, _ rect: CGRect, gr: Double) {
    // Dotted red track like an LED column, lit from the top by the amount of reduction.
    let segments = max(4, Int(rect.height / 4))
    let lit = Int((min(gr, 24) / 24 * Double(segments)).rounded())
    let segHeight = rect.height / CGFloat(segments)
    for i in 0..<segments {
        let r = CGRect(x: rect.minX, y: rect.minY + CGFloat(i) * segHeight + 0.5, width: rect.width, height: max(1, segHeight - 1))
        ctx.fill(Path(r), with: .color(i < lit ? Theme.mute : Theme.mute.opacity(0.22)))
    }
}

/// The overall EQ response (bands plus low cut) for a strip, in dB at `steps` log-spaced points.
enum EQResponse {
    static func bands(app: AppModel, strip: StripID) -> [EQBandValues] {
        (1...max(strip.eqBandCount, 1)).map { band in
            EQBandValues(
                band: band,
                type: app.param(strip.eqPath(band, "type")).int(or: 2),
                freqNorm: app.param(strip.eqPath(band, "f")).float(or: 0.5),
                gainNorm: app.param(strip.eqPath(band, "g")).float(or: 0.5),
                qNorm: app.param(strip.eqPath(band, "q")).float(or: 0.46)
            )
        }
    }

    static func lowCut(app: AppModel, strip: StripID) -> (Double, Int)? {
        guard strip.hasHighPass, app.param(strip.preampPath("hpon")).bool else { return nil }
        return (Double(Specs.hpf.value(app.param(strip.preampPath("hpf")).float(or: 0.4))), app.param(strip.preampPath("hpslope")).int)
    }

    static func curve(bands: [EQBandValues], eqOn: Bool, lowCut: (Double, Int)?, bandCount: Int, steps: Int) -> [Double] {
        (0..<steps).map { i in
            let f = 20 * pow(1000, Double(i) / Double(steps - 1))
            var db: Double = 0
            if eqOn {
                for b in bands {
                    db += EQMath.bandDB(type: b.type, band: b.band, bandCount: bandCount, freq: Double(b.freq), gain: Double(b.gain), q: Double(b.q), at: f)
                }
            }
            if let lc = lowCut {
                db += EQMath.lowCutDB(freq: lc.0, slope: lc.1, at: f)
            }
            return db
        }
    }
}

/// A small drawing of a strip's EQ curve.
struct EQThumb: View {
    let app: AppModel
    let strip: StripID
    var showsZeroLine = true

    var body: some View {
        let eqOn = app.param(strip.eqOnPath).int(or: 1) != 0
        let lowCut = EQResponse.lowCut(app: app, strip: strip)
        let values = EQResponse.curve(bands: EQResponse.bands(app: app, strip: strip), eqOn: eqOn, lowCut: lowCut, bandCount: strip.eqBandCount, steps: 48)
        let active = eqOn || lowCut != nil
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.graphBack))
            if showsZeroLine {
                ctx.fill(Path(CGRect(x: 0, y: size.height / 2, width: size.width, height: 1)), with: .color(Color.white.opacity(0.08)))
            }
            var curve = Path()
            for (i, db) in values.enumerated() {
                let clamped = max(min(db, 18), -18)
                let p = CGPoint(x: CGFloat(i) / CGFloat(values.count - 1) * size.width, y: size.height / 2 - CGFloat(clamped / 18) * (size.height / 2 - 2))
                if i == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
            }
            ctx.stroke(curve, with: .color(active ? Theme.curve : Theme.tertiary), lineWidth: 1.5)
        }
    }
}
