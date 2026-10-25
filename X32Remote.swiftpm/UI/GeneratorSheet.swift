import SwiftUI

/// The desk's signal generator. Turning it on asks first (it puts a tone or noise on a live
/// output), and closing the sheet with it running asks whether to leave it on.
struct GeneratorSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmOn = false
    @State private var confirmLeaveOn = false

    var body: some View {
        let onParam = app.param(Oscillator.onPath)
        let on = onParam.bool
        let select = app.param(Oscillator.selectPath).int(or: 0)
        let destination = app.param(Oscillator.destinationPath)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Button {
                            if on {
                                app.setBool(Oscillator.onPath, false)
                            } else if onParam.isKnown {
                                confirmOn = true
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: on ? "waveform.circle.fill" : "waveform.circle")
                                    .font(.system(size: 30))
                                Text(on ? "ON" : "OFF")
                                    .font(.system(size: 13, weight: .heavy))
                            }
                            .foregroundStyle(on ? Color.black.opacity(0.85) : Theme.text)
                            .frame(width: 110, height: 90)
                            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.solo : Theme.raised))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Theme.solo : Color.white.opacity(0.1), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(!onParam.isKnown)
                        .accessibilityLabel("Generator")
                        .accessibilityValue(on ? "on" : "off")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(on ? "Sending to \(destination.isKnown ? Oscillator.destinationName(destination.int) : "—")" : "Off")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(on ? Theme.solo : Theme.text)
                            Text("Use it to ring out monitors or check an output. It goes to the destination at the level below, so start low.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    Panel(title: "Signal") {
                        LabeledChoice(app: app, title: "Type", address: Oscillator.typePath, options: Oscillator.types)
                        LabeledChoice(app: app, title: "Destination", address: Oscillator.destinationPath, options: Oscillator.destinations)
                        ParamKnob(app: app, address: Oscillator.levelPath, spec: Oscillator.levelSpec, title: "Level", tint: Theme.solo)
                    }
                    Panel(title: "Frequency (sine)") {
                        HStack(spacing: 10) {
                            ForEach(0..<2, id: \.self) { i in
                                LitButton(title: Oscillator.frequencySelect[i], isOn: select == i, height: 36, style: .outline) {
                                    app.setInt(Oscillator.selectPath, i)
                                }
                                .frame(width: 70)
                                .accessibilityLabel("Use frequency \(Oscillator.frequencySelect[i])")
                            }
                            Spacer()
                        }
                        ParamKnob(app: app, address: Oscillator.f1Path, spec: Oscillator.frequencySpec, title: "F1", enabled: select == 0)
                        ParamKnob(app: app, address: Oscillator.f2Path, spec: Oscillator.frequencySpec, title: "F2", enabled: select == 1)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .overlay {
                ValueEditorOverlay(app: app)
            }
            .overlay(alignment: .bottom) {
                ToastView(app: app)
            }
            .navigationTitle("Signal generator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if app.param(Oscillator.onPath).bool {
                            confirmLeaveOn = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .interactiveDismissDisabled(on)
            .confirmationDialog("Turn the generator on?", isPresented: $confirmOn, titleVisibility: .visible) {
                Button("Turn on", role: .destructive) {
                    app.setBool(Oscillator.onPath, true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(Oscillator.types[min(max(app.param(Oscillator.typePath).int, 0), 2)]) goes to \(Oscillator.destinationName(destination.int)) at \(Oscillator.levelSpec.display(app.param(Oscillator.levelPath).float)).")
            }
            .confirmationDialog("The generator is still on", isPresented: $confirmLeaveOn, titleVisibility: .visible) {
                Button("Turn it off and close") {
                    app.setBool(Oscillator.onPath, false)
                    dismiss()
                }
                Button("Leave it on", role: .destructive) {
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .onDisappear {
                app.valueEditor = nil
            }
        }
        .preferredColorScheme(.dark)
    }
}
