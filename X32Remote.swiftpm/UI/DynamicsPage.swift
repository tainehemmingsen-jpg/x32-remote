import SwiftUI

struct DynamicsPage: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if strip.hasGate {
                    GatePanel(app: app, strip: strip)
                }
                if strip.hasDynamics {
                    CompressorPanel(app: app, strip: strip)
                }
            }
            .padding(16)
        }
    }
}

private struct GatePanel: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let on = app.param(strip.gatePath("on")).bool
        let tint = Theme.on
        Panel {
            HStack(spacing: 12) {
                Text("GATE")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.text)
                OnSwitch(app: app, address: strip.gatePath("on"), title: on ? "ON" : "OFF", color: tint)
                EnumMenu(app: app, address: strip.gatePath("mode"), options: X32Enums.gateModes, tint: tint)
                Spacer(minLength: 8)
                ReductionMeter(meter: app.meters.meter(strip), gate: true)
                    .frame(maxWidth: 220)
            }
            ControlGrid {
                ParamKnob(app: app, address: strip.gatePath("thr"), spec: Specs.gateThreshold, title: "Threshold", tint: tint, enabled: on)
                ParamKnob(app: app, address: strip.gatePath("range"), spec: Specs.gateRange, title: "Range", tint: tint, enabled: on)
                ParamKnob(app: app, address: strip.gatePath("attack"), spec: Specs.attack, title: "Attack", tint: tint, enabled: on)
                ParamKnob(app: app, address: strip.gatePath("hold"), spec: Specs.hold, title: "Hold", tint: tint, enabled: on)
                ParamKnob(app: app, address: strip.gatePath("release"), spec: Specs.release, title: "Release", tint: tint, enabled: on)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct CompressorPanel: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let on = app.param(strip.dynPath("on")).bool
        let tint = Theme.accent
        Panel {
            HStack(spacing: 12) {
                Text("COMPRESSOR")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.text)
                OnSwitch(app: app, address: strip.dynPath("on"), title: on ? "ON" : "OFF", color: tint)
                Spacer()
                ReductionMeter(meter: app.meters.meter(strip))
                    .frame(maxWidth: 220)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    EnumMenu(app: app, address: strip.dynPath("mode"), options: X32Enums.dynModes, tint: tint)
                    EnumMenu(app: app, address: strip.dynPath("det"), options: X32Enums.dynDetect, tint: tint)
                    EnumMenu(app: app, address: strip.dynPath("env"), options: X32Enums.dynEnvelope, tint: tint)
                    OnSwitch(app: app, address: strip.dynPath("auto"), title: "AUTO", color: tint, width: 70)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    TransferCurve(app: app, strip: strip)
                        .frame(width: 150, height: 150)
                    CompressorBars(app: app, strip: strip, tint: tint, on: on)
                        .frame(minWidth: 520)
                }
                VStack(alignment: .leading, spacing: 12) {
                    TransferCurve(app: app, strip: strip)
                        .frame(width: 150, height: 150)
                        .frame(maxWidth: .infinity)
                    CompressorBars(app: app, strip: strip, tint: tint, on: on)
                }
            }
        }
    }
}

private struct CompressorBars: View {
    let app: AppModel
    let strip: StripID
    let tint: Color
    let on: Bool

    var body: some View {
        ControlGrid {
            ParamKnob(app: app, address: strip.dynPath("thr"), spec: Specs.dynThreshold, title: "Threshold", tint: tint, enabled: on)
            EnumKnob(app: app, address: strip.dynPath("ratio"), options: X32Enums.ratios, title: "Ratio", suffix: ":1", tint: tint, enabled: on)
            ParamKnob(app: app, address: strip.dynPath("knee"), spec: Specs.knee, title: "Knee", tint: tint, enabled: on)
            ParamKnob(app: app, address: strip.dynPath("mgain"), spec: Specs.makeup, title: "Gain", tint: tint, enabled: on)
            ParamKnob(app: app, address: strip.dynPath("attack"), spec: Specs.attack, title: "Attack", tint: tint, enabled: on)
            ParamKnob(app: app, address: strip.dynPath("hold"), spec: Specs.hold, title: "Hold", tint: tint, enabled: on)
            ParamKnob(app: app, address: strip.dynPath("release"), spec: Specs.release, title: "Release", tint: tint, enabled: on)
            ParamKnob(app: app, address: strip.dynPath("mix"), spec: Specs.dynMix, title: "Mix", tint: tint, enabled: on)
        }
        .padding(.vertical, 4)
    }
}

/// Input/output curve of the compressor, with the current input level as a dot.
private struct TransferCurve: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let on = app.param(strip.dynPath("on")).bool
        let threshold = Double(Specs.dynThreshold.value(app.param(strip.dynPath("thr")).float(or: 1)))
        let ratioIndex = min(max(app.param(strip.dynPath("ratio")).int(or: 3), 0), X32Enums.ratioValues.count - 1)
        let ratio = Double(X32Enums.ratioValues[ratioIndex])
        let knee = Double(Specs.knee.value(app.param(strip.dynPath("knee")).float(or: 0.2))) * 2
        let expander = app.param(strip.dynPath("mode")).int == 1
        let meter = app.meters.meter(strip)
        let level = Double(meter.level)
        Canvas { ctx, size in
            let range: Double = 60
            func x(_ db: Double) -> CGFloat { CGFloat((db + range) / range) * size.width }
            func y(_ db: Double) -> CGFloat { size.height - CGFloat((db + range) / range) * size.height }
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

            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10), with: .color(Color.black.opacity(0.35)))
            for db in stride(from: -50.0, through: -10.0, by: 10.0) {
                var grid = Path()
                grid.move(to: CGPoint(x: x(db), y: 0))
                grid.addLine(to: CGPoint(x: x(db), y: size.height))
                grid.move(to: CGPoint(x: 0, y: y(db)))
                grid.addLine(to: CGPoint(x: size.width, y: y(db)))
                ctx.stroke(grid, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
            }
            var unity = Path()
            unity.move(to: CGPoint(x: x(-range), y: y(-range)))
            unity.addLine(to: CGPoint(x: x(0), y: y(0)))
            ctx.stroke(unity, with: .color(Color.white.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            var curve = Path()
            var input = -range
            curve.move(to: CGPoint(x: x(input), y: y(output(input))))
            while input <= 0 {
                curve.addLine(to: CGPoint(x: x(input), y: y(max(-range, output(input)))))
                input += 0.5
            }
            ctx.stroke(curve, with: .color(on ? Theme.accent : Theme.tertiary), lineWidth: 2.5)

            if level > -range {
                let dot = CGRect(x: x(level) - 5, y: y(max(-range, output(level))) - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: dot), with: .color(Theme.text))
            }
        }
    }
}
