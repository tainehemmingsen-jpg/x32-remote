import SwiftUI

/// A 31-band graphic EQ in an effects slot (GEQ / TEQ, stereo or dual).
struct GraphicEQPanel: View {
    let app: AppModel
    let slot: Int
    let sides: Int
    @State private var side = 0
    @State private var confirmFlat = false

    var body: some View {
        let shownSide = min(side, sides - 1)
        let code = Effects.typeCode(slot: slot, type: app.param(Effects.typePath(slot)).int) ?? "GEQ"
        RackUnit(title: Effects.typeName(slot: slot, type: app.param(Effects.typePath(slot)).int), code: code, look: FXFamily.eq.look) {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if sides == 2 {
                    ForEach(0..<2, id: \.self) { s in
                        Button {
                            side = s
                        } label: {
                            Text(s == 0 ? "A" : "B")
                                .frame(minWidth: 30)
                                .barChip(active: shownSide == s)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(s == 0 ? "Side A" : "Side B")
                        .accessibilityAddTraits(shownSide == s ? .isSelected : [])
                    }
                }
                Spacer()
                Button {
                    confirmFlat = true
                } label: {
                    Text("Flatten").barChip()
                }
                .buttonStyle(.plain)
                .confirmationDialog("Set all 31 bands\(sides == 2 ? " of side \(shownSide == 0 ? "A" : "B")" : "") to 0 dB?",
                                    isPresented: $confirmFlat, titleVisibility: .visible) {
                    Button("Flatten", role: .destructive) {
                        let changes = (1...31).map { (Effects.parPath(slot, Effects.geqParNumber(side: shownSide, band: $0)), OSCArg.float(0.5)) }
                        app.applyBatch(changes, label: "FX \(slot) GEQ flatten")
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
            GraphicEQGraph(app: app, slot: slot, side: shownSide)
                .id(shownSide)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            ParamKnob(app: app, address: Effects.parPath(slot, Effects.geqMasterNumber(side: shownSide)),
                      spec: Effects.geqSpec, title: sides == 2 ? "Level \(shownSide == 0 ? "A" : "B")" : "Level", bipolar: true)
            Text("Drag a band up or down to adjust it. Sweep sideways to draw a curve. Double-tap a band to reset it.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
        }
        }
    }
}

/// The band bars and curve. Touches are relative on the band you land on (so a tap changes
/// nothing), and absolute once the finger sweeps across to other bands.
struct GraphicEQGraph: View {
    let app: AppModel
    let slot: Int
    let side: Int

    @GestureState private var gestureActive = false
    /// Addresses changed by the current gesture (one undo step at the end).
    @State private var touched: [String] = []
    @State private var startBand: Int?
    @State private var startNorm: Float = 0.5
    @State private var lastBand: Int?
    @State private var lastNorm: Float = 0.5
    @State private var drawing = false
    @State private var dragSlot = 0
    @State private var dragSide = 0
    @State private var shownBand: Int?
    @State private var lastTap: (band: Int, time: Date)?
    @State private var readoutToken = 0
    /// Where the gesture really started (it may begin a little after the finger lands).
    @State private var origin: CGPoint = .zero

    private static let labelHeight: CGFloat = 18
    private static let dbRange: Float = 15

    private func address(_ band: Int, slot: Int? = nil, side: Int? = nil) -> String {
        Effects.parPath(slot ?? self.slot, Effects.geqParNumber(side: side ?? self.side, band: band + 1))
    }

    var body: some View {
        let norms: [Float] = (0..<31).map { app.param(address($0)).float(or: 0.5) }
        let knownBands: [Bool] = (0..<31).map { app.param(address($0)).isKnown }
        GeometryReader { geo in
            let size = geo.size
            let graphHeight = max(size.height - GraphicEQGraph.labelHeight, 1)
            let column = size.width / 31
            Canvas { ctx, sz in
                GraphicEQGraph.draw(&ctx, sz, norms: norms, known: knownBands, highlighted: shownBand)
            }
            .accessibilityHidden(true)
            .background(Theme.graphBack)
            .overlay(alignment: .topLeading) {
                if let b = shownBand, knownBands[b] {
                    Text("\(Effects.geqBandLabel(b)) Hz   \(Effects.geqSpec.display(norms[b]))")
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.55)))
                        .padding(6)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($gestureActive) { _, state, _ in state = true }
                    .onChanged { g in
                        let band = min(max(Int(g.location.x / max(column, 1)), 0), 30)
                        if startBand == nil {
                            // Never start from a value that hasn't been read from the desk.
                            guard knownBands[band] else { return }
                            readoutToken += 1
                            origin = g.location
                            startBand = band
                            lastBand = band
                            dragSlot = slot
                            dragSide = side
                            startNorm = norms[band]
                            lastNorm = norms[band]
                            drawing = false
                            shownBand = band
                            return
                        }
                        guard let start = startBand else { return }
                        let absolute = Float(1 - min(max(g.location.y, 0), graphHeight) / graphHeight)
                        let moved = CGSize(width: g.location.x - origin.x, height: g.location.y - origin.y)
                        // Only a clear sideways move starts drawing, so a tap or an up/down drag
                        // near a column edge never touches the neighbouring band.
                        if !drawing && band != start && abs(moved.width) > max(column * 0.75, 10) {
                            drawing = true
                        }
                        if drawing {
                            // Fill in any bands the finger skipped over.
                            let from = lastBand ?? band
                            if band == from {
                                set(band, absolute)
                            } else {
                                let step = band > from ? 1 : -1
                                for b in stride(from: from + step, through: band, by: step) {
                                    let t = Float(abs(b - from)) / Float(abs(band - from))
                                    set(b, lastNorm + (absolute - lastNorm) * t)
                                }
                            }
                            lastNorm = absolute
                        } else {
                            // A small dead zone, so a tap never nudges the band.
                            guard abs(moved.height) >= 4 || !touched.isEmpty else { return }
                            let sensitivity: Float = app.fineMode ? 0.25 : 1
                            let delta = Float(-moved.height / graphHeight) * sensitivity
                            let v = min(max(startNorm + delta, 0), 1)
                            set(start, v)
                            lastNorm = v
                        }
                        lastBand = drawing ? band : start
                        shownBand = drawing ? band : start
                    }
                    .onEnded { g in
                        let tapped = abs(g.location.x - origin.x) < 4 && abs(g.location.y - origin.y) < 4
                        if tapped, !drawing, let b = startBand {
                            if let last = lastTap, last.band == b, Date().timeIntervalSince(last.time) < 0.35 {
                                set(b, 0.5)
                                lastTap = nil
                            } else {
                                lastTap = (b, Date())
                            }
                        }
                        finish()
                    }
            )
            .onChange(of: gestureActive) { _, active in
                if !active { finish() }
            }
            .onDisappear { finish() }
            .background {
                // VoiceOver: one adjustable element per band (touches go to the graph on top).
                HStack(spacing: 0) {
                    ForEach(0..<31, id: \.self) { b in
                        Color.clear
                            .paramAccessibility(app: app, title: "\(Effects.geqBandLabel(b)) hertz", address: address(b), spec: Effects.geqSpec, reset: 0.5)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Graphic EQ")
    }

    private func set(_ band: Int, _ norm: Float) {
        let a = address(band, slot: dragSlot, side: dragSide)
        guard app.param(a).isKnown else { return }
        if !touched.contains(a) {
            touched.append(a)
            app.touch(a, true)
            app.beginGesture([a])
        }
        app.setFloat(a, norm, steps: Effects.geqSpec.steps)
    }

    private func finish() {
        guard startBand != nil || !touched.isEmpty else { return }
        for a in touched { app.touch(a, false) }
        if !touched.isEmpty {
            app.endGesture(touched, label: "FX \(dragSlot) GEQ")
        }
        touched = []
        startBand = nil
        lastBand = nil
        drawing = false
        // Leave the readout up for a moment after the finger lifts.
        readoutToken += 1
        let token = readoutToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if readoutToken == token { shownBand = nil }
        }
    }

    static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, norms: [Float], known: [Bool], highlighted: Int?) {
        let h = size.height - labelHeight
        let column = size.width / 31
        func y(_ db: Float) -> CGFloat { CGFloat(0.5 - db / (2 * dbRange)) * h }

        // Grid
        for db: Float in [-12, -6, 0, 6, 12] {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y(db)))
            line.addLine(to: CGPoint(x: size.width, y: y(db)))
            ctx.stroke(line, with: .color(db == 0 ? Theme.lineStrong : Theme.graphGrid), lineWidth: 1)
            let label = db > 0 ? "+\(Int(db))" : "\(Int(db))"
            ctx.draw(Text(label).font(.system(size: 9)).foregroundStyle(Theme.tertiary),
                     at: CGPoint(x: 3, y: y(db) - 7), anchor: .leading)
        }
        // Column separators and labels
        // All labels when there's room, every other one, or every third (31.5, 63, 125…) on phones.
        let labelEvery = column >= 26 ? 1 : (column >= 17 ? 2 : 3)
        for i in 0..<31 {
            let x0 = CGFloat(i) * column
            if i > 0 {
                var sep = Path()
                sep.move(to: CGPoint(x: x0, y: 0))
                sep.addLine(to: CGPoint(x: x0, y: h))
                ctx.stroke(sep, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
            }
            if labelEvery == 1 || (labelEvery == 2 && i % 2 == 0) || (labelEvery == 3 && i % 3 == 2) {
                ctx.draw(Text(Effects.geqBandLabel(i)).font(.system(size: 9)).foregroundStyle(Theme.secondary),
                         at: CGPoint(x: x0 + column / 2, y: h + labelHeight / 2))
            }
        }
        // Bars from the 0 dB line, with a bright cap (only for bands read from the desk).
        var points: [CGPoint] = []
        for (i, n) in norms.enumerated() where known[i] {
            let db = (n - 0.5) * 2 * dbRange
            let x0 = CGFloat(i) * column
            let top = y(db)
            let zero = y(0)
            let lit = i == highlighted
            // A fader slot per band, with a chrome cap at the band's gain (like a hardware graphic EQ).
            let slotRect = CGRect(x: x0 + column / 2 - 1.5, y: y(dbRange), width: 3, height: y(-dbRange) - y(dbRange))
            ctx.fill(Path(roundedRect: slotRect, cornerRadius: 1.5), with: .color(Color.black.opacity(0.85)))
            let bar = CGRect(x: x0 + column / 2 - 1.5, y: min(top, zero), width: 3, height: max(abs(zero - top), 1))
            ctx.fill(Path(bar), with: .color(Theme.accent.opacity(lit ? 0.9 : 0.6)))
            let capH = min(max(column * 0.45, 8), 14)
            let cap = CGRect(x: x0 + column * 0.14, y: top - capH / 2, width: column * 0.72, height: capH)
            ctx.fill(Path(roundedRect: cap.offsetBy(dx: 0, dy: 1.5), cornerRadius: 2), with: .color(Color.black.opacity(0.5)))
            ctx.fill(Path(roundedRect: cap, cornerRadius: 2), with: .linearGradient(
                Gradient(colors: lit ? [Color.white, Color(white: 0.8)] : [Color(white: 0.9), Color(white: 0.6), Color(white: 0.78)]),
                startPoint: CGPoint(x: cap.midX, y: cap.minY), endPoint: CGPoint(x: cap.midX, y: cap.maxY)))
            ctx.fill(Path(CGRect(x: cap.minX + 2, y: cap.midY - 0.75, width: cap.width - 4, height: 1.5)), with: .color(lit ? Theme.accent : Color.black.opacity(0.7)))
            points.append(CGPoint(x: x0 + column / 2, y: top))
        }
        // Smooth curve through the bands
        var curve = Path()
        if points.count == norms.count, let first = points.first {
            curve.move(to: first)
            for i in 1..<points.count {
                let p0 = points[i - 1], p1 = points[i]
                let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                curve.addQuadCurve(to: mid, control: p0)
                if i == points.count - 1 { curve.addLine(to: p1) }
            }
        }
        ctx.stroke(curve, with: .color(Theme.curve), lineWidth: 2)
    }
}
