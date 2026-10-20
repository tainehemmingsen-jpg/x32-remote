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
                let c = CGPoint(x: x(level), y: y(output(level)))
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

    var body: some View {
        let gate = Dynamics.Gate(app: app, strip: strip)
        let meter = app.meters.meter(strip)
        let gr = Double(meter.gateReduction)
        let level = Double(meter.level)
        Canvas { ctx, size in
            let grWidth: CGFloat = detailed ? 6 : 4
            let rect = CGRect(x: 0, y: 0, width: size.width - grWidth - 2, height: size.height)
            Dynamics.drawTransfer(&ctx, rect, range: 80, on: gate.on, detailed: detailed, handles: [gate.threshold], level: detailed ? level : nil) { gate.output($0) }
            if detailed {
                // Second handle at the bottom of the step (threshold minus range).
                let x = rect.minX + CGFloat((gate.threshold + 80) / 80) * rect.width
                let yb = rect.maxY - CGFloat((max(-80, gate.threshold - gate.range) + 80) / 80) * rect.height
                ctx.stroke(Path(ellipseIn: CGRect(x: x - 9, y: yb - 9, width: 18, height: 18)), with: .color(gate.on ? Theme.curve : Theme.tertiary), lineWidth: 2.5)
            }
            drawGR(&ctx, CGRect(x: size.width - grWidth, y: 0, width: grWidth, height: size.height), gr: gate.on ? gr : 0)
        }
    }
}

/// Compressor curve for a strip.
struct CompGraph: View {
    let app: AppModel
    let strip: StripID
    var detailed = false

    var body: some View {
        let comp = Dynamics.Comp(app: app, strip: strip)
        let meter = app.meters.meter(strip)
        let gr = Double(meter.dynReduction)
        let level = Double(meter.level)
        Canvas { ctx, size in
            let grWidth: CGFloat = detailed ? 6 : 4
            let rect = CGRect(x: 0, y: 0, width: size.width - grWidth - 2, height: size.height)
            Dynamics.drawTransfer(&ctx, rect, range: 60, on: comp.on, detailed: detailed, handles: [comp.threshold, 0], level: detailed ? level : nil) { comp.output($0) }
            drawGR(&ctx, CGRect(x: size.width - grWidth, y: 0, width: grWidth, height: size.height), gr: comp.on ? gr : 0)
        }
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
