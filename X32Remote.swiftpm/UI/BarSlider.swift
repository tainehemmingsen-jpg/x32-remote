import SwiftUI

/// A big horizontal parameter bar: drag anywhere on it left/right (it never jumps to your finger),
/// or tap − / + for one step. Much easier on a touchscreen than a rotary knob.
struct BarSlider: View {
    let title: String
    let value: Float
    let display: String
    var tint: Color = Theme.accent
    var bipolar: Bool = false
    var enabled: Bool = true
    var fine: Bool = false
    /// Normalised amount one − / + tap moves.
    var step: Float = 0.01
    /// Double-tap target, or nil to disable double-tap reset.
    var defaultValue: Float? = nil
    var height: CGFloat = 46
    let onChange: (Float) -> Void
    var onTouch: (Bool) -> Void = { _ in }

    @State private var dragValue: Float = 0
    @State private var lastPoint: CGPoint = .zero
    @State private var touching = false

    var body: some View {
        HStack(spacing: 6) {
            StepButton(symbol: "minus", height: height) {
                onChange(min(max(value - step, 0), 1))
            }
            bar
            StepButton(symbol: "plus", height: height) {
                onChange(min(max(value + step, 0), 1))
            }
        }
        .opacity(enabled ? 1 : 0.45)
        .onDisappear {
            if touching {
                touching = false
                onTouch(false)
            }
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let v = CGFloat(min(max(value, 0), 1))
            let fillStart = bipolar ? min(v, 0.5) : 0
            let fillEnd = bipolar ? max(v, 0.5) : v
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.raised)
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(touching ? 0.55 : 0.38))
                    .frame(width: max(0, (fillEnd - fillStart) * width))
                    .offset(x: fillStart * width)
                Rectangle()
                    .fill(touching ? Theme.text : tint)
                    .frame(width: 3)
                    .offset(x: min(max(v * width - 1.5, 0), width - 3))
                HStack {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(display)
                        .font(Theme.mono(15, .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(touching ? tint : Theme.line, lineWidth: touching ? 2 : 1)
            )
            .frame(width: width, height: geo.size.height)
            .overlay(
                TouchSurface(
                    axis: .horizontal,
                    onBegin: { p in
                        touching = true
                        dragValue = value
                        lastPoint = p
                        onTouch(true)
                    },
                    onMove: { p in
                        let dx = p.x - lastPoint.x
                        lastPoint = p
                        // One full sweep is at least 260 pt, so small adjustments are easy.
                        let span = max(width, 260)
                        var next = dragValue + Float(dx / span) * (fine ? 0.25 : 1)
                        next = min(max(next, 0), 1)
                        dragValue = next
                        onChange(next)
                    },
                    onEnd: { moved, taps in
                        touching = false
                        onTouch(false)
                        if !moved && taps >= 2, let d = defaultValue {
                            onChange(d)
                        }
                    }
                )
            )
        }
        .frame(minWidth: 150)
        .frame(height: height)
    }
}

private struct StepButton: View {
    let symbol: String
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 40, height: height)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised2))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }
}

/// Grid that lays parameter bars out two or three across, depending on width.
struct ControlGrid<Content: View>: View {
    var minimumWidth: CGFloat = 260
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 12)], alignment: .leading, spacing: 10) {
            content
        }
    }
}
