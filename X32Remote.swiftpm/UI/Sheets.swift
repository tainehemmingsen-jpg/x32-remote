import SwiftUI

// MARK: - Scenes

struct ScenesSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmScene: Int?

    var body: some View {
        let current = app.param("/-show/prepos/current").int(or: -1)
        let scenes = (0..<100).filter { app.param(String(format: "/-show/showfile/scene/%03d/hasdata", $0)).bool }
        NavigationStack {
            List {
                if scenes.isEmpty {
                    if app.pendingRequests > 0 {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading scenes from the desk…")
                                .foregroundStyle(Theme.secondary)
                        }
                    } else {
                        Text("No scenes saved on this desk yet.")
                            .foregroundStyle(Theme.secondary)
                    }
                }
                ForEach(scenes, id: \.self) { n in
                    SceneRow(app: app, number: n, isCurrent: n == current) {
                        confirmScene = n
                    }
                }
            }
            .navigationTitle("Scenes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                confirmTitle,
                isPresented: Binding(get: { confirmScene != nil }, set: { if !$0 { confirmScene = nil } }),
                titleVisibility: .visible
            ) {
                Button("Recall scene", role: .destructive) {
                    if let n = confirmScene {
                        app.recallScene(n)
                    }
                    confirmScene = nil
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    confirmScene = nil
                }
            } message: {
                Text("This changes the desk straight away: faders, mutes, EQ and routing.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var confirmTitle: String {
        guard let n = confirmScene else { return "Recall scene?" }
        let name = app.param(String(format: "/-show/showfile/scene/%03d/name", n)).string
        return String(format: "Recall scene %02d", n) + (name.isEmpty ? "?" : " “\(name)”?")
    }
}

private struct SceneRow: View {
    let app: AppModel
    let number: Int
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        let name = app.param(String(format: "/-show/showfile/scene/%03d/name", number)).string
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(String(format: "%02d", number))
                    .font(Theme.mono(15, .bold))
                    .foregroundStyle(isCurrent ? Theme.accent : Theme.secondary)
                    .frame(width: 34, alignment: .leading)
                Text(name.isEmpty ? "Untitled" : name)
                    .font(.system(size: 17, weight: isCurrent ? .bold : .regular))
                    .foregroundStyle(Theme.text)
                Spacer()
                if isCurrent {
                    Text("CURRENT")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.accent))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modes

struct ModesSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(AppMode.allCases) { mode in
                    Button {
                        app.setMode(mode)
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Text(mode.subtitle)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            if app.settings.mode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Mode")
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

// MARK: - Settings

struct SettingsSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var newPIN = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Console") {
                    LabeledContent("Name", value: app.connectedName)
                    LabeledContent("Address", value: app.connectedAddress)
                    if let info = app.console {
                        LabeledContent("Model", value: info.model)
                        LabeledContent("Firmware", value: info.firmware)
                    }
                    Toggle("Reconnect to the last desk on launch", isOn: binding(\.autoConnect))
                    Button("Disconnect", role: .destructive) {
                        dismiss()
                        app.disconnect()
                    }
                }
                Section("Mode") {
                    ForEach(AppMode.allCases) { mode in
                        Button {
                            app.setMode(mode)
                            dismiss()
                        } label: {
                            HStack {
                                Label(mode.title, systemImage: mode.symbol)
                                Spacer()
                                if app.settings.mode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Section {
                    Toggle("Keep screen awake while connected", isOn: binding(\.keepAwake))
                    Toggle("Tick when a fader passes 0 dB", isOn: binding(\.hapticAtUnity))
                    Toggle("Show dB scale on faders", isOn: binding(\.showFaderScale))
                } header: {
                    Text("Faders")
                } footer: {
                    Text("Tip: slide your finger sideways off a fader while dragging for fine control.")
                }
                Section {
                    SecureField(app.hasPIN ? "Change PIN" : "Set a PIN (4+ digits)", text: $newPIN)
                        .keyboardType(.numberPad)
                    Button("Save PIN") {
                        app.updateSettings { $0.pin = newPIN }
                        newPIN = ""
                    }
                    .disabled(newPIN.count < 4)
                    if app.hasPIN {
                        Button("Remove PIN", role: .destructive) {
                            app.updateSettings { s in
                                s.pin = ""
                                s.locked = false
                            }
                        }
                    }
                } header: {
                    Text("PIN")
                } footer: {
                    Text("The PIN guards the locked Monitor and Simple modes.")
                }
                Section("About") {
                    Text("X32 Remote talks to Behringer X32 and Midas M32 consoles over OSC on UDP port 10023. It isn't made by or affiliated with Behringer or Music Tribe.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { app.settings[keyPath: keyPath] },
            set: { v in app.updateSettings { $0[keyPath: keyPath] = v } }
        )
    }
}

// MARK: - PIN

/// Asks for the PIN; calls `onSuccess` when it matches.
struct PINPrompt: View {
    let app: AppModel
    let title: String
    let message: String
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""
    @State private var wrong = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            SecureField("PIN", text: $entry)
                .keyboardType(.numberPad)
                .focused($focused)
                .font(.system(size: 24, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(width: 200, height: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
            if wrong {
                Text("That PIN isn't right.")
                    .foregroundStyle(Theme.mute)
            }
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                Button("Unlock") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(entry.isEmpty)
            }
        }
        .padding(30)
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
        .onAppear {
            focused = true
        }
        .onSubmit {
            submit()
        }
    }

    private func submit() {
        if app.checkPIN(entry) {
            dismiss()
            onSuccess()
        } else {
            wrong = true
            entry = ""
        }
    }
}
