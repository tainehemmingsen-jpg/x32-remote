import SwiftUI

/// Shown over the mixer or channel page when a control is long-pressed: the exact value,
/// fine and coarse steps, typed entry and reset.
struct ValueEditorOverlay: View {
    @Bindable var app: AppModel
    /// The mixer only shows it when no channel page is covering it.
    var active: Bool = true

    var body: some View {
        if active, let request = app.valueEditor {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        app.valueEditor = nil
                    }
                ValueEditorCard(app: app, request: request)
                    .id(request.id)
                    .padding(20)
            }
            .transition(.opacity)
        }
    }
}

private struct ValueEditorCard: View {
    let app: AppModel
    let request: ValueEditRequest
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var typing: Bool

    var body: some View {
        let p = app.param(request.address)
        let norm = p.float(or: request.spec.defaultNorm)
        VStack(spacing: 16) {
            HStack {
                Text(request.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    app.valueEditor = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.raised2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text(p.isKnown ? display(norm) : "—")
                .font(.system(size: 40, weight: .light).monospacedDigit())
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                StepKey(label: coarseLabel(-1)) { nudge(norm, coarse: true, up: false) }
                StepKey(label: fineLabel(-1)) { nudge(norm, coarse: false, up: false) }
                StepKey(label: fineLabel(1)) { nudge(norm, coarse: false, up: true) }
                StepKey(label: coarseLabel(1)) { nudge(norm, coarse: true, up: true) }
            }
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .submitLabel(.done)
                    .font(.system(size: 18).monospacedDigit())
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(invalid ? Theme.mute : Color.white.opacity(0.14), lineWidth: 1))
                    .onSubmit(applyText)
                Button("Set", action: applyText)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
                    .frame(width: 70, height: 46)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised2))
                    .buttonStyle(.plain)
                    .disabled(text.isEmpty)
            }
            if let reset = request.resetNorm {
                Button {
                    set(reset)
                } label: {
                    Text("Reset to \(display(reset))")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: 440)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
    }

    private var placeholder: String {
        switch request.style {
        case .pan: return "Type L30, C or R30"
        case .normal: return request.spec.unit.isEmpty ? "Type a value" : "Type a value in \(request.spec.unit)"
        }
    }

    private func display(_ norm: Float) -> String {
        switch request.style {
        case .pan: return panText(norm)
        case .normal: return request.spec.display(norm)
        }
    }

    private var isFader: Bool {
        if case .fader = request.spec.scale { return true }
        return false
    }

    private func fineLabel(_ sign: Int) -> String {
        let s = sign < 0 ? "−" : "+"
        if isFader { return s + "0.1 dB" }
        return s
    }

    private func coarseLabel(_ sign: Int) -> String {
        let s = sign < 0 ? "−" : "+"
        if isFader { return s + "1 dB" }
        return s + s
    }

    private func nudge(_ norm: Float, coarse: Bool, up: Bool) {
        guard app.param(request.address).isKnown else { return }
        let sign: Float = up ? 1 : -1
        if isFader {
            let db = X32Math.faderToDB(norm)
            if db.isFinite && db > -89 {
                let next = db + sign * (coarse ? 1 : 0.1)
                var n = X32Math.dbToFader(next)
                // Make sure every press moves at least one desk step.
                let minimum = 1 / Float(request.spec.steps)
                if abs(n - norm) < minimum { n = norm + sign * minimum }
                set(n)
                return
            }
        }
        let step = 1 / Float(max(request.spec.steps, 1)) * (coarse ? 10 : 1)
        set(norm + sign * step)
    }

    private func set(_ norm: Float) {
        app.setFloat(request.address, min(max(norm, 0), 1), steps: request.spec.steps)
        Haptics.click()
    }

    private func applyText() {
        let parsed: Float?
        switch request.style {
        case .pan: parsed = ValueEditorCard.parsePan(text)
        case .normal: parsed = request.spec.parse(text)
        }
        guard let n = parsed else {
            invalid = true
            return
        }
        invalid = false
        set(n)
        text = ""
        typing = false
    }

    /// "L30", "R 15", "C", "-30", "30".
    static func parsePan(_ text: String) -> Float? {
        var t = text.trimmingCharacters(in: .whitespaces).uppercased()
        if t == "C" || t == "0" { return 0.5 }
        var sign: Float = 1
        if t.hasPrefix("L") { sign = -1; t.removeFirst() } else if t.hasPrefix("R") { t.removeFirst() }
        guard let v = Float(t.trimmingCharacters(in: .whitespaces)) else { return nil }
        let amount = min(max(sign * v, -100), 100)
        return X32Math.quantize((amount + 100) / 200, steps: 100)
    }
}

private struct StepKey: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16).monospacedDigit())
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised2))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }
}
