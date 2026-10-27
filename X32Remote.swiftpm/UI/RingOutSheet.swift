import SwiftUI

/// Ring out wedges and the PA: pick an output, turn it up until it starts to ring, and the
/// frequencies that are feeding back appear with a Cut button that notches them out of that
/// output's EQ. Tap again to cut deeper.
struct RingOutSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var output: StripID = .mainLR
    @State private var detector = FeedbackDetector()
    @State private var claim = UUID()
    /// Bands cut in this session, so the list can say so.
    @State private var cut: [Int: String] = [:]

    private var outputs: [StripID] { [StripID.mainLR] + StripID.all(.bus) + [StripID.monoC] }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = geo.size.width >= 700
                VStack(spacing: 10) {
                    OutputPicker(app: app, outputs: outputs, selection: $output)
                    if wide {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 10) {
                                spectrum
                                    .frame(maxHeight: .infinity)
                                fader
                            }
                            .frame(maxWidth: .infinity)
                            sidePanel
                                .frame(width: 340)
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                spectrum.frame(height: 220)
                                fader
                                sidePanel
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(Theme.background)
            .navigationTitle("Ring out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                ToastView(app: app)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            app.loadDetail(output)
            app.claimRTA(claim, strip: output, always: true)
        }
        .onDisappear {
            app.releaseRTA(claim)
        }
        .onChange(of: output) { _, new in
            detector.reset()
            cut = [:]
            app.loadDetail(new)
            app.claimRTA(claim, strip: new, always: true)
        }
        .onChange(of: app.meters.rta.levels) { _, levels in
            guard !app.meters.rta.idle else { return }
            detector.ingest(levels)
        }
    }

    // MARK: Parts

    private var spectrum: some View {
        ZStack(alignment: .topLeading) {
            RingSpectrum(levels: app.meters.rta.levels, candidates: detector.candidates,
                         notches: RingOut.notches(output, value: { app.store.value($0) }))
            if app.meters.rta.idle || app.meters.rta.levels.isEmpty {
                AnalyserNotice(app: app)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// The output's own fader, so it can be pushed up into feedback from here.
    private var fader: some View {
        let address = output.faderPath
        let p = app.param(address)
        return HStack(spacing: 12) {
            Text(app.stripTitle(output))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
            ParamHFader(app: app, address: address)
                .frame(height: 44)
            Text(p.isKnown ? X32Math.formatFader(p.float) : "—")
                .font(Theme.mono(14))
                .foregroundStyle(Theme.text)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.panel))
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bring \(app.stripTitle(output)) up slowly until it just starts to ring, then tap Cut on the frequency that appears. Pull the level back a little, push again, and repeat.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Ringing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                if !detector.candidates.isEmpty {
                    Button("Clear") { detector.reset(); cut = [:] }
                        .font(.system(size: 13))
                }
            }
            if detector.candidates.isEmpty {
                Text("Nothing ringing yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            ForEach(detector.candidates) { c in
                CandidateRow(candidate: c, cutText: cut[c.band]) {
                    if let what = app.notch(output, frequency: c.frequency) {
                        cut[c.band] = what
                        Haptics.click()
                    }
                } dismiss: {
                    detector.dismiss(c.band)
                }
            }
            let notches = RingOut.notches(output, value: { app.store.value($0) })
            if !notches.isEmpty {
                Text("Notches on \(app.stripTitle(output))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 6)
                ForEach(notches) { n in
                    HStack {
                        Text(RingOut.label(n.hz))
                            .font(Theme.mono(14))
                            .foregroundStyle(Theme.text)
                        Text(String(format: "%.0f dB", n.gain))
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.mute)
                        Text("band \(n.band)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiary)
                        Spacer()
                        Button("Remove") { app.removeNotch(output, band: n.band) }
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.panel))
    }
}

/// A horizontal fader bound to a desk parameter (fader law), with undo.
private struct ParamHFader: View {
    let app: AppModel
    let address: String
    @State private var drag = DragTarget()

    var body: some View {
        HFader(value: app.param(address).float, fine: app.fineMode,
               onChange: { v in app.dragSet(address, drag, v, steps: 1023) },
               onTouch: { began in if began { app.beginDrag(address, drag) } else { app.endDrag(drag) } })
    }
}

private struct OutputPicker: View {
    let app: AppModel
    let outputs: [StripID]
    @Binding var selection: StripID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(outputs) { s in
                    let name = app.param(s.namePath).string
                    let color = s.kind == .main || s.kind == .mono ? Theme.text : Theme.scribble(app.param(s.colorPath).int)
                    Button {
                        selection = s
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(name.isEmpty ? s.footLabel : name)
                                .font(.system(size: 14, weight: selection == s ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(Capsule().fill(selection == s ? Theme.raised2 : Theme.raised))
                        .overlay(Capsule().strokeBorder(selection == s ? Theme.on : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CandidateRow: View {
    let candidate: FeedbackDetector.Candidate
    let cutText: String?
    let cut: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(candidate.live ? Theme.mute : Theme.tertiary)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(RingOut.label(Float(candidate.frequency)))
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                Text(cutText ?? (candidate.live ? String(format: "Ringing, %.0f dB above", candidate.prominence) : "Stopped"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 34, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ignore")
            LitButton(title: cutText == nil ? "Cut" : "Cut more", isOn: true, color: Theme.mute, height: 40, fontSize: 14, action: cut)
                .frame(width: 92)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
    }
}

/// The analyser with ringing frequencies marked in red and existing notches in blue.
private struct RingSpectrum: View {
    let levels: [Float]
    let candidates: [FeedbackDetector.Candidate]
    let notches: [RingOut.Notch]

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.graphBack))
            let top: Float = 0, bottom: Float = -90
            func x(_ hz: Double) -> CGFloat { CGFloat(log(hz / 20) / log(1000)) * size.width }
            func y(_ db: Float) -> CGFloat { CGFloat((top - min(max(db, bottom), top)) / (top - bottom)) * size.height }
            // Grid.
            for hz in [50.0, 100, 200, 500, 1000, 2000, 5000, 10000] {
                ctx.fill(Path(CGRect(x: x(hz), y: 0, width: 0.5, height: size.height)), with: .color(Theme.graphGrid))
                let label = hz >= 1000 ? "\(Int(hz / 1000))k" : "\(Int(hz))"
                ctx.draw(Text(label).font(.system(size: 10)).foregroundColor(Theme.tertiary), at: CGPoint(x: x(hz) + 3, y: size.height - 4), anchor: .bottomLeading)
            }
            for db in stride(from: -80, through: -10, by: 10) {
                ctx.fill(Path(CGRect(x: 0, y: y(Float(db)), width: size.width, height: 0.5)), with: .color(Theme.graphGrid.opacity(0.5)))
            }
            // Notches already on the EQ.
            for n in notches {
                let nx = x(Double(n.hz))
                ctx.fill(Path(CGRect(x: nx - 1, y: 0, width: 2, height: size.height)), with: .color(Theme.accent.opacity(0.7)))
            }
            // Spectrum.
            if levels.count > 1 {
                var area = Path()
                area.move(to: CGPoint(x: 0, y: size.height))
                for (i, db) in levels.enumerated() {
                    area.addLine(to: CGPoint(x: x(RTA.frequency(i)), y: y(db)))
                }
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(Gradient(colors: [Theme.on.opacity(0.55), Theme.on.opacity(0.08)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            // Ringing frequencies.
            for c in candidates {
                let cx = x(c.frequency)
                let cy = y(c.level)
                ctx.fill(Path(CGRect(x: cx - 1.5, y: cy, width: 3, height: size.height - cy)), with: .color(Theme.mute.opacity(c.live ? 0.9 : 0.4)))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 6, y: cy - 6, width: 12, height: 12)), with: .color(c.live ? Theme.mute : Theme.tertiary))
                ctx.draw(Text(RingOut.label(Float(c.frequency))).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text),
                         at: CGPoint(x: min(max(cx, 30), size.width - 30), y: max(cy - 10, 10)), anchor: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Shown while the desk's analyser isn't sending yet.
private struct AnalyserNotice: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Text(app.meters.rta.idle ? "The desk's analyser isn't running." : "Waiting for the desk's analyser…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
            if app.meters.rta.idle {
                Button("Start it") { app.wakeRTA() }
                    .buttonStyle(.bordered)
                    .disabled(app.rtaWaking)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.65)))
        .padding(10)
    }
}
