import SwiftUI

// MARK: - Input

struct InputPage: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 2) {
                        Cell {
                            PreampControls(app: app, strip: strip)
                                .padding(14)
                        }
                        if strip.hasHighPass {
                            Cell {
                                LowCutControls(app: app, strip: strip)
                                    .padding(14)
                            }
                        }
                    }
                    .frame(minWidth: 620)
                    VStack(spacing: 2) {
                        Cell {
                            PreampControls(app: app, strip: strip)
                                .padding(14)
                        }
                        if strip.hasHighPass {
                            Cell {
                                LowCutControls(app: app, strip: strip)
                                    .padding(14)
                            }
                        }
                    }
                }
                if strip.hasDelay {
                    Cell {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Delay")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondary)
                            HStack(spacing: 14) {
                                OnSwitch(app: app, address: strip.delayPath("on"), title: "Delay", width: 100)
                                ParamKnob(app: app, address: strip.delayPath("time"), spec: Specs.delay, title: "Time", enabled: app.param(strip.delayPath("on")).bool)
                            }
                            Text(delayHint(app.param(strip.delayPath("time")).float(or: 0)))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.tertiary)
                        }
                        .padding(14)
                    }
                }
                Cell {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Input level")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                        InputMeterRow(app: app, strip: strip)
                        SourceNote(app: app, strip: strip)
                    }
                    .padding(14)
                }
            }
            .padding(2)
        }
    }
}

/// Distance sound travels in the delay time, to line a channel up with a mic further away.
private func delayHint(_ norm: Float) -> String {
    let ms = Specs.delay.value(norm)
    let metres = ms * 0.343
    return String(format: "≈ %.1f m of sound travel", metres)
}

private struct PreampControls: View {
    let app: AppModel
    let strip: StripID
    @State private var confirmPhantom = false

    var body: some View {
        let haIndex = strip.headampIndexPath.map { app.param($0).int(or: -1) } ?? -1
        let hasHeadamp = haIndex >= 0 && haIndex < 128
        let phantomOn = hasHeadamp && app.param(StripID.headampPhantomPath(haIndex)).bool
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Preamp")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                if hasHeadamp {
                    Text(StripSource.headampLabel(haIndex))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                }
            }
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
            HStack(spacing: 10) {
                if hasHeadamp {
                    LitButton(title: "+48V", isOn: phantomOn, color: Theme.mute, height: 44, fontSize: 13, offColor: Theme.phantomOff) {
                        confirmPhantom = true
                    }
                    .frame(width: 100)
                }
                if strip.hasPolarity {
                    OnSwitch(app: app, address: strip.preampPath("invert"), title: "Ø Invert", width: 100)
                }
            }
        }
        .phantomConfirm(isPresented: $confirmPhantom, on: phantomOn) {
            if hasHeadamp {
                app.setBool(StripID.headampPhantomPath(haIndex), !phantomOn)
            }
        }
    }
}

private struct LowCutControls: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Low cut")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 10) {
                OnSwitch(app: app, address: strip.preampPath("hpon"), title: "Lowcut", width: 100)
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

/// Every send of the channel as its own fader, with tap point and on/off underneath.
struct SendsPage: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        GeometryReader { geo in
            let count = max(strip.sendCount, 1)
            let columnWidth = max(64, (geo.size.width - 4) / CGFloat(count))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(1...count, id: \.self) { n in
                        SendColumn(app: app, strip: strip, n: n)
                            .frame(width: columnWidth - 1)
                    }
                }
                .frame(height: max(0, geo.size.height - 4))
                .padding(2)
            }
            .scrollDisabled(columnWidth * CGFloat(count) <= geo.size.width)
        }
        .background(Color.black)
    }
}

private struct SendColumn: View {
    let app: AppModel
    let strip: StripID
    let n: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let target = strip.sendsFeedMatrix ? StripID(.matrix, n) : StripID(.bus, n)
        let name = app.param(target.namePath).string
        let colorIndex = app.param(target.colorPath).int
        let levelAddress = strip.sendLevelPath(n)
        let onAddress = strip.sendOnPath(n)
        let on = app.param(onAddress).int(or: 1) != 0
        let tap = app.param(strip.sendTypePath(n))
        VStack(spacing: 4) {
            ScribbleView(name: name, colorIndex: colorIndex, placeholder: target.footLabel, height: 30, fontSize: 11)
                .onTapGesture {
                    // Put this mix's sends on the faders.
                    guard target.kind == .bus else { return }
                    app.selectSendsBus(n)
                    dismiss()
                }
            FaderReadout(app: app, address: levelAddress)
            ParamFader(app: app, address: levelAddress, steps: 160, editTitle: "\(app.stripTitle(strip)) → \(name.isEmpty ? target.footLabel : name)")
                .opacity(on ? 1 : 0.5)
            Text(target.footLabel)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.opacity(0.8))
            if n % 2 == 1 || strip.sendsFeedMatrix {
                TapMenu(app: app, address: strip.sendTypePath(n), current: tap.isKnown ? tap.int : -1)
            } else {
                Text(tap.isKnown && tap.int >= 0 && tap.int < X32Enums.sendTaps.count ? X32Enums.sendTaps[tap.int] : "")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .frame(height: 36)
            }
            LitButton(title: on ? "ON" : "OFF", isOn: on, color: Theme.on, height: 36, fontSize: 12, style: .outline) {
                app.setBool(onAddress, !on)
            }
        }
        .padding(4)
        .background(Theme.panel)
    }
}

/// Where the send is taken from (pre/post fader…). Shared by each odd/even pair on the X32.
private struct TapMenu: View {
    let app: AppModel
    let address: String
    let current: Int

    var body: some View {
        Menu {
            ForEach(0..<X32Enums.sendTaps.count, id: \.self) { i in
                Button {
                    app.setInt(address, i)
                } label: {
                    if i == current {
                        Label(X32Enums.sendTaps[i], systemImage: "checkmark")
                    } else {
                        Text(X32Enums.sendTaps[i])
                    }
                }
            }
        } label: {
            Text(current >= 0 && current < X32Enums.sendTaps.count ? X32Enums.sendTaps[current] : "—")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.on.opacity(0.7), lineWidth: 1))
        }
    }
}

// MARK: - Setup

struct SetupPage: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Panel(title: "Name") {
                    NameEditor(app: app, strip: strip)
                }
                Panel(title: "Colour") {
                    ColorPicker32(app: app, address: strip.colorPath)
                }
                if strip.kind == .channel {
                    Panel(title: "Input source") {
                        SourcePicker(app: app, strip: strip)
                    }
                }
                if strip.hasInsert {
                    Panel(title: "Insert") {
                        InsertControls(app: app, strip: strip)
                    }
                }
                if strip.linkPath != nil, let partner = strip.linkPartner {
                    Panel(title: "Stereo link") {
                        LinkSwitch(app: app, strip: strip, partner: partner)
                    }
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
                if let group = Automix.groupPath(strip), let weight = Automix.weightPath(strip) {
                    Panel(title: "Automix") {
                        AutomixControls(app: app, groupPath: group, weightPath: weight)
                    }
                }
            }
            .padding(16)
        }
    }
}

/// Automix group and weight for a channel, plus the two group switches.
private struct AutomixControls: View {
    let app: AppModel
    let groupPath: String
    let weightPath: String

    var body: some View {
        let group = app.param(groupPath).int(or: 0)
        VStack(alignment: .leading, spacing: 10) {
            LabeledChoice(app: app, title: "Group", address: groupPath, options: Automix.groupNames)
            ParamKnob(app: app, address: weightPath, spec: Automix.weightSpec, title: "Weight", bipolar: true, enabled: group > 0)
            HStack(spacing: 10) {
                OnSwitch(app: app, address: Automix.enablePath("X"), title: "Automix X on", width: 120)
                OnSwitch(app: app, address: Automix.enablePath("Y"), title: "Automix Y on", width: 120)
                Spacer()
            }
            Text("Channels in a group share one gain budget: whoever is loudest comes through and the others come down. Weight favours a channel within its group.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
        }
    }
}

/// Patch an effect (or an aux loop) into the strip.
private struct InsertControls: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                OnSwitch(app: app, address: strip.insertPath("on"), title: "Insert", width: 84)
                Spacer()
                EnumMenu(app: app, address: strip.insertPath("sel"), options: X32Enums.insertSelections)
            }
            LabeledChoice(app: app, title: "Position", address: strip.insertPath("pos"), options: X32Enums.prePost)
        }
    }
}

/// Which input feeds a channel (local inputs, aux, USB, FX returns, buses).
private struct SourcePicker: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let p = app.param(strip.sourcePath)
        HStack(spacing: 12) {
            Menu {
                ForEach(0...64, id: \.self) { v in
                    Button {
                        app.setSource(strip, v)
                    } label: {
                        if p.isKnown && p.int == v {
                            Label(X32Enums.sourceName(v), systemImage: "checkmark")
                        } else {
                            Text(X32Enums.sourceName(v))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(p.isKnown ? X32Enums.sourceName(p.int) : "—")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                }
                .barChip()
            }
            Text("Changes what this channel hears. Undo puts it back.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
        }
    }
}

/// Links an odd/even pair into a stereo channel.
private struct LinkSwitch: View {
    let app: AppModel
    let strip: StripID
    let partner: StripID
    @State private var confirm = false

    var body: some View {
        let first = strip.index < partner.index ? strip : partner
        let second = strip.index < partner.index ? partner : strip
        let linked = app.isLinked(strip)
        HStack(spacing: 12) {
            LitButton(title: linked ? "Linked" : "Link", isOn: linked, height: 40, fontSize: 13, style: .outline) {
                confirm = true
            }
            .frame(width: 100)
            Text("\(first.footLabel) + \(second.footLabel)")
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
        }
        .confirmationDialog(linked ? "Unlink \(first.footLabel) and \(second.footLabel)?" : "Link \(first.footLabel) and \(second.footLabel)?", isPresented: $confirm, titleVisibility: .visible) {
            Button(linked ? "Unlink" : "Link", role: .destructive) {
                if let path = strip.linkPath {
                    app.setBool(path, !linked)
                    app.reloadAfterLink(first, second)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(linked
                 ? "They'll go back to being two separate channels."
                 : "\(second.footLabel) takes on \(first.footLabel)'s linked settings, and from then on they move together.")
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
