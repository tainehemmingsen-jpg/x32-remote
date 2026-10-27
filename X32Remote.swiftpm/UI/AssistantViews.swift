import SwiftUI

// MARK: - Gain wizard

/// "Auto gain": listens to the input while someone plays, then sets the preamp so the loudest
/// moment peaks with 12 dB to spare.
struct GainWizardButton: View {
    let app: AppModel
    let strip: StripID
    var height: CGFloat = 40
    @State private var open = false

    var body: some View {
        let ha = strip.headampIndexPath.map { app.param($0).int(or: -1) } ?? -1
        if strip.kind == .channel && ha >= 0 && ha < 128 {
            Button {
                open = true
            } label: {
                Label("Auto gain", systemImage: "wand.and.stars")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.raised2))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.accent.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $open) {
                GainWizardView(app: app, strip: strip, headamp: ha) { open = false }
                    .frame(width: 380)
                    .presentationCompactAdaptation(.popover)
                    .preferredColorScheme(.dark)
            }
        }
    }
}

private struct GainWizardView: View {
    let app: AppModel
    let strip: StripID
    let headamp: Int
    let close: () -> Void

    enum Phase: Equatable {
        case ready
        case listening(started: Date)
        case done(GainWizard.Result, peak: Float)
    }

    @State private var phase: Phase = .ready
    @State private var peak: Float = -90
    @State private var keepFader = false

    var body: some View {
        let meter = app.meters.meter(strip)
        let gainNorm = app.param(StripID.headampGainPath(headamp)).float
        let currentGain = Specs.headampGain.value(gainNorm)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Auto gain · \(app.stripTitle(strip))")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("Gain \(Specs.headampGain.display(gainNorm))")
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.secondary)
            }
            InputBar(level: meter.input, peak: peak)
                .frame(height: 22)
            switch phase {
            case .ready:
                Text("Have them play or sing as loud as they will in the show, then tap Listen. It takes \(Int(GainWizard.listenSeconds)) seconds.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LitButton(title: "Listen", isOn: true, color: Theme.accent, height: 46, fontSize: 16) {
                    peak = -90
                    phase = .listening(started: Date())
                }
            case .listening(let started):
                TimelineView(.periodic(from: started, by: 0.05)) { t in
                    let elapsed = t.date.timeIntervalSince(started)
                    let _ = sample(meter.input, elapsed: elapsed, currentGain: currentGain)
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: min(elapsed / GainWizard.listenSeconds, 1))
                        Text("Listening… loudest so far \(peak > -89 ? String(format: "%.0f dBFS", peak) : "nothing")")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                Button("Stop") { phase = .ready }
                    .font(.system(size: 14))
            case .done(let result, let heard):
                switch result {
                case .silent:
                    Text("Didn't hear anything. Check the mic, the cable, the patch and 48V, then try again.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.mute)
                        .fixedSize(horizontal: false, vertical: true)
                    LitButton(title: "Try again", isOn: false, height: 40, fontSize: 14) { phase = .ready }
                case .set(let gain, let clipped):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(format: "Loudest peak: %.0f dBFS%@", heard, clipped ? " (clipping)" : ""))
                            .font(.system(size: 13))
                            .foregroundStyle(clipped ? Theme.mute : Theme.secondary)
                        Text("Set gain \(Specs.headampGain.display(gainNorm)) → \(Specs.headampGain.display(Specs.headampGain.norm(gain)))")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if abs(gain - currentGain) < 1 {
                            Text("That's about where it is already.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.on)
                        }
                    }
                    Toggle("Move the fader to keep the main mix level the same", isOn: $keepFader)
                        .font(.system(size: 13))
                    HStack(spacing: 10) {
                        LitButton(title: "Again", isOn: false, height: 44, fontSize: 14) { phase = .ready }
                        LitButton(title: "Set gain", isOn: true, color: Theme.on, height: 44, fontSize: 15) {
                            app.setGain(strip, gain: gain, keepFaderLevel: keepFader)
                            close()
                        }
                    }
                    Text("Monitor sends before the fader get louder or quieter by the same amount.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    /// Called while listening: keeps the loudest input level and finishes after the time is up.
    private func sample(_ level: Float, elapsed: TimeInterval, currentGain: Float) {
        DispatchQueue.main.async {
            guard case .listening = phase else { return }
            if level > peak { peak = level }
            if elapsed >= GainWizard.listenSeconds {
                phase = .done(GainWizard.suggestion(currentGain: currentGain, peak: peak), peak: peak)
            }
        }
    }
}

/// Input level with a target zone (where peaks should land) and the loudest peak heard.
private struct InputBar: View {
    let level: Float
    let peak: Float

    var body: some View {
        Canvas { ctx, size in
            func x(_ db: Float) -> CGFloat { CGFloat((min(max(db, -60), 0) + 60) / 60) * size.width }
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4), with: .color(Color.black.opacity(0.6)))
            // Target zone: peaks between -18 and -6 dBFS.
            ctx.fill(Path(CGRect(x: x(-18), y: 0, width: x(-6) - x(-18), height: size.height)), with: .color(Theme.on.opacity(0.18)))
            let color: Color = level >= -3 ? Theme.mute : (level >= -18 ? Theme.on : Theme.accent)
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 3, width: x(level), height: size.height - 6), cornerRadius: 2), with: .color(color))
            if peak > -60 {
                ctx.fill(Path(CGRect(x: x(peak) - 1, y: 0, width: 2, height: size.height)), with: .color(Theme.text))
            }
            for db: Float in [-48, -36, -24, -12, 0] {
                ctx.draw(Text("\(Int(db))").font(.system(size: 8)).foregroundColor(Theme.tertiary),
                         at: CGPoint(x: min(x(db) + 2, size.width - 8), y: size.height / 2), anchor: .leading)
            }
        }
        .accessibilityLabel("Input level")
        .accessibilityValue(String(format: "%.0f dBFS", level))
    }
}

// MARK: - Starting points

/// "Start from…": loads a built-in starting point for the source plugged into a channel.
struct StarterButton: View {
    let app: AppModel
    let strip: StripID
    var height: CGFloat = 40
    @State private var open = false

    var body: some View {
        if strip.kind == .channel {
            Button {
                open = true
            } label: {
                Label("Start from…", systemImage: "square.grid.2x2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.raised2))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $open) {
                StarterPicker(app: app, strip: strip) { open = false }
                    .frame(width: 420)
                    .presentationCompactAdaptation(.popover)
                    .preferredColorScheme(.dark)
            }
        }
    }
}

private struct StarterPicker: View {
    let app: AppModel
    let strip: StripID
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's on \(app.stripTitle(strip))?")
                .font(.system(size: 16, weight: .semibold))
            Text("Sets the low cut, gate, EQ and compressor to a sensible start for that source. Gain and sends stay as they are, and Undo takes it back.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(StarterPresets.all) { s in
                    Button {
                        app.loadPreset(StarterPresets.preset(s), onto: strip)
                        close()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: s.symbol)
                                .font(.system(size: 22))
                            Text(s.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Theme.panel)
    }
}
