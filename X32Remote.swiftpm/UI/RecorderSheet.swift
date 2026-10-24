import SwiftUI

/// Transport for the desk's USB stick recorder.
struct RecorderSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmStop = false

    var body: some View {
        let stateParam = app.param(Recorder.statePath)
        let state = Recorder.State(rawValue: stateParam.int) ?? .stop
        let mounted = app.param(Recorder.mountedPath)
        let file = app.param(Recorder.filePath).string
        NavigationStack {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(state.isRecording ? Theme.mute : (state == .play ? Theme.on : Theme.tertiary))
                            .frame(width: 10, height: 10)
                        Text(stateParam.isKnown ? state.title : "Reading…")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.text)
                    }
                    Text(file.isEmpty ? " " : file)
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if mounted.isKnown && !mounted.bool {
                        Text("No USB stick in the desk")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.mute)
                    }
                }
                HStack(spacing: 10) {
                    TransportButton(symbol: "backward.fill", label: "Rewind", tint: Theme.text, active: state == .rewind) {
                        app.setInt(Recorder.statePath, Recorder.State.rewind.rawValue)
                    }
                    .disabled(state.isRecording)
                    TransportButton(symbol: "stop.fill", label: "Stop", tint: Theme.text, active: state == .stop) {
                        if state.isRecording { confirmStop = true } else { app.setInt(Recorder.statePath, Recorder.State.stop.rawValue) }
                    }
                    TransportButton(symbol: "play.fill", label: "Play", tint: Theme.on, active: state == .play) {
                        app.setInt(Recorder.statePath, Recorder.State.play.rawValue)
                    }
                    .disabled(state.isRecording)
                    TransportButton(symbol: "pause.fill", label: "Pause", tint: Theme.solo, active: state == .playPaused || state == .recordPaused) {
                        if let target = Recorder.pauseTarget(from: state) { app.setInt(Recorder.statePath, target.rawValue) }
                    }
                    .disabled(Recorder.pauseTarget(from: state) == nil)
                    TransportButton(symbol: "record.circle.fill", label: "Record", tint: Theme.mute, active: state.isRecording) {
                        app.setInt(Recorder.statePath, Recorder.State.record.rawValue)
                    }
                    .disabled(!(state == .stop || state == .recordPaused) || (mounted.isKnown && !mounted.bool))
                    TransportButton(symbol: "forward.fill", label: "Fast forward", tint: Theme.text, active: state == .fastForward) {
                        app.setInt(Recorder.statePath, Recorder.State.fastForward.rawValue)
                    }
                    .disabled(state.isRecording)
                }
                .disabled(!stateParam.isKnown)
                Text("Records what's patched to the record outputs (Output patch → Record).")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .navigationTitle("USB recorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Stop recording?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Stop recording", role: .destructive) {
                    app.setInt(Recorder.statePath, Recorder.State.stop.rawValue)
                }
                Button("Keep recording", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .task {
            // The desk reports transport changes, but read again now and then in case one is missed.
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
                app.loadRecorder()
            }
        }
    }
}

private struct TransportButton: View {
    let symbol: String
    let label: String
    let tint: Color
    let active: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(active ? Color.black.opacity(0.85) : tint)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? tint : Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
