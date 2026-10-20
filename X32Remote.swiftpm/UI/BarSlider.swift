import SwiftUI

/// A parameter slider: name on the left, value on the right, and a filled bar underneath.
/// Drag left/right anywhere on it (it never jumps to your finger); double-tap resets when allowed.
struct BarSlider: View {
    let title: String
    let value: Float
    let display: String
    var tint: Color = Theme.accent
    var bipolar: Bool = false
    var enabled: Bool = true
    var fine: Bool = false
    /// Normalised amount one − / + tap moves (only used when `steppers` is on).
    var step: Float = 0.01
    /// Double-tap target, or nil to disable double-tap reset.
    var defaultValue: Float? = nil
    /// Height of the bar itself.
    var height: CGFloat = 20
    var steppers: Bool = false
    var onLongPress: (() -> Void)? = nil
    let onChange: (Float) -> Void
    var onTouch: (Bool) -> Void = { _ in }

    @State private var dragValue: Float = 0
    @State private var lastPoint: CGPoint = .zero
    @State private var touching = false

    var body: some View {
        HStack(spacing: 6) {
            if steppers {
                StepButton(symbol: "minus") {
                    onChange(min(max(value - step, 0), 1))
                }
            }
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(display)
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(.system(size: 13))
                bar
            }
            .contentShape(Rectangle())
            .overlay(touchLayer)
            if steppers {
                StepButton(symbol: "plus") {
                    onChange(min(max(value + step, 0), 1))
                }
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
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.black.opacity(0.3))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tint)
                    .frame(width: max(bipolar ? 2 : 0, (fillEnd - fillStart) * width))
                    .offset(x: fillStart * width)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(touching ? Theme.text : Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .frame(minWidth: 80)
        .frame(height: height)
    }

    private var touchLayer: some View {
        GeometryReader { geo in
            let width = geo.size.width
            TouchSurface(
                axis: .horizontal,
                onLongPress: onLongPress,
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
        }
    }
}

private struct StepButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 36, height: 40)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.raised))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }
}

/// Grid that lays parameter sliders out two or three across, depending on width.
struct ControlGrid<Content: View>: View {
    var minimumWidth: CGFloat = 220
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 16)], alignment: .leading, spacing: 12) {
            content
        }
    }
}
