import SwiftUI

// MARK: - Input

struct InputPage: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        Panel(title: "Preamp") {
                            PreampControls(app: app, strip: strip)
                        }
                        if strip.hasHighPass {
                            Panel(title: "Low cut") {
                                LowCutControls(app: app, strip: strip)
                            }
                        }
                    }
                    VStack(spacing: 14) {
                        Panel(title: "Preamp") {
                            PreampControls(app: app, strip: strip)
                        }
                        if strip.hasHighPass {
                            Panel(title: "Low cut") {
                                LowCutControls(app: app, strip: strip)
                            }
                        }
                    }
                }
                Panel(title: "Input level") {
                    InputMeterRow(app: app, strip: strip)
                }
                SourceNote(app: app, strip: strip)
            }
            .padding(16)
        }
    }
}

private struct PreampControls: View {
    let app: AppModel
    let strip: StripID
    @State private var confirmPhantom = false

    var body: some View {
        let haIndex = strip.headampIndexPath.map { app.param($0).int(or: -1) } ?? -1
        let hasHeadamp = haIndex >= 0 && haIndex < 128
        let phantomOn = hasHeadamp && app.param(StripID.headampPhantomPath(haIndex)).bool
        VStack(alignment: .leading, spacing: 12) {
            if hasHeadamp {
                ParamKnob(app: app, address: StripID.headampGainPath(haIndex), spec: Specs.headampGain, title: "Gain")
            } else {
                Text("This input isn't fed by a local or AES50 preamp, so gain is set at the source.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
            if strip.hasTrim {
                ParamKnob(app: app, address: strip.preampPath("trim"), spec: Specs.trim, title: "Trim", bipolar: true, resettable: true)
            }
            HStack(alignment: .top, spacing: 18) {
                if hasHeadamp {
                    PhantomSwitch(app: app, address: StripID.headampPhantomPath(haIndex), confirm: $confirmPhantom)
                }
                if strip.hasPolarity {
                    VStack(spacing: 6) {
                        Text("POLARITY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.secondary)
                        OnSwitch(app: app, address: strip.preampPath("invert"), title: "Ø", color: Theme.accent, width: 56)
                    }
                }
            }
        }
        .alert(phantomOn ? "Turn off 48V phantom power?" : "Turn on 48V phantom power?", isPresented: $confirmPhantom) {
            Button(phantomOn ? "Turn off 48V" : "Turn on 48V", role: .destructive) {
                if hasHeadamp {
                    app.setBool(StripID.headampPhantomPath(haIndex), !phantomOn)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(phantomOn
                 ? "Condenser mics and DI boxes on this input will go silent."
                 : "Phantom power can damage ribbon mics and some line-level gear. Pull the channel down first.")
        }
    }
}

private struct PhantomSwitch: View {
    let app: AppModel
    let address: String
    @Binding var confirm: Bool

    var body: some View {
        let on = app.param(address).bool
        VStack(spacing: 6) {
            Text("PHANTOM")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.secondary)
            LitButton(title: "48V", isOn: on, color: Theme.mute, height: 32) {
                confirm = true
            }
            .frame(width: 64)
        }
    }
}

private struct LowCutControls: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                OnSwitch(app: app, address: strip.preampPath("hpon"), title: "LOW CUT", width: 96)
                Text("SLOPE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                EnumMenu(app: app, address: strip.preampPath("hpslope"), options: X32Enums.hpfSlopes.map { $0 + " dB/oct" })
            }
            ParamKnob(app: app, address: strip.preampPath("hpf"), spec: Specs.hpf, title: "Frequency", enabled: app.param(strip.preampPath("hpon")).bool)
        }
    }
}

private struct InputMeterRow: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let meter = app.meters.meter(strip)
        HStack(spacing: 12) {
            HorizontalLevel(meter: meter)
                .frame(height: 16)
            LevelText(meter: meter)
                .frame(width: 60, alignment: .trailing)
        }
    }
}

struct HorizontalLevel: View {
    let meter: MeterLevel

    var body: some View {
        let level = meter.level
        Canvas { ctx, size in
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4), with: .color(Color.black.opacity(0.55)))
            let pos = MeterScale.position(level)
            let yellow = MeterScale.position(-12)
            let red = MeterScale.position(-3)
            let segments: [(CGFloat, CGFloat, Color)] = [(0, yellow, Theme.meterLow), (yellow, red, Theme.meterMid), (red, 1, Theme.meterHigh)]
            for segment in segments {
                let a = min(pos, segment.0)
                let b = min(pos, segment.1)
                if b > a {
                    ctx.fill(Path(CGRect(x: size.width * a, y: 0, width: size.width * (b - a), height: size.height)), with: .color(segment.2))
                }
            }
            for db in [-48, -36, -24, -12, -6, 0] {
                let x = size.width * MeterScale.position(Float(db))
                ctx.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.25)))
            }
        }
    }
}

private struct LevelText: View {
    let meter: MeterLevel

    var body: some View {
        let level = meter.level
        Text(level <= -89 ? "-∞" : String(format: "%.0f dB", level))
            .font(Theme.mono(13))
            .foregroundStyle(Theme.secondary)
    }
}

private struct SourceNote: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let source = app.param(strip.sourcePath)
        HStack {
            Text("Source")
                .foregroundStyle(Theme.secondary)
            Text(source.isKnown ? X32Enums.sourceName(source.int) : "—")
                .foregroundStyle(Theme.text)
            Spacer()
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 4)
    }
}

// MARK: - Sends

struct SendsPage: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if strip.sendCount > 0 {
                    ForEach(1...strip.sendCount, id: \.self) { n in
                        SendRow(app: app, strip: strip, n: n)
                    }
                }
                Text(strip.sendsFeedMatrix ? "Sends from this bus to the six matrix outputs." : "Tap a bus name to put its sends on the faders.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            .padding(16)
        }
    }
}

private struct SendRow: View {
    let app: AppModel
    let strip: StripID
    let n: Int
    @Environment(\.dismiss) private var dismiss
    @State private var drag = DragTarget()

    var body: some View {
        let target = strip.sendsFeedMatrix ? StripID(.matrix, n) : StripID(.bus, n)
        let name = app.param(target.namePath).string
        let color = Theme.scribble(app.param(target.colorPath).int)
        let levelAddress = strip.sendLevelPath(n)
        let onAddress = strip.sendOnPath(n)
        let level = app.param(levelAddress)
        let on = app.param(onAddress).int(or: 1) != 0
        let tap = app.param(strip.sendTypePath(n))
        let nameButton = Button {
            guard target.kind == .bus else { return }
            app.selectSendsBus(n)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 6, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.shortLabel.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                    Text(name.isEmpty ? target.shortLabel : name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        let fader = HFader(
            value: level.float,
            tint: color,
            hapticAtUnity: app.settings.hapticAtUnity,
            fine: app.fineMode,
            onChange: { v in app.dragSet(levelAddress, drag, v, steps: 160) },
            onTouch: { began in
                if began { app.beginDrag(levelAddress, drag) } else { app.endDrag(drag) }
            }
        )
        .frame(height: 40)
        .opacity(on ? 1 : 0.45)
        let readout = Text(level.isKnown ? X32Math.formatFader(level.float) : "—")
            .font(Theme.mono(13, .semibold))
            .frame(width: 52, alignment: .trailing)
        let tapText = (tap.isKnown && tap.int >= 0 && tap.int < X32Enums.sendTaps.count) ? X32Enums.sendTaps[tap.int] : ""
        let tapLabel = Text(tapText)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.secondary)
            .frame(width: 44)
        let onButton = LitButton(title: on ? "ON" : "OFF", isOn: on, color: Theme.on, height: 34) {
            app.setBool(onAddress, !on)
        }
        .frame(width: 56)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                nameButton.frame(width: 140, alignment: .leading)
                fader.frame(minWidth: 180)
                readout
                tapLabel
                onButton
            }
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    nameButton
                    Spacer(minLength: 4)
                    tapLabel
                    readout
                    onButton
                }
                fader
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
    }
}

// MARK: - Setup

struct SetupPage: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Panel(title: "Name") {
                    NameEditor(app: app, strip: strip)
                }
                Panel(title: "Colour") {
                    ColorPicker32(app: app, address: strip.colorPath)
                }
                if let dca = strip.dcaGroupsPath {
                    Panel(title: "DCA groups") {
                        BitToggles(app: app, address: dca, count: 8, prefix: "DCA", color: Theme.accent)
                    }
                }
                if let mute = strip.muteGroupsPath {
                    Panel(title: "Mute groups") {
                        BitToggles(app: app, address: mute, count: 6, prefix: "MG", color: Theme.mute)
                    }
                }
                if strip.lrAssignPath != nil || strip.monoAssignPath != nil {
                    Panel(title: "Main outputs") {
                        MainAssign(app: app, strip: strip)
                    }
                }
            }
            .padding(16)
        }
    }
}

private struct NameEditor: View {
    let app: AppModel
    let strip: StripID
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let current = app.param(strip.namePath).string
        HStack(spacing: 10) {
            TextField(strip.defaultName, text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.done)
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised))
                .onSubmit {
                    commit()
                }
                .onChange(of: text) { _, newValue in
                    if newValue.count > 12 {
                        text = String(newValue.prefix(12))
                    }
                }
            Button("Save") {
                commit()
                focused = false
            }
            .buttonStyle(.borderedProminent)
            .disabled(text == current)
        }
        .onAppear {
            text = current
        }
        .onChange(of: current) { _, newValue in
            if !focused {
                text = newValue
            }
        }
        .onChange(of: strip) { _, _ in
            text = app.param(strip.namePath).string
        }
    }

    private func commit() {
        let trimmed = String(text.trimmingCharacters(in: .whitespaces).prefix(12))
        app.setString(strip.namePath, trimmed)
    }
}

/// The 16 X32 scribble colours (8 solid, 8 inverted).
struct ColorPicker32: View {
    let app: AppModel
    let address: String

    var body: some View {
        let current = app.param(address).int
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<8, id: \.self) { col in
                        let index = row * 8 + col
                        Button {
                            app.setInt(address, index)
                        } label: {
                            ColorSwatch(index: index, selected: index == current)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(colorTitle(current))
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
        }
    }

    private func colorTitle(_ index: Int) -> String {
        let base = X32Enums.colorNames[((index % 8) + 8) % 8]
        return index >= 8 ? base + " (inverted)" : base
    }
}

private struct ColorSwatch: View {
    let index: Int
    let selected: Bool

    var body: some View {
        let color = Theme.scribble(index)
        let inverted = Theme.isInverted(index)
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(inverted ? Theme.raised : color)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(inverted ? color : Color.clear, lineWidth: 2)
            )
            .overlay(
                Text("Aa")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(inverted ? color : Color.black.opacity(0.7))
            )
            .frame(width: 40, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Theme.text : Color.clear, lineWidth: 2)
                    .padding(-3)
            )
    }
}

/// Toggles for each bit of a bitmask parameter (DCA and mute-group assignment).
struct BitToggles: View {
    let app: AppModel
    let address: String
    let count: Int
    let prefix: String
    let color: Color

    var body: some View {
        let param = app.param(address)
        let mask = param.int
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { bit in
                let on = (mask >> bit) & 1 == 1
                LitButton(title: "\(prefix) \(bit + 1)", isOn: on, color: color, height: 34, fontSize: 11) {
                    // Writing a mask we haven't read would silently drop the channel from its other groups.
                    guard param.isKnown else { return }
                    let newMask = on ? (mask & ~(1 << bit)) : (mask | (1 << bit))
                    app.setInt(address, newMask)
                }
                .frame(minWidth: 52)
            }
        }
    }
}

private struct MainAssign: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .top, spacing: 22) {
            if let lr = strip.lrAssignPath {
                VStack(spacing: 6) {
                    Text("TO MAIN LR")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                    OnSwitch(app: app, address: lr, title: "LR", color: Theme.accent)
                }
            }
            if let mono = strip.monoAssignPath {
                VStack(spacing: 6) {
                    Text("TO MONO")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                    OnSwitch(app: app, address: mono, title: "M/C", color: Theme.accent)
                }
            }
          }
            if let level = strip.monoLevelPath {
                ParamKnob(app: app, address: level, spec: Specs.send, title: "Mono level")
                    .frame(maxWidth: 420)
            }
        }
    }
}
