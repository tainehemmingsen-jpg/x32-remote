import SwiftUI

/// Approximate frequency response of the X32 EQ, for drawing the curve.
enum EQMath {
    static let sampleRate: Double = 48000

    struct Biquad {
        var b0: Double
        var b1: Double
        var b2: Double
        var a0: Double
        var a1: Double
        var a2: Double
    }

    static func peaking(_ f: Double, _ gain: Double, _ q: Double) -> Biquad {
        let w0 = 2 * Double.pi * min(f, sampleRate * 0.45) / sampleRate
        let a = pow(10, gain / 40)
        let alpha = sin(w0) / (2 * max(q, 0.1))
        let c = cos(w0)
        return Biquad(b0: 1 + alpha * a, b1: -2 * c, b2: 1 - alpha * a, a0: 1 + alpha / a, a1: -2 * c, a2: 1 - alpha / a)
    }

    static func lowShelf(_ f: Double, _ gain: Double) -> Biquad {
        let w0 = 2 * Double.pi * min(f, sampleRate * 0.45) / sampleRate
        let a = pow(10, gain / 40)
        let c = cos(w0)
        let alpha = sin(w0) / 2 * sqrt(2.0)
        let t = 2 * sqrt(a) * alpha
        let ap = a + 1
        let am = a - 1
        return Biquad(
            b0: a * (ap - am * c + t),
            b1: 2 * a * (am - ap * c),
            b2: a * (ap - am * c - t),
            a0: ap + am * c + t,
            a1: -2 * (am + ap * c),
            a2: ap + am * c - t
        )
    }

    static func highShelf(_ f: Double, _ gain: Double) -> Biquad {
        let w0 = 2 * Double.pi * min(f, sampleRate * 0.45) / sampleRate
        let a = pow(10, gain / 40)
        let c = cos(w0)
        let alpha = sin(w0) / 2 * sqrt(2.0)
        let t = 2 * sqrt(a) * alpha
        let ap = a + 1
        let am = a - 1
        return Biquad(
            b0: a * (ap + am * c + t),
            b1: -2 * a * (am + ap * c),
            b2: a * (ap + am * c - t),
            a0: ap - am * c + t,
            a1: 2 * (am - ap * c),
            a2: ap - am * c - t
        )
    }

    static func highPass(_ f: Double, _ q: Double) -> Biquad {
        let w0 = 2 * Double.pi * min(f, sampleRate * 0.45) / sampleRate
        let c = cos(w0)
        let alpha = sin(w0) / (2 * q)
        return Biquad(b0: (1 + c) / 2, b1: -(1 + c), b2: (1 + c) / 2, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    static func lowPass(_ f: Double, _ q: Double) -> Biquad {
        let w0 = 2 * Double.pi * min(f, sampleRate * 0.45) / sampleRate
        let c = cos(w0)
        let alpha = sin(w0) / (2 * q)
        return Biquad(b0: (1 - c) / 2, b1: 1 - c, b2: (1 - c) / 2, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    static func magnitudeDB(_ bq: Biquad, at f: Double) -> Double {
        let w = 2 * Double.pi * f / sampleRate
        let c1 = cos(w)
        let s1 = sin(w)
        let c2 = cos(2 * w)
        let s2 = sin(2 * w)
        let nr = bq.b0 + bq.b1 * c1 + bq.b2 * c2
        let ni = bq.b1 * s1 + bq.b2 * s2
        let dr = bq.a0 + bq.a1 * c1 + bq.a2 * c2
        let di = bq.a1 * s1 + bq.a2 * s2
        let num = nr * nr + ni * ni
        let den = dr * dr + di * di
        if num <= 0 || den <= 0 { return -60 }
        return 10 * log10(num / den)
    }

    static func firstOrderHighPassDB(_ fc: Double, at f: Double) -> Double {
        let r = f / fc
        return 20 * log10(r / sqrt(1 + r * r))
    }

    static func firstOrderLowPassDB(_ fc: Double, at f: Double) -> Double {
        let r = f / fc
        return -10 * log10(1 + r * r)
    }

    /// Response of one band in dB at frequency f.
    static func bandDB(type: Int, band: Int, bandCount: Int, freq: Double, gain: Double, q: Double, at f: Double) -> Double {
        switch type {
        case 0:
            return magnitudeDB(highPass(freq, 0.7071), at: f)
        case 1:
            return magnitudeDB(lowShelf(freq, gain), at: f)
        case 2, 3:
            return magnitudeDB(peaking(freq, gain, q), at: f)
        case 4:
            return magnitudeDB(highShelf(freq, gain), at: f)
        case 5:
            return magnitudeDB(lowPass(freq, 0.7071), at: f)
        default:
            // Crossover types on 6-band EQs: band 1 acts as a high-pass, band 6 as a low-pass.
            let highPassBand = band == 1
            let order: Int
            switch type {
            case 6: order = 1
            case 7, 8, 9: order = 2
            case 10: order = 3
            default: order = 4
            }
            var db: Double = 0
            if order % 2 == 1 {
                db += highPassBand ? firstOrderHighPassDB(freq, at: f) : firstOrderLowPassDB(freq, at: f)
            }
            let biquads = order / 2
            for _ in 0..<biquads {
                db += highPassBand ? magnitudeDB(highPass(freq, 0.7071), at: f) : magnitudeDB(lowPass(freq, 0.7071), at: f)
            }
            return db
        }
    }

    /// The channel's preamp low-cut filter.
    static func lowCutDB(freq: Double, slope: Int, at f: Double) -> Double {
        switch slope {
        case 1:
            return firstOrderHighPassDB(freq, at: f) + magnitudeDB(highPass(freq, 1.0), at: f)
        case 2:
            return magnitudeDB(highPass(freq, 0.5412), at: f) + magnitudeDB(highPass(freq, 1.3065), at: f)
        default:
            return magnitudeDB(highPass(freq, 0.7071), at: f)
        }
    }
}

/// Values of one EQ band, normalised as the console stores them.
struct EQBandValues: Equatable {
    var band: Int
    var type: Int
    var freqNorm: Float
    var gainNorm: Float
    var qNorm: Float

    var freq: Float { Specs.eqFreq.value(freqNorm) }
    var gain: Float { Specs.eqGain.value(gainNorm) }
    var q: Float { Specs.eqQ.value(qNorm) }
    var usesGain: Bool { type >= 1 && type <= 4 }
    var usesQ: Bool { type == 2 || type == 3 }
}

enum EQColors {
    static func band(_ b: Int) -> Color {
        switch b {
        case 1: return Color(red: 0.96, green: 0.36, blue: 0.36)
        case 2: return Color(red: 0.98, green: 0.74, blue: 0.24)
        case 3: return Color(red: 0.36, green: 0.84, blue: 0.48)
        case 4: return Color(red: 0.34, green: 0.62, blue: 0.99)
        case 5: return Color(red: 0.78, green: 0.46, blue: 0.96)
        default: return Color(red: 0.30, green: 0.84, blue: 0.90)
        }
    }
}

struct EQPage: View {
    let app: AppModel
    let strip: StripID
    @State private var band = 2

    var body: some View {
        let count = strip.eqBandCount
        let selected = min(max(band, 1), max(count, 1))
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                OnSwitch(app: app, address: strip.eqOnPath, title: "EQ ON", width: 80)
                Spacer(minLength: 10)
                ForEach(1...max(count, 1), id: \.self) { b in
                    Button {
                        band = b
                    } label: {
                        Text("\(b)")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 40, height: 32)
                            .foregroundStyle(b == selected ? Color.black.opacity(0.85) : EQColors.band(b))
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(b == selected ? EQColors.band(b) : Theme.raised)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 0)
            }
            EQGraph(app: app, strip: strip, selectedBand: $band)
                .frame(minHeight: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            BandControls(app: app, strip: strip, band: selected)
        }
        .padding(16)
    }
}

private struct BandControls: View {
    let app: AppModel
    let strip: StripID
    let band: Int

    var body: some View {
        let typeAddress = strip.eqPath(band, "type")
        let type = app.param(typeAddress).int(or: 2)
        let extended = strip.eqBandCount == 6 && (band == 1 || band == 6)
        let options = extended ? X32Enums.eqTypes + X32Enums.busEqExtraTypes : X32Enums.eqTypes
        let tint = EQColors.band(band)
        let usesGain = type >= 1 && type <= 4
        let usesQ = type == 2 || type == 3
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("BAND \(band) TYPE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                EnumMenu(app: app, address: typeAddress, options: options, tint: tint)
                Spacer(minLength: 8)
                Button {
                    app.setFloat(strip.eqPath(band, "g"), 0.5, steps: Specs.eqGain.steps)
                } label: {
                    Text("Flatten band")
                        .barChip()
                }
                .buttonStyle(.plain)
            }
            ControlGrid(minimumWidth: 230) {
                ParamKnob(app: app, address: strip.eqPath(band, "f"), spec: Specs.eqFreq, title: "Freq", tint: tint)
                ParamKnob(app: app, address: strip.eqPath(band, "g"), spec: Specs.eqGain, title: "Gain", bipolar: true, tint: tint, enabled: usesGain, resettable: true)
                ParamKnob(app: app, address: strip.eqPath(band, "q"), spec: Specs.eqQ, title: "Q", tint: tint, enabled: usesQ)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Interactive EQ curve: drag a numbered point to change frequency and gain.
struct EQGraph: View {
    let app: AppModel
    let strip: StripID
    @Binding var selectedBand: Int

    @GestureState private var gestureActive = false
    @State private var dragBand: Int?
    @State private var dragStrip: StripID?
    @State private var dragUsesGain = false
    @State private var dragOrigin: CGPoint = .zero

    private static let dbRange: Double = 18

    private func endDrag() {
        if let b = dragBand, let s = dragStrip {
            app.touch(s.eqPath(b, "f"), false)
            app.touch(s.eqPath(b, "g"), false)
        }
        dragBand = nil
        dragStrip = nil
    }

    var body: some View {
        let count = strip.eqBandCount
        let bands: [EQBandValues] = (1...max(count, 1)).map { b in
            EQBandValues(
                band: b,
                type: app.param(strip.eqPath(b, "type")).int(or: 2),
                freqNorm: app.param(strip.eqPath(b, "f")).float(or: 0.5),
                gainNorm: app.param(strip.eqPath(b, "g")).float(or: 0.5),
                qNorm: app.param(strip.eqPath(b, "q")).float(or: 0.46)
            )
        }
        let eqOn = app.param(strip.eqOnPath).int(or: 1) != 0
        let lowCutOn = strip.hasHighPass && app.param(strip.preampPath("hpon")).bool
        let lowCutFreq = Double(Specs.hpf.value(app.param(strip.preampPath("hpf")).float(or: 0.4)))
        let lowCutSlope = app.param(strip.preampPath("hpslope")).int
        let selected = selectedBand
        GeometryReader { geo in
            let size = geo.size
            Canvas { ctx, sz in
                EQGraph.drawGrid(&ctx, sz)
                EQGraph.drawCurves(&ctx, sz, bands: bands, eqOn: eqOn, selected: selected, lowCut: lowCutOn ? (lowCutFreq, lowCutSlope) : nil, bandCount: count)
                EQGraph.drawHandles(&ctx, sz, bands: bands, eqOn: eqOn, selected: selected)
            }
            .background(Theme.panel)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($gestureActive) { _, state, _ in
                        state = true
                    }
                    .onChanged { g in
                        if dragBand == nil {
                            guard let hit = EQGraph.nearestBand(to: g.startLocation, bands: bands, size: size) else { return }
                            dragBand = hit.band
                            dragStrip = strip
                            dragUsesGain = hit.usesGain
                            dragOrigin = EQGraph.point(for: hit, size: size)
                            selectedBand = hit.band
                            app.touch(strip.eqPath(hit.band, "f"), true)
                            app.touch(strip.eqPath(hit.band, "g"), true)
                        }
                        // Keep editing the channel the drag started on, even if the page moved on.
                        guard let b = dragBand, let s = dragStrip else { return }
                        let x = min(max(dragOrigin.x + g.translation.width, 0), size.width)
                        let y = min(max(dragOrigin.y + g.translation.height, 0), size.height)
                        let freqNorm = Float(x / max(size.width, 1))
                        app.setFloat(s.eqPath(b, "f"), freqNorm, steps: Specs.eqFreq.steps)
                        if dragUsesGain {
                            let db = (Double(size.height) / 2 - Double(y)) / (Double(size.height) / 2) * EQGraph.dbRange
                            let clamped = Float(min(max(db, -15), 15))
                            app.setFloat(s.eqPath(b, "g"), Specs.eqGain.norm(clamped), steps: Specs.eqGain.steps)
                        }
                    }
                    .onEnded { _ in
                        endDrag()
                    }
            )
            .onDisappear {
                endDrag()
            }
            .onChange(of: gestureActive) { _, active in
                // Also runs when the system cancels the gesture (onEnded doesn't).
                if !active {
                    endDrag()
                }
            }
        }
    }

    // MARK: Geometry

    static func xFor(freqNorm: Float, width: CGFloat) -> CGFloat {
        CGFloat(freqNorm) * width
    }

    static func yFor(db: Double, height: CGFloat) -> CGFloat {
        let half = Double(height) / 2
        return CGFloat(half - db / dbRange * half)
    }

    static func point(for band: EQBandValues, size: CGSize) -> CGPoint {
        let x = xFor(freqNorm: band.freqNorm, width: size.width)
        let y = band.usesGain ? yFor(db: Double(band.gain), height: size.height) : size.height / 2
        return CGPoint(x: x, y: y)
    }

    static func nearestBand(to p: CGPoint, bands: [EQBandValues], size: CGSize) -> EQBandValues? {
        var best: EQBandValues?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for b in bands {
            let q = point(for: b, size: size)
            let d = hypot(q.x - p.x, q.y - p.y)
            if d < bestDistance {
                bestDistance = d
                best = b
            }
        }
        return bestDistance <= 70 ? best : nil
    }

    // MARK: Drawing

    static func drawGrid(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let freqs: [Double] = [50, 100, 200, 500, 1000, 2000, 5000, 10000]
        for f in freqs {
            let x = CGFloat(log(f / 20) / log(1000)) * size.width
            var p = Path()
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(p, with: .color(Color.white.opacity(0.07)), lineWidth: 1)
            let label = f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
            ctx.draw(Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(Color.white.opacity(0.35)), at: CGPoint(x: x + 3, y: size.height - 8), anchor: .leading)
        }
        for db in [-12.0, -6.0, 0.0, 6.0, 12.0] {
            let y = yFor(db: db, height: size.height)
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(p, with: .color(Color.white.opacity(db == 0 ? 0.18 : 0.07)), lineWidth: 1)
            let label = db > 0 ? "+\(Int(db))" : "\(Int(db))"
            ctx.draw(Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(Color.white.opacity(0.35)), at: CGPoint(x: 4, y: y - 7), anchor: .leading)
        }
    }

    static func drawCurves(_ ctx: inout GraphicsContext, _ size: CGSize, bands: [EQBandValues], eqOn: Bool, selected: Int, lowCut: (Double, Int)?, bandCount: Int) {
        let steps = 160
        var total = [Double](repeating: 0, count: steps)
        var selectedCurve = [Double](repeating: 0, count: steps)
        for i in 0..<steps {
            let norm = Double(i) / Double(steps - 1)
            let f = 20 * pow(1000, norm)
            var sum: Double = 0
            if eqOn {
                for b in bands {
                    let db = EQMath.bandDB(type: b.type, band: b.band, bandCount: bandCount, freq: Double(b.freq), gain: Double(b.gain), q: Double(b.q), at: f)
                    sum += db
                    if b.band == selected {
                        selectedCurve[i] = db
                    }
                }
            }
            if let lc = lowCut {
                sum += EQMath.lowCutDB(freq: lc.0, slope: lc.1, at: f)
            }
            total[i] = sum
        }

        func path(_ values: [Double], closeToZero: Bool) -> Path {
            var p = Path()
            let zeroY = yFor(db: 0, height: size.height)
            for i in 0..<values.count {
                let x = CGFloat(Double(i) / Double(values.count - 1)) * size.width
                let y = yFor(db: max(min(values[i], dbRange + 6), -dbRange - 6), height: size.height)
                if i == 0 {
                    if closeToZero {
                        p.move(to: CGPoint(x: x, y: zeroY))
                        p.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        p.move(to: CGPoint(x: x, y: y))
                    }
                } else {
                    p.addLine(to: CGPoint(x: x, y: y))
                }
            }
            if closeToZero {
                p.addLine(to: CGPoint(x: size.width, y: zeroY))
                p.closeSubpath()
            }
            return p
        }

        if eqOn {
            ctx.fill(path(selectedCurve, closeToZero: true), with: .color(EQColors.band(selected).opacity(0.18)))
        }
        ctx.fill(path(total, closeToZero: true), with: .color(Theme.accent.opacity(eqOn ? 0.10 : 0.04)))
        ctx.stroke(path(total, closeToZero: false), with: .color(eqOn ? Theme.accent : Theme.tertiary), lineWidth: 2.5)
    }

    static func drawHandles(_ ctx: inout GraphicsContext, _ size: CGSize, bands: [EQBandValues], eqOn: Bool, selected: Int) {
        for b in bands {
            let p = point(for: b, size: size)
            let isSelected = b.band == selected
            let r: CGFloat = isSelected ? 15 : 12
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            let color = EQColors.band(b.band).opacity(eqOn ? 1 : 0.45)
            ctx.fill(Path(ellipseIn: rect), with: .color(isSelected ? color : Color.black.opacity(0.6)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2)
            let label = Text("\(b.band)")
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(isSelected ? Color.black.opacity(0.85) : color)
            ctx.draw(label, at: p, anchor: .center)
        }
    }
}
