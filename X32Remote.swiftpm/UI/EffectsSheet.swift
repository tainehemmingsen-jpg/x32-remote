import SwiftUI

/// "FX" in the top bar.
struct FXIcon: View {
    let app: AppModel

    var body: some View {
        Button {
            app.loadEffects()
            app.sheet = .effects
        } label: {
            Text("FX")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 46, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Effects")
    }
}

/// The eight effects slots: what's in each, what feeds it, its return level, and (for the
/// reverbs, delays and modulation effects in slots 1-4) every parameter.
struct EffectsSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var slot: Int

    init(app: AppModel) {
        self.app = app
        _slot = State(initialValue: app.effectsSlot)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = geo.size.width >= 700
                if wide {
                    HStack(spacing: 2) {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(Array(Effects.slots), id: \.self) { s in
                                    SlotTile(app: app, slot: s, selected: s == slot) { slot = s }
                                }
                            }
                            .padding(6)
                        }
                        .frame(width: 210)
                        .background(Theme.background)
                        SlotDetail(app: app, slot: slot) { dismiss() }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(Effects.slots), id: \.self) { s in
                                    SlotTile(app: app, slot: s, selected: s == slot) { slot = s }
                                        .frame(width: 150)
                                }
                            }
                            .padding(6)
                        }
                        SlotDetail(app: app, slot: slot) { dismiss() }
                    }
                }
            }
            .background(Theme.background)
            .overlay(alignment: .bottom) {
                ToastView(app: app)
            }
            .overlay {
                ValueEditorOverlay(app: app)
            }
            .onDisappear {
                // Don't leave an editor open for the mixer to show after the sheet closes.
                app.valueEditor = nil
                // Reopen on the same slot next time.
                app.effectsSlot = slot
            }
            // Sliders and the graphic EQ are dragged downwards a lot; close with Done instead.
            .interactiveDismissDisabled()
            .navigationTitle("Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct SlotTile: View {
    let app: AppModel
    let slot: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let type = app.param(Effects.typePath(slot))
        let source = app.param(Effects.sourcePath(slot))
        let sourceText = slot <= 4 ? (source.isKnown ? "from \(Effects.sourceName(source.int))" : " ") : "insert"
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text("FX \(slot)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                Text(type.isKnown ? Effects.typeName(slot: slot, type: type.int) : "—")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(sourceText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(10)
            .padding(.leading, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                // The effect family's colour, like the faceplate.
                if type.isKnown, let code = Effects.typeCode(slot: slot, type: type.int) {
                    Rectangle().fill(FXFamily.of(code).look.accent).frame(width: 5)
                }
            }
            .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Theme.raised2 : Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? Theme.on : Color.white.opacity(0.07), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SlotDetail: View {
    let app: AppModel
    let slot: Int
    let close: () -> Void
    @State private var pendingType: Int?
    @State private var showPicker = false

    var body: some View {
        let typeParam = app.param(Effects.typePath(slot))
        let type = typeParam.int(or: -1)
        let source = app.param(Effects.sourcePath(slot))
        let params = Effects.parameters(slot: slot, type: type)
        let geqSides = Effects.graphicEQSides(slot: slot, type: type)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FX \(slot)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                        Text(typeParam.isKnown ? Effects.typeName(slot: slot, type: type) : "Reading…")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.text)
                    }
                    Spacer()
                    Button {
                        showPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.grid.2x2")
                            Text("Effects")
                        }
                        .barChip()
                    }
                    .buttonStyle(.plain)
                    .disabled(!typeParam.isKnown)
                    .accessibilityLabel("Choose an effect")
                }
                if slot <= 4 && source.isKnown {
                    SourceRow(app: app, sourceValue: source.int, close: close)
                }
                ForEach(Effects.returnStrips(slot: slot)) { strip in
                    ReturnRow(app: app, strip: strip)
                }
                InsertedOnRow(app: app, slot: slot, close: close)
                if let geqSides {
                    GraphicEQPanel(app: app, slot: slot, sides: geqSides)
                        .id(slot)
                        .padding(.top, 4)
                } else if let params {
                    FXFaceplate(app: app, slot: slot, type: type, params: params)
                        .id("\(slot)-\(type)")
                        .padding(.top, 4)
                } else if typeParam.isKnown {
                    Text("This effect's settings are on the desk's Effects screen; you can still change the type above.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(16)
        }
        .background(Theme.panel)
        .sheet(isPresented: $showPicker) {
            EffectPicker(slot: slot, current: type) { chosen in
                // Ask after the picker has closed (a dialog can't show over a closing sheet).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { pendingType = chosen }
            }
        }
        .task(id: "\(slot)-\(type)") {
            // Read this effect's parameters whenever it's shown (graphic EQs use up to 64).
            if type >= 0 { app.loadEffectParameters(slot: slot, type: type) }
        }
        .confirmationDialog(
            pendingType.map { "Change FX \(slot) to \(Effects.typeName(slot: slot, type: $0))?" } ?? "",
            isPresented: Binding(get: { pendingType != nil }, set: { if !$0 { pendingType = nil } }),
            titleVisibility: .visible
        ) {
            Button("Change effect", role: .destructive) {
                if let t = pendingType {
                    app.setEffectType(slot: slot, type: t)
                }
                pendingType = nil
            }
            Button("Cancel", role: .cancel) { pendingType = nil }
        } message: {
            Text("Its settings go back to the desk's defaults for the new effect.")
        }
    }
}

private struct TypeMenu: View {
    let slot: Int
    let current: Int
    let choose: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(Effects.typeMenu(slot: slot), id: \.0) { title, types in
                Menu(title) {
                    ForEach(types, id: \.0) { value, name in
                        Button {
                            if value != current { choose(value) }
                        } label: {
                            if value == current {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Change effect")
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .barChip()
        }
    }
}

/// Tap along to set the delay time; shows the time and tempo.
private struct TapTempoRow: View {
    let app: AppModel
    let address: String
    @State private var tempo = TapTempo()
    @State private var flash = false

    private func tap() {
        let p = app.param(address)
        guard p.isKnown else { return }
        if let newMS = tempo.tap(at: ProcessInfo.processInfo.systemUptime) {
            app.setFloat(address, Effects.delayTimeSpec.norm(Float(newMS)), steps: Effects.delayTimeSpec.steps)
        }
        flash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.2)) { flash = false }
        }
    }

    var body: some View {
        let p = app.param(address)
        let ms = Double(Effects.delayTimeSpec.value(p.float))
        HStack(spacing: 14) {
            Text("TAP")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(flash ? Color.black : Theme.text)
                .frame(width: 110, height: 54)
                .background(RoundedRectangle(cornerRadius: 6).fill(flash ? Theme.curve : Theme.raised2))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.curve.opacity(0.7), lineWidth: 1.5))
                .opacity(p.isKnown ? 1 : 0.4)
                .overlay(
                    // Timed on touch-down: how long each tap is held mustn't change the tempo.
                    TouchSurface(onBegin: { _ in tap() }, onEnd: { _, _ in }, immediate: true)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tap tempo")
                .accessibilityHint("Tap repeatedly in time with the music to set the delay time")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { tap() }
            VStack(alignment: .leading, spacing: 2) {
                Text(p.isKnown ? "\(Int(ms.rounded())) ms" : "—")
                    .font(Theme.mono(20))
                    .foregroundStyle(Theme.text)
                Text(p.isKnown ? String(format: "%.1f BPM", TapTempo.bpm(ms: ms)) : " ")
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
        }
    }
}

/// The strips this slot is inserted on (tap to open one).
private struct InsertedOnRow: View {
    let app: AppModel
    let slot: Int
    let close: () -> Void

    var body: some View {
        let strips = Effects.insertedOn(slot: slot) { app.param($0).isKnown ? app.param($0).int : nil }
        if !strips.isEmpty {
            HStack(spacing: 8) {
                Text("Inserted on")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(strips) { strip in
                            Button {
                                app.pendingDetail = strip
                                app.pendingDetailTab = .setup
                                close()
                            } label: {
                                Text(app.stripTitle(strip)).barChip()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

/// Which mix feeds the effect, with a shortcut to put that mix's sends on the faders.
private struct SourceRow: View {
    let app: AppModel
    let sourceValue: Int
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Fed from \(Effects.sourceName(sourceValue))")
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
            if let bus = Effects.feedingBus(sourceValue: sourceValue) {
                let name = app.param(StripID(.bus, bus).namePath).string
                if !name.isEmpty {
                    Text("(\(name))")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button {
                    app.selectSendsBus(bus)
                    close()
                } label: {
                    Text("Sends on faders")
                        .barChip()
                }
                .buttonStyle(.plain)
            } else {
                Spacer()
            }
        }
    }
}

/// The FX return's level and mute.
private struct ReturnRow: View {
    let app: AppModel
    let strip: StripID
    @State private var drag = DragTarget()

    var body: some View {
        let address = strip.faderPath
        let fader = app.param(address)
        HStack(spacing: 10) {
            Text("Return \(strip.footLabel)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .frame(width: 110, alignment: .leading)
            HFader(
                value: fader.float,
                hapticAtUnity: app.settings.hapticAtUnity,
                fine: app.fineMode,
                onLongPress: { app.editValue("\(strip.footLabel) return", address, Specs.fader) },
                onChange: { v in app.dragSet(address, drag, v, steps: 1023) },
                onTouch: { began in
                    if began { app.beginDrag(address, drag) } else { app.endDrag(drag) }
                }
            )
            .frame(height: 40)
            Text(fader.isKnown ? X32Math.formatFader(fader.float) : "—")
                .font(Theme.mono(13))
                .foregroundStyle(Theme.text)
                .frame(width: 50, alignment: .trailing)
            MuteButton(app: app, strip: strip, height: 36)
                .frame(width: 70)
        }
    }
}

/// One effect parameter: a slider, or a menu for choices.
private struct EffectParamControl: View {
    let app: AppModel
    let slot: Int
    let param: Effects.Param

    private static let percentSpec = ParamSpec(.linear(0, 100), steps: 1000, unit: "%", decimals: 0, defaultNorm: 0.5)

    var body: some View {
        let address = Effects.parPath(slot, param.number)
        switch param.kind {
        case .value(let spec):
            ParamKnob(app: app, address: address, spec: spec, title: param.name)
        case .percent:
            ParamKnob(app: app, address: address, spec: EffectParamControl.percentSpec, title: param.name)
        case .choice(let options):
            HStack {
                Text(param.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                Spacer()
                EnumMenu(app: app, address: address, options: options)
            }
            .frame(minHeight: 44)
        }
    }
}
