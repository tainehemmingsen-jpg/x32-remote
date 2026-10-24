import SwiftUI

/// A handful of big, friendly controls (music, mic, main volume) for staff. Levels can be capped.
struct SimpleScreen: View {
    @Bindable var app: AppModel
    @State private var editing = false
    @State private var askPIN = false
    @State private var pendingAction: PendingAction?

    enum PendingAction {
        case edit
        case unlock
        case exit
    }

    var body: some View {
        let controls = app.settings.simpleControls
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height && geo.size.width >= 700
            VStack(spacing: 0) {
                header
                if controls.isEmpty {
                    Spacer()
                    Text("No controls yet. Tap Edit to add the channels staff should be able to change.")
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .padding(40)
                    Spacer()
                } else if landscape {
                    HStack(spacing: 14) {
                        ForEach(controls) { control in
                            SimpleColumn(app: app, control: control)
                        }
                    }
                    .padding(16)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(controls) { control in
                                SimpleRow(app: app, control: control)
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $editing) {
            SimpleEditor(app: app)
        }
        .sheet(isPresented: $askPIN) {
            PINPrompt(app: app, title: "Enter PIN", message: "These controls are locked.") {
                switch pendingAction {
                case .edit:
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        editing = true
                    }
                case .unlock:
                    app.updateSettings { $0.locked = false }
                case .exit:
                    app.updateSettings { $0.locked = false }
                    app.setMode(.mixer)
                case .none:
                    break
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(app.settings.simpleTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.text)
            Spacer()
            if app.settings.locked {
                Button {
                    pendingAction = .unlock
                    askPIN = true
                } label: {
                    Label("Locked", systemImage: "lock.fill")
                        .barChip()
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    if app.hasPIN {
                        pendingAction = .edit
                        askPIN = true
                    } else {
                        editing = true
                    }
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .barChip()
                }
                .buttonStyle(.plain)
                Button {
                    app.setMode(.mixer)
                } label: {
                    Label("Mixer", systemImage: "slider.vertical.3")
                        .barChip()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.topBar)
    }
}

private struct SimpleColumn: View {
    let app: AppModel
    let control: SimpleControl
    @State private var drag = DragTarget()

    var body: some View {
        let strip = control.strip
        let color = Theme.scribble(app.param(strip.colorPath).int)
        let fader = app.param(strip.faderPath)
        let cap = control.maxDB >= 10 ? 1 : X32Math.dbToFader(control.maxDB)
        VStack(spacing: 10) {
            Text(control.label)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(height: 56)
            Text(SimpleScreen.levelWord(fader.float))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 6) {
                FaderView(
                    value: fader.float,
                    tint: color.opacity(0.9),
                    maxValue: cap,
                    showScale: false,
                    hapticAtUnity: app.settings.hapticAtUnity,
                    capTint: color,
                    onChange: { v in app.dragSet(strip.faderPath, drag, min(v, cap), steps: 1023) },
                    onTouch: { began in
                        if began { app.beginDrag(strip.faderPath, drag) } else { app.endDrag(drag) }
                    }
                )
                if strip.kind != .dca {
                    MeterView(meter: app.meters.meter(strip), stereo: strip.kind == .main)
                        .frame(width: strip.kind == .main ? 14 : 8)
                        .padding(.vertical, 24)
                }
            }
            SimpleMute(app: app, strip: strip, height: 60)
        }
        .padding(14)
        .frame(maxWidth: 260)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(color.opacity(0.5), lineWidth: 2)
        )
    }
}

private struct SimpleRow: View {
    let app: AppModel
    let control: SimpleControl
    @State private var drag = DragTarget()

    var body: some View {
        let strip = control.strip
        let color = Theme.scribble(app.param(strip.colorPath).int)
        let fader = app.param(strip.faderPath)
        let cap = control.maxDB >= 10 ? 1 : X32Math.dbToFader(control.maxDB)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(control.label)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(SimpleScreen.levelWord(fader.float))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 12) {
                HFader(
                    value: fader.float,
                    tint: color,
                    maxValue: cap,
                    hapticAtUnity: app.settings.hapticAtUnity,
                    onChange: { v in app.dragSet(strip.faderPath, drag, min(v, cap), steps: 1023) },
                    onTouch: { began in
                        if began { app.beginDrag(strip.faderPath, drag) } else { app.endDrag(drag) }
                    }
                )
                .frame(height: 56)
                SimpleMute(app: app, strip: strip, height: 56)
                    .frame(width: 92)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(0.45), lineWidth: 2)
        )
    }
}

private struct SimpleMute: View {
    let app: AppModel
    let strip: StripID
    let height: CGFloat

    var body: some View {
        let muted = app.param(strip.onPath).int(or: 1) == 0
        LitButton(title: muted ? "OFF" : "ON", isOn: !muted, color: Theme.on, height: height, fontSize: 18) {
            app.toggleMute(strip)
        }
    }
}

extension SimpleScreen {
    /// Plain-language level for non-technical users.
    static func levelWord(_ fader: Float) -> String {
        let db = X32Math.faderToDB(fader)
        if db.isInfinite || db < -60 { return "Silent" }
        let percent = Int((fader / X32Math.unityFader * 100).rounded())
        return "\(min(percent, 133))%"
    }
}

/// Add, remove, rename and cap the Simple controls.
struct SimpleEditor: View {
    @Bindable var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var newPIN = ""
    @State private var adding = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Screen title") {
                    TextField("Title", text: Binding(
                        get: { app.settings.simpleTitle },
                        set: { v in app.updateSettings { $0.simpleTitle = v } }
                    ))
                }
                Section {
                    ForEach(app.settings.simpleControls) { control in
                        SimpleControlEditorRow(app: app, control: control)
                    }
                    .onDelete { offsets in
                        app.updateSettings { $0.simpleControls.remove(atOffsets: offsets) }
                    }
                    .onMove { from, to in
                        app.updateSettings { $0.simpleControls.move(fromOffsets: from, toOffset: to) }
                    }
                    Button {
                        adding = true
                    } label: {
                        Label("Add a control", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Each control moves one fader on the desk. “Max” stops staff pushing it past that level.")
                }
                Section {
                    SecureField(app.hasPIN ? "New PIN" : "PIN (4+ digits)", text: $newPIN)
                        .keyboardType(.numberPad)
                    Button("Save PIN") {
                        app.updateSettings { $0.pin = newPIN }
                        newPIN = ""
                    }
                    .disabled(newPIN.count < 4)
                    Button("Lock this iPad to these controls") {
                        app.updateSettings { $0.locked = true }
                        dismiss()
                    }
                    .disabled(!app.hasPIN)
                } header: {
                    Text("Lock")
                } footer: {
                    Text("When locked, only these controls are shown. Tap the lock and enter the PIN to get back to the mixer.")
                }
            }
            .navigationTitle("Simple controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $adding) {
                StripPicker(app: app) { strip in
                    let name = app.param(strip.namePath).string
                    app.updateSettings { s in
                        s.simpleControls.append(SimpleControl(strip: strip, label: name.isEmpty ? strip.shortLabel : name, maxDB: 0))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct SimpleControlEditorRow: View {
    let app: AppModel
    let control: SimpleControl

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Label", text: Binding(
                get: { control.label },
                set: { v in update { $0.label = v } }
            ))
            .font(.system(size: 17, weight: .semibold))
            HStack {
                Text(control.strip.shortLabel + " · " + displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Picker("Max", selection: Binding(
                    get: { control.maxDB },
                    set: { v in update { $0.maxDB = v } }
                )) {
                    Text("Max 0 dB").tag(Float(0))
                    Text("Max -5 dB").tag(Float(-5))
                    Text("Max -10 dB").tag(Float(-10))
                    Text("Max +5 dB").tag(Float(5))
                    Text("No limit").tag(Float(10))
                }
                .pickerStyle(.menu)
            }
        }
        .padding(.vertical, 4)
    }

    private var displayName: String {
        let n = app.param(control.strip.namePath).string
        return n.isEmpty ? "unnamed" : n
    }

    private func update(_ change: @escaping (inout SimpleControl) -> Void) {
        app.updateSettings { s in
            if let i = s.simpleControls.firstIndex(where: { $0.id == control.id }) {
                change(&s.simpleControls[i])
            }
        }
    }
}

/// Choose any strip on the desk.
struct StripPicker: View {
    let app: AppModel
    let onPick: (StripID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(StripKind.allCases, id: \.self) { kind in
                    Section(kind.title) {
                        ForEach(StripID.all(kind)) { strip in
                            Button {
                                onPick(strip)
                                dismiss()
                            } label: {
                                StripPickerRow(app: app, strip: strip)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose a fader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct StripPickerRow: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let name = app.param(strip.namePath).string
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.scribble(app.param(strip.colorPath).int))
                .frame(width: 6, height: 24)
            Text(strip.shortLabel)
                .foregroundStyle(Theme.secondary)
                .frame(width: 70, alignment: .leading)
            Text(name.isEmpty ? "—" : name)
                .foregroundStyle(Theme.text)
        }
    }
}
