import SwiftUI

/// One performer's monitor mix: every input's send to a single bus, as big horizontal faders.
struct MonitorScreen: View {
    @Bindable var app: AppModel
    @State private var editing = false
    @State private var askPIN = false
    /// Only the inputs that were in this mix (send above -inf) when "In my mix" was tapped.
    /// A snapshot, so a row doesn't vanish while its fader is being pulled down.
    @State private var inMix: Set<String>?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let bus = app.settings.monitorBus
        let compact = sizeClass == .compact
        let busStrip = StripID(.bus, bus)
        let busName = app.param(busStrip.namePath).string
        let busColor = Theme.scribble(app.param(busStrip.colorPath).int)
        let sources = visibleSources()
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(busColor)
                    .frame(width: 8, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MY MIX · BUS \(bus)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                    Text(busName.isEmpty ? "Mix \(bus)" : busName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                Spacer()
                UndoButton(app: app)
                FineButton(app: app, height: 34)
                    .frame(width: 64)
                if app.settings.locked {
                    Button {
                        askPIN = true
                    } label: {
                        Label("Locked", systemImage: "lock.fill")
                            .labelStyle(AdaptiveLabelStyle(iconOnly: compact))
                            .barChip()
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        editing = true
                    } label: {
                        Label("Choose", systemImage: "slider.horizontal.3")
                            .labelStyle(AdaptiveLabelStyle(iconOnly: compact))
                            .barChip()
                    }
                    .buttonStyle(.plain)
                    Button {
                        app.setMode(.mixer)
                    } label: {
                        Label("Mixer", systemImage: "slider.vertical.3")
                            .labelStyle(AdaptiveLabelStyle(iconOnly: compact))
                            .barChip()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.topBar)

            MonitorMasterRow(app: app, bus: bus, color: busColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(busColor.opacity(0.12))

            HStack(spacing: 8) {
                FilterChip(title: "Everything", active: inMix == nil) { inMix = nil }
                FilterChip(title: "In my mix", active: inMix != nil) { inMix = currentlyInMix() }
                Spacer()
                Text("\(sources.count) inputs")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            GeometryReader { geo in
                // Two columns on a landscape iPad, so a whole band fits without scrolling.
                let columns = geo.size.width >= 900 ? 2 : 1
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 6) {
                        ForEach(sources) { source in
                            MonitorRow(app: app, source: source, bus: bus, color: busColor)
                        }
                    }
                    if sources.isEmpty {
                        Text(inMix != nil ? "Nothing is in this mix yet. Tap Everything and bring some inputs up."
                                       : "No inputs to show. Tap Choose to pick which inputs appear here.")
                            .foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.center)
                            .padding(30)
                    }
                }
                .contentMargins(.horizontal, 12, for: .scrollContent)
                .contentMargins(.vertical, 10, for: .scrollContent)
            }
        }
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            ToastView(app: app)
        }
        .overlay {
            ValueEditorOverlay(app: app)
        }
        .animation(.easeOut(duration: 0.15), value: app.valueEditor?.id)
        .onAppear {
            app.loadSends(bus: bus)
        }
        .onChange(of: bus) { _, newBus in
            app.loadSends(bus: newBus)
            inMix = nil
        }
        .sheet(isPresented: $editing) {
            MonitorSetupSheet(app: app)
        }
        .sheet(isPresented: $askPIN) {
            PINPrompt(app: app, title: "Unlock this iPad", message: "Enter the PIN to unlock and leave the monitor mix.") {
                app.updateSettings { $0.locked = false }
            }
        }
    }

    private func currentlyInMix() -> Set<String> {
        let bus = app.settings.monitorBus
        return Set(StripID.busSources.filter { s in
            let level = app.param(s.sendLevelPath(bus))
            return level.isKnown && level.float > 0.001 && app.param(s.sendOnPath(bus)).int(or: 1) != 0
        }.map(\.id))
    }

    private func visibleSources() -> [StripID] {
        let hidden = Set(app.settings.monitorHidden)
        return StripID.busSources.filter { s in
            if hidden.contains(s.id) { return false }
            if let inMix { return inMix.contains(s.id) }
            if app.settings.monitorShowAll { return true }
            return !app.param(s.namePath).string.isEmpty
        }
    }
}

private struct FilterChip: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: active ? .semibold : .regular))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(active ? Theme.raised2 : Theme.raised))
                .overlay(Capsule().strokeBorder(active ? Theme.on : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

private struct MonitorMasterRow: View {
    let app: AppModel
    let bus: Int
    let color: Color
    @State private var drag = DragTarget()

    var body: some View {
        let strip = StripID(.bus, bus)
        let fader = app.param(strip.faderPath)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("OVERALL")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.text)
                Text("Whole mix level")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }
            .frame(width: 112, alignment: .leading)
            HFader(
                value: fader.float,
                tint: color,
                hapticAtUnity: app.settings.hapticAtUnity,
                fine: app.fineMode,
                onLongPress: { app.editValue("\(app.stripTitle(strip)) · Overall level", strip.faderPath, Specs.fader) },
                onChange: { v in app.dragSet(strip.faderPath, drag, v, steps: 1023) },
                onTouch: { began in
                    if began { app.beginDrag(strip.faderPath, drag) } else { app.endDrag(drag) }
                }
            )
            .frame(height: 50)
            Text(fader.isKnown ? X32Math.formatFader(fader.float) : "—")
                .font(Theme.mono(14, .semibold))
                .frame(width: 52, alignment: .trailing)
            MeterView(meter: app.meters.meter(strip))
                .frame(width: 8, height: 44)
            MuteButton(app: app, strip: strip, height: 44)
                .frame(width: 70)
        }
    }
}

private struct MonitorRow: View {
    let app: AppModel
    let source: StripID
    let bus: Int
    let color: Color
    @State private var drag = DragTarget()

    var body: some View {
        let name = app.param(source.namePath).string
        let sourceColor = Theme.scribble(app.param(source.colorPath).int)
        let levelAddress = source.sendLevelPath(bus)
        let onAddress = source.sendOnPath(bus)
        let level = app.param(levelAddress)
        let on = app.param(onAddress).int(or: 1) != 0
        let channelMuted = app.param(source.onPath).int(or: 1) == 0
        let label = MonitorRowLabel(name: name.isEmpty ? source.shortLabel : name, short: source.shortLabel, color: sourceColor, mutedAtDesk: channelMuted)
        let fader = HFader(
            value: level.float,
            tint: color,
            hapticAtUnity: app.settings.hapticAtUnity,
            fine: app.fineMode,
            onLongPress: { app.editValue("\(name.isEmpty ? source.footLabel : name) in my mix", levelAddress, Specs.send) },
            onChange: { v in app.dragSet(levelAddress, drag, v, steps: 160) },
            onTouch: { began in
                if began { app.beginDrag(levelAddress, drag) } else { app.endDrag(drag) }
            }
        )
        .frame(height: 48)
        .opacity(on ? 1 : 0.45)
        let readout = Text(level.isKnown ? X32Math.formatFader(level.float) : "—")
            .font(Theme.mono(14, .semibold))
            .frame(width: 52, alignment: .trailing)
        let meter = MeterView(meter: app.meters.meter(source))
            .frame(width: 8, height: 40)
        let onButton = LitButton(title: on ? "ON" : "OFF", isOn: on, color: Theme.on, height: 44, fontSize: 13) {
            app.setBool(onAddress, !on)
        }
        .frame(width: 70)
        // Phones: put the name above the fader so the fader keeps a usable length.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                label.frame(width: 112, alignment: .leading)
                fader.frame(minWidth: 180)
                readout
                meter
                onButton
            }
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    label
                    Spacer(minLength: 4)
                    readout
                    onButton
                }
                HStack(spacing: 8) {
                    fader
                    meter
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.panel))
    }
}

private struct MonitorRowLabel: View {
    let name: String
    let short: String
    let color: Color
    let mutedAtDesk: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 6, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(short)
                    if mutedAtDesk {
                        Text("· MUTED AT DESK")
                            .foregroundStyle(Theme.mute)
                    }
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// Pick the bus and which inputs appear in the monitor mix, and lock it.
struct MonitorSetupSheet: View {
    @Bindable var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var lockPIN = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Mix") {
                    Picker("Bus", selection: Binding(
                        get: { app.settings.monitorBus },
                        set: { newBus in
                            app.updateSettings { $0.monitorBus = newBus }
                            app.loadSends(bus: newBus)
                        }
                    )) {
                        ForEach(1...16, id: \.self) { b in
                            Text(busTitle(b)).tag(b)
                        }
                    }
                }
                Section {
                    Toggle("Show unnamed inputs", isOn: Binding(
                        get: { app.settings.monitorShowAll },
                        set: { v in app.updateSettings { $0.monitorShowAll = v } }
                    ))
                    ForEach(StripID.busSources) { s in
                        SourceVisibilityRow(app: app, source: s)
                    }
                } header: {
                    Text("Inputs shown")
                } footer: {
                    Text("Turn off anything the performer doesn't need, so their list stays short.")
                }
                Section {
                    SecureField("PIN (4+ digits)", text: $lockPIN)
                        .keyboardType(.numberPad)
                    Button("Lock to this mix") {
                        app.updateSettings { s in
                            if lockPIN.count >= 4 {
                                s.pin = lockPIN
                            }
                            s.locked = true
                        }
                        dismiss()
                    }
                    .disabled(lockPIN.count < 4 && !app.hasPIN)
                } header: {
                    Text("Lock")
                } footer: {
                    Text("Locking hides the mixer so a performer can only change their own mix. Unlock with the PIN.")
                }
            }
            .navigationTitle("Monitor mix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func busTitle(_ b: Int) -> String {
        let name = app.param(StripID(.bus, b).namePath).string
        return name.isEmpty ? "Mix \(b)" : "Mix \(b) · \(name)"
    }
}

private struct SourceVisibilityRow: View {
    let app: AppModel
    let source: StripID

    var body: some View {
        let name = app.param(source.namePath).string
        let hidden = app.settings.monitorHidden.contains(source.id)
        Toggle(isOn: Binding(
            get: { !hidden },
            set: { show in
                app.updateSettings { s in
                    s.monitorHidden.removeAll { $0 == source.id }
                    if !show {
                        s.monitorHidden.append(source.id)
                    }
                }
            }
        )) {
            HStack {
                Text(source.shortLabel)
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 64, alignment: .leading)
                Text(name.isEmpty ? "—" : name)
            }
        }
    }
}
