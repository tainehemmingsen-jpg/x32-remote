import SwiftUI
import UIKit

// MARK: - Raw touch tracking

/// A transparent UIKit view that reports one touch. Each surface tracks its own finger,
/// so several faders can be moved at once. It's a UIControl so scroll views don't steal its touches.
struct TouchSurface: UIViewRepresentable {
    var onBegin: (CGPoint) -> Void = { _ in }
    var onMove: (CGPoint) -> Void = { _ in }
    /// (moved, tapCount)
    var onEnd: (Bool, Int) -> Void = { _, _ in }

    func makeUIView(context: Context) -> TouchControl {
        let view = TouchControl()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isMultipleTouchEnabled = false
        return view
    }

    func updateUIView(_ view: TouchControl, context: Context) {
        view.onBegin = onBegin
        view.onMove = onMove
        view.onEnd = onEnd
    }

    final class TouchControl: UIControl {
        var onBegin: ((CGPoint) -> Void)?
        var onMove: ((CGPoint) -> Void)?
        var onEnd: ((Bool, Int) -> Void)?
        private var activeTouch: UITouch?
        private var startPoint: CGPoint = .zero
        private var moved = false

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard activeTouch == nil, let touch = touches.first else { return }
            activeTouch = touch
            moved = false
            startPoint = touch.location(in: self)
            onBegin?(startPoint)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = activeTouch, touches.contains(touch) else { return }
            let p = touch.location(in: self)
            if !moved && hypot(p.x - startPoint.x, p.y - startPoint.y) > 4 {
                moved = true
            }
            onMove?(p)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = activeTouch, touches.contains(touch) else { return }
            activeTouch = nil
            onEnd?(moved, touch.tapCount)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = activeTouch, touches.contains(touch) else { return }
            activeTouch = nil
            onEnd?(true, 0)
        }
    }
}

enum Haptics {
    static func tick() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    static func click() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

// MARK: - Vertical fader

/// dB marks drawn beside faders.
private let faderMarks: [(Float, String)] = [
    (10, "+10"), (5, "+5"), (0, "0"), (-5, "-5"), (-10, "-10"),
    (-20, "-20"), (-30, "-30"), (-40, "-40"), (-60, "-60")
]

/// A desk-style vertical fader. Drag anywhere on it (no jump); slide sideways off the strip for fine control.
struct FaderView: View {
    let value: Float
    var tint: Color = Theme.accent
    var maxValue: Float = 1
    var showScale: Bool = true
    var hapticAtUnity: Bool = true
    var capLabel: String? = nil
    let onChange: (Float) -> Void
    var onTouch: (Bool) -> Void = { _ in }

    @State private var dragValue: Float = 0
    @State private var lastPoint: CGPoint = .zero
    @State private var touching = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let capHeight = min(48, max(30, height * 0.085))
            let travel = max(1, height - capHeight)
            let clamped = CGFloat(min(max(value, 0), 1))
            let capCenterY = (1 - clamped) * travel + capHeight / 2
            let capWidth = min(width - 6, 56)
            ZStack {
                FaderTrack(value: value, tint: tint, capHeight: capHeight, showScale: showScale && width >= 54, maxValue: maxValue)
                FaderCap(touching: touching, tint: tint, label: capLabel)
                    .frame(width: capWidth, height: capHeight)
                    .position(x: width / 2, y: capCenterY)
            }
            .frame(width: width, height: height)
            .overlay(
                TouchSurface(
                    onBegin: { p in
                        touching = true
                        dragValue = value
                        lastPoint = p
                        onTouch(true)
                    },
                    onMove: { p in
                        let dy = p.y - lastPoint.y
                        lastPoint = p
                        let fine: CGFloat = abs(p.x - width / 2) > max(80, width) ? 0.25 : 1
                        var next = dragValue - Float(dy / travel * fine)
                        next = min(max(next, 0), maxValue)
                        let unity = X32Math.unityFader
                        if hapticAtUnity && ((dragValue < unity) != (next < unity)) {
                            Haptics.tick()
                        }
                        dragValue = next
                        onChange(next)
                    },
                    onEnd: { _, _ in
                        touching = false
                        onTouch(false)
                    }
                )
            )
        }
    }
}

private struct FaderTrack: View {
    let value: Float
    let tint: Color
    let capHeight: CGFloat
    let showScale: Bool
    let maxValue: Float

    var body: some View {
        let v = CGFloat(min(max(value, 0), 1))
        let limit = CGFloat(maxValue)
        Canvas { ctx, size in
            let travel = max(1, size.height - capHeight)
            let top = capHeight / 2
            let midX = size.width / 2
            func y(_ f: CGFloat) -> CGFloat { top + (1 - f) * travel }

            // groove
            let groove = CGRect(x: midX - 3, y: top - 2, width: 6, height: travel + 4)
            ctx.fill(Path(roundedRect: groove, cornerRadius: 3), with: .color(Color.black.opacity(0.65)))
            // level fill
            let fillRect = CGRect(x: midX - 3, y: y(v), width: 6, height: max(0, y(0) - y(v)))
            ctx.fill(Path(roundedRect: fillRect, cornerRadius: 3), with: .color(tint.opacity(0.55)))

            // limit marker (simple mode caps)
            if limit < 1 {
                let ly = y(limit)
                var p = Path()
                p.move(to: CGPoint(x: midX - 16, y: ly))
                p.addLine(to: CGPoint(x: midX + 16, y: ly))
                ctx.stroke(p, with: .color(Theme.mute.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            }

            // scale
            for mark in faderMarks {
                let f = CGFloat(X32Math.dbToFader(mark.0))
                let my = y(f)
                let isUnity = mark.0 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: midX - (isUnity ? 14 : 9), y: my))
                tick.addLine(to: CGPoint(x: midX - 5, y: my))
                tick.move(to: CGPoint(x: midX + 5, y: my))
                tick.addLine(to: CGPoint(x: midX + (isUnity ? 14 : 9), y: my))
                ctx.stroke(tick, with: .color(isUnity ? Color.white.opacity(0.7) : Color.white.opacity(0.25)), lineWidth: 1)
                if showScale {
                    let text = Text(mark.1)
                        .font(.system(size: 8, weight: isUnity ? .bold : .regular).monospacedDigit())
                        .foregroundColor(isUnity ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
                    ctx.draw(text, at: CGPoint(x: 2, y: my), anchor: .leading)
                }
            }
        }
    }
}

private struct FaderCap: View {
    let touching: Bool
    let tint: Color
    let label: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: touching ? 0.80 : 0.72), Color(white: touching ? 0.60 : 0.50), Color(white: touching ? 0.74 : 0.64)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.6), radius: 4, y: 3)
            RoundedRectangle(cornerRadius: 1)
                .fill(touching ? tint : Color.black.opacity(0.75))
                .frame(height: 3)
                .padding(.horizontal, 5)
            if let label = label {
                Text(label)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .offset(y: -11)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(touching ? tint : Color.white.opacity(0.25), lineWidth: touching ? 2 : 1)
        )
    }
}

// MARK: - Horizontal fader

/// Horizontal fader for sends, monitor mixes and phone layouts.
struct HFader: View {
    let value: Float
    var tint: Color = Theme.accent
    var maxValue: Float = 1
    var hapticAtUnity: Bool = true
    let onChange: (Float) -> Void
    var onTouch: (Bool) -> Void = { _ in }

    @State private var dragValue: Float = 0
    @State private var lastPoint: CGPoint = .zero
    @State private var touching = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let capWidth = min(36, max(24, height * 0.8))
            let travel = max(1, width - capWidth)
            let clamped = CGFloat(min(max(value, 0), 1))
            let capX = clamped * travel + capWidth / 2
            let unityX = CGFloat(X32Math.unityFader) * travel + capWidth / 2
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.6))
                    .frame(height: 6)
                    .padding(.horizontal, capWidth / 2 - 3)
                Capsule()
                    .fill(tint.opacity(0.6))
                    .frame(width: max(0, capX - capWidth / 2 + 6), height: 6)
                    .padding(.leading, capWidth / 2 - 3)
                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 1.5, height: height * 0.55)
                    .position(x: unityX, y: height / 2)
                if maxValue < 1 {
                    Rectangle()
                        .fill(Theme.mute.opacity(0.8))
                        .frame(width: 2, height: height * 0.7)
                        .position(x: CGFloat(maxValue) * travel + capWidth / 2, y: height / 2)
                }
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: touching ? 0.82 : 0.72), Color(white: touching ? 0.62 : 0.52)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Rectangle()
                            .fill(touching ? tint : Color.black.opacity(0.7))
                            .frame(width: 3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(touching ? tint : Color.white.opacity(0.25), lineWidth: touching ? 2 : 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .frame(width: capWidth, height: height - 6)
                    .position(x: capX, y: height / 2)
            }
            .frame(width: width, height: height)
            .overlay(
                TouchSurface(
                    onBegin: { p in
                        touching = true
                        dragValue = value
                        lastPoint = p
                        onTouch(true)
                    },
                    onMove: { p in
                        let dx = p.x - lastPoint.x
                        lastPoint = p
                        let fine: CGFloat = abs(p.y - height / 2) > max(70, height * 1.5) ? 0.25 : 1
                        var next = dragValue + Float(dx / travel * fine)
                        next = min(max(next, 0), maxValue)
                        let unity = X32Math.unityFader
                        if hapticAtUnity && ((dragValue < unity) != (next < unity)) {
                            Haptics.tick()
                        }
                        dragValue = next
                        onChange(next)
                    },
                    onEnd: { _, _ in
                        touching = false
                        onTouch(false)
                    }
                )
            )
        }
    }
}

// MARK: - Knob

private struct KnobArc: Shape {
    var from: Double
    var to: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = min(rect.width, rect.height) / 2 - 3
        p.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(135 + 270 * from),
            endAngle: .degrees(135 + 270 * to),
            clockwise: false
        )
        return p
    }
}

/// A rotary control: drag up/down to turn, double-tap to reset.
struct Knob: View {
    let title: String
    let value: Float
    let display: String
    var tint: Color = Theme.accent
    var bipolar: Bool = false
    var defaultValue: Float? = nil
    var enabled: Bool = true
    var size: CGFloat = 54
    let onChange: (Float) -> Void
    var onTouch: (Bool) -> Void = { _ in }

    @State private var dragValue: Float = 0
    @State private var lastPoint: CGPoint = .zero
    @State private var touching = false

    var body: some View {
        let v = Double(min(max(value, 0), 1))
        let arcFrom = bipolar ? min(0.5, v) : 0
        let arcTo = bipolar ? max(0.5, v) : v
        let pointerRotation = Angle.degrees(225 + 270 * v)
        VStack(spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [Theme.raised2, Theme.raised], center: .center, startRadius: 2, endRadius: size / 2)
                    )
                    .padding(8)
                KnobArc(from: 0, to: 1)
                    .stroke(Color.black.opacity(0.55), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                KnobArc(from: arcFrom, to: arcTo)
                    .stroke(enabled ? tint : Theme.tertiary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                Capsule()
                    .fill(touching ? tint : Theme.text)
                    .frame(width: 3, height: size * 0.2)
                    .offset(y: -size * 0.2)
                    .rotationEffect(pointerRotation)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .overlay(
                TouchSurface(
                    onBegin: { p in
                        touching = true
                        dragValue = value
                        lastPoint = p
                        onTouch(true)
                    },
                    onMove: { p in
                        let dy = lastPoint.y - p.y
                        let dx = p.x - lastPoint.x
                        lastPoint = p
                        var next = dragValue + Float((dy + dx * 0.5) / 220)
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
            Text(display)
                .font(Theme.mono(12))
                .foregroundStyle(enabled ? Theme.text : Theme.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: size + 10)
        .opacity(enabled ? 1 : 0.55)
    }
}

// MARK: - Meters

/// Maps dB to a 0...1 meter position.
enum MeterScale {
    static func position(_ db: Float) -> CGFloat {
        if db <= -60 { return 0 }
        if db >= 0 { return 1 }
        // A little more resolution near the top, like the desk's LEDs.
        let lin = (db + 60) / 60
        return CGFloat(powf(lin, 1.35))
    }
}

/// A vertical level meter (mono or stereo).
struct MeterView: View {
    let meter: MeterLevel
    var stereo: Bool = false

    var body: some View {
        let left = meter.level
        let right = meter.level2
        Canvas { ctx, size in
            let bars = stereo ? 2 : 1
            let gap: CGFloat = stereo ? 2 : 0
            let barWidth = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
            for i in 0..<bars {
                let db = i == 0 ? left : right
                let x = CGFloat(i) * (barWidth + gap)
                let full = CGRect(x: x, y: 0, width: barWidth, height: size.height)
                ctx.fill(Path(roundedRect: full, cornerRadius: 1.5), with: .color(Color.black.opacity(0.55)))
                let pos = MeterScale.position(db)
                if pos <= 0 { continue }
                let yellowStart = MeterScale.position(-12)
                let redStart = MeterScale.position(-3)
                func band(_ from: CGFloat, _ to: CGFloat, _ color: Color) {
                    let a = min(pos, from)
                    let b = min(pos, to)
                    guard b > a else { return }
                    let rect = CGRect(x: x, y: size.height * (1 - b), width: barWidth, height: size.height * (b - a))
                    ctx.fill(Path(rect), with: .color(color))
                }
                band(0, yellowStart, Theme.meterLow)
                band(yellowStart, redStart, Theme.meterMid)
                band(redStart, 1, Theme.meterHigh)
            }
        }
    }
}

/// A horizontal gain-reduction bar (grows right-to-left).
struct ReductionMeter: View {
    let meter: MeterLevel
    var gate: Bool = false

    var body: some View {
        let reduction = gate ? meter.gateReduction : meter.dynReduction
        HStack(spacing: 8) {
            Text("GR")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.secondary)
            GeometryReader { geo in
                let fraction = CGFloat(min(reduction, 30) / 30)
                ZStack(alignment: .trailing) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.55))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gate ? Theme.on : Theme.accent)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
            Text(reduction < 0.5 ? "0" : String(format: "-%.0f", reduction))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

// MARK: - Pan

/// A compact pan control: drag sideways, double-tap to centre.
struct PanControl: View {
    let value: Float
    var tint: Color = Theme.accent
    var height: CGFloat = 22
    let onChange: (Float) -> Void
    var onTouch: (Bool) -> Void = { _ in }

    @State private var dragValue: Float = 0.5
    @State private var lastPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let v = CGFloat(min(max(value, 0), 1))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.5))
                Rectangle()
                    .fill(tint.opacity(0.8))
                    .frame(width: max(2, abs(v - 0.5) * width), height: height - 8)
                    .offset(x: v >= 0.5 ? width / 2 : v * width)
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 1, height: height)
                    .offset(x: width / 2)
                Circle()
                    .fill(Theme.text)
                    .frame(width: 8, height: 8)
                    .offset(x: v * (width - 8))
            }
            .frame(width: width, height: height)
            .overlay(
                TouchSurface(
                    onBegin: { p in
                        dragValue = value
                        lastPoint = p
                        onTouch(true)
                    },
                    onMove: { p in
                        let dx = p.x - lastPoint.x
                        lastPoint = p
                        var next = dragValue + Float(dx / max(60, width * 1.5))
                        next = min(max(next, 0), 1)
                        if (dragValue < 0.5) != (next < 0.5) {
                            Haptics.tick()
                        }
                        dragValue = next
                        onChange(next)
                    },
                    onEnd: { moved, taps in
                        onTouch(false)
                        if !moved && taps >= 2 {
                            onChange(0.5)
                        }
                    }
                )
            )
        }
        .frame(height: height)
    }
}

/// "L32", "C", "R70" style pan text.
func panText(_ v: Float) -> String {
    let p = Int(((v - 0.5) * 200).rounded())
    if abs(p) < 1 { return "C" }
    return p < 0 ? "L\(-p)" : "R\(p)"
}
