import SwiftUI

// Mini editors that open over the mixer, like a DiGiCo: tap a strip's gain, gate, EQ or
// compressor and change it right there, with the faders still in view. Everything here is the
// same controls as the channel page, just gathered for one job.

/// The line across the top of each mini editor: whose strip, which section, its on/off, and the
/// way to the full channel page.
private struct EditorHeader: View {
    let app: AppModel
    let strip: StripID
    let title: String
    let tab: DetailTab
    var onAddress: String? = nil
    let close: () -> Void

    var body: some View {
        let name = app.param(strip.namePath).string
        let color = Theme.scribble(app.param(strip.colorPath).int)
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 5, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(name.isEmpty ? strip.footLabel : name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(name.isEmpty ? title : "\(strip.footLabel) · \(title)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            if let onAddress {
                let on = app.param(onAddress).bool
                LitButton(title: on ? "On" : "Bypassed", isOn: on, color: Theme.on, height: 36, fontSize: 13, style: .outline) {
                    app.setBool(onAddress, !on)
                    Haptics.click()
                }
                .frame(width: 96)
            }
            Button {
                close()
                // Let the popover go first, or the full-screen page can't present.
                DispatchQueue.main.async { app.openDetail(strip, tab: tab) }
            } label: {
                Label("Channel", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .medium))
                    .barChip()
            }
            .buttonStyle(ConsoleKeyStyle())
            .accessibilityLabel("Open the full channel page")
        }
    }
}

/// Gain, 48V, low cut and polarity: the input section of a strip.
struct InputEditor: View {
    let app: AppModel
    let strip: StripID
    let close: () -> Void
    @State private var confirmPhantom = false

    var body: some View {
        let ha = strip.headampIndexPath.map { app.param($0).int(or: -1) } ?? -1
        let hasHeadamp = ha >= 0 && ha < 128
        let phantomOn = hasHeadamp && app.param(StripID.headampPhantomPath(ha)).bool
        VStack(alignment: .leading, spacing: 14) {
            EditorHeader(app: app, strip: strip, title: "Input", tab: .input, close: close)
            if hasHeadamp {
                StepRow(app: app, address: StripID.headampGainPath(ha), spec: Specs.headampGain, title: "Gain", step: 1)
            }
            if strip.hasTrim && !hasHeadamp {
                StepRow(app: app, address: strip.preampPath("trim"), spec: Specs.trim, title: "Trim", step: 0.5, bipolar: true)
            }
            // How hot the input is right now, so gain can be set by eye.
            HStack(spacing: 10) {
                Text("Input")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 44, alignment: .leading)
                InputLevelBar(meter: app.meters.meter(strip))
                    .frame(height: 14)
            }
            HStack(spacing: 8) {
                if hasHeadamp {
                    LitButton(title: "+48V", isOn: phantomOn, color: Theme.mute, height: 40, fontSize: 13, offColor: Theme.phantomOff) {
                        confirmPhantom = true
                    }
                    .frame(width: 84)
                }
                if strip.hasPolarity {
                    OnSwitch(app: app, address: strip.preampPath("invert"), title: "Ø Invert", width: 96)
                }
                if hasHeadamp {
                    GainWizardButton(app: app, strip: strip, height: 40)
                }
                Spacer(minLength: 0)
            }
            if strip.hasHighPass {
                let lowCutOn = app.param(strip.preampPath("hpon")).bool
                HStack(spacing: 8) {
                    OnSwitch(app: app, address: strip.preampPath("hpon"), title: "Low cut", width: 96)
                    ParamKnob(app: app, address: strip.preampPath("hpf"), spec: Specs.hpf, title: "Frequency", enabled: lowCutOn)
                }
            }
        }
        .padding(16)
        .frame(width: 440)
        .phantomConfirm(isPresented: $confirmPhantom, on: phantomOn) {
            if hasHeadamp { app.setBool(StripID.headampPhantomPath(ha), !phantomOn) }
        }
    }
}

/// A slider with − and + keys either side for exact steps (gain in 1 dB, trim in 0.5 dB).
private struct StepRow: View {
    let app: AppModel
    let address: String
    let spec: ParamSpec
    let title: String
    /// In the parameter's own units (dB).
    let step: Float
    var bipolar = false

    var body: some View {
        HStack(spacing: 8) {
            StepKey(symbol: "minus") { nudge(-step) }
            ParamKnob(app: app, address: address, spec: spec, title: title, bipolar: bipolar, resettable: bipolar)
            StepKey(symbol: "plus") { nudge(step) }
        }
    }

    private func nudge(_ delta: Float) {
        let p = app.param(address)
        guard p.isKnown else { app.stillReading(); return }
        let target = spec.value(p.float) + delta
        app.setFloat(address, min(max(spec.norm(target), 0), 1), steps: spec.steps)
        Haptics.click()
    }
}

private struct StepKey: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.raised2))
            .contentShape(Rectangle())
            .modifier(PressAction(action: action))
            .accessibilityLabel(symbol == "plus" ? "Up" : "Down")
    }
}

/// The input level as a horizontal bar with the -18 to -6 dBFS sweet spot marked.
private struct InputLevelBar: View {
    let meter: MeterLevel

    var body: some View {
        let db = Double(max(meter.input, -60))
        Canvas { ctx, size in
            func x(_ v: Double) -> CGFloat { CGFloat((v + 60) / 60) * size.width }
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3), with: .color(Color.black))
            ctx.fill(Path(CGRect(x: x(-18), y: 0, width: x(-6) - x(-18), height: size.height)), with: .color(Theme.on.opacity(0.15)))
            let lit = CGRect(x: 0, y: 2, width: x(db), height: size.height - 4)
            let color = db > -3 ? Theme.mute : (db > -12 ? Theme.solo : Theme.on)
            ctx.fill(Path(roundedRect: lit, cornerRadius: 2), with: .color(color))
        }
        .accessibilityLabel("Input level")
        .accessibilityValue(String(format: "%.0f dB", db))
    }
}

/// Gate: the curve (drag its handles) and the settings people actually change.
struct GateEditor: View {
    let app: AppModel
    let strip: StripID
    let close: () -> Void

    var body: some View {
        let on = app.param(strip.gatePath("on")).bool
        VStack(alignment: .leading, spacing: 12) {
            EditorHeader(app: app, strip: strip, title: "Gate", tab: .gate, onAddress: strip.gatePath("on"), close: close)
            HStack(alignment: .top, spacing: 14) {
                GateGraph(app: app, strip: strip, detailed: true, interactive: true)
                    .frame(width: 250, height: 250)
                    .background(Theme.graphBack)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(spacing: 10) {
                    EnumMenu(app: app, address: strip.gatePath("mode"), options: X32Enums.gateModes)
                    ParamKnob(app: app, address: strip.gatePath("thr"), spec: Specs.gateThreshold, title: "Threshold", enabled: on)
                    ParamKnob(app: app, address: strip.gatePath("range"), spec: Specs.gateRange, title: "Range", enabled: on)
                    ParamKnob(app: app, address: strip.gatePath("attack"), spec: Specs.attack, title: "Attack", enabled: on)
                    ParamKnob(app: app, address: strip.gatePath("hold"), spec: Specs.hold, title: "Hold", enabled: on)
                    ParamKnob(app: app, address: strip.gatePath("release"), spec: Specs.release, title: "Release", enabled: on)
                }
                .frame(width: 250)
            }
        }
        .padding(16)
    }
}

/// Compressor: the curve and the main settings.
struct CompEditor: View {
    let app: AppModel
    let strip: StripID
    let close: () -> Void

    var body: some View {
        let on = app.param(strip.dynPath("on")).bool
        VStack(alignment: .leading, spacing: 12) {
            EditorHeader(app: app, strip: strip, title: "Compressor", tab: .comp, onAddress: strip.dynPath("on"), close: close)
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    CompGraph(app: app, strip: strip, detailed: true, interactive: true)
                        .frame(width: 250, height: 250)
                        .background(Theme.graphBack)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    ReductionMeter(meter: app.meters.meter(strip))
                        .frame(width: 250, height: 22)
                }
                VStack(spacing: 10) {
                    ParamKnob(app: app, address: strip.dynPath("thr"), spec: Specs.dynThreshold, title: "Threshold", enabled: on)
                    EnumKnob(app: app, address: strip.dynPath("ratio"), options: X32Enums.ratios, title: "Ratio", suffix: ":1", enabled: on)
                    ParamKnob(app: app, address: strip.dynPath("attack"), spec: Specs.attack, title: "Attack", enabled: on)
                    ParamKnob(app: app, address: strip.dynPath("release"), spec: Specs.release, title: "Release", enabled: on)
                    ParamKnob(app: app, address: strip.dynPath("knee"), spec: Specs.knee, title: "Knee", enabled: on)
                    ParamKnob(app: app, address: strip.dynPath("mgain"), spec: Specs.makeup, title: "Makeup", enabled: on)
                }
                .frame(width: 250)
            }
        }
        .padding(16)
    }
}

/// EQ: the full EQ page (curve with draggable bands, band keys, low cut), sized for a popover.
struct EQEditor: View {
    let app: AppModel
    let strip: StripID
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The EQ page has its own On key on the left.
            EditorHeader(app: app, strip: strip, title: "EQ", tab: .eq, close: close)
            EQPage(app: app, strip: strip, wide: true)
                .frame(width: 720, height: 400)
        }
        .padding(16)
    }
}

/// Which mini editor a strip has open.
enum StripEditor: String, Identifiable {
    case input, gate, eq, comp
    var id: String { rawValue }
}

extension View {
    /// Shows a strip's mini editor in a popover anchored to this view.
    func stripEditor(_ editor: Binding<StripEditor?>, app: AppModel, strip: StripID) -> some View {
        popover(item: editor, arrowEdge: .top) { which in
            Group {
                switch which {
                case .input: InputEditor(app: app, strip: strip) { editor.wrappedValue = nil }
                case .gate: GateEditor(app: app, strip: strip) { editor.wrappedValue = nil }
                case .eq: EQEditor(app: app, strip: strip) { editor.wrappedValue = nil }
                case .comp: CompEditor(app: app, strip: strip) { editor.wrappedValue = nil }
                }
            }
            .background(Theme.panel)
            .presentationCompactAdaptation(.sheet)
            .preferredColorScheme(.dark)
            .onAppear { app.loadDetail(strip) }
        }
    }
}
