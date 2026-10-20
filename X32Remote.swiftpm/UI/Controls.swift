import SwiftUI
import UIKit

// MARK: - Raw touch tracking

/// A transparent UIKit view that reports one touch. Each surface tracks its own finger,
/// so several faders can be moved at once. It's a UIControl so scroll views don't steal its touches.
struct TouchSurface: UIViewRepresentable {
    /// When set, a touch that starts moving mostly across this axis is ignored (so scrolling past a
    /// fader can't nudge it).
    var axis: Axis? = nil
    /// Holding still for half a second (e.g. to open the precision editor).
    var onLongPress: (() -> Void)? = nil
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
        view.axis = axis
        view.onBegin = onBegin
        view.onMove = onMove
        view.onEnd = onEnd
        view.onLongPress = onLongPress
    }

    final class TouchControl: UIControl {
        var onBegin: ((CGPoint) -> Void)?
        var onMove: ((CGPoint) -> Void)?
        var onEnd: ((Bool, Int) -> Void)?
        var onLongPress: (() -> Void)?
        var axis: Axis?
        private var longPressWork: DispatchWorkItem?
        private var longPressed = false
        private var activeTouch: UITouch?
        private var startPoint: CGPoint = .zero
        private var moved = false
        private var directionDecided = false
        private var ignoringMoves = false

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard activeTouch == nil, let touch = touches.first else { return }
            activeTouch = touch
            moved = false
            directionDecided = axis == nil
            ignoringMoves = false
            longPressed = false
            startPoint = touch.location(in: self)
            onBegin?(startPoint)
            if onLongPress != nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.activeTouch === touch, !self.moved else { return }
                    self.longPressed = true
                    Haptics.tick()
                    self.onLongPress?()
                }
                longPressWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = activeTouch, touches.contains(touch) else { return }
            let p = touch.location(in: self)
            let dx = abs(p.x - startPoint.x)
            let dy = abs(p.y - startPoint.y)
            if !moved && hypot(dx, dy) > 4 {
                moved = true
                longPressWork?.cancel()
            }
            if longPressed { return }
            if !directionDecided {
                guard hypot(dx, dy) >= 6 else { return }
                directionDecided = true
                if axis == .horizontal {
                    ignoringMoves = dy > dx * 1.2
                } else if axis == .vertical {
                    ignoringMoves = dx > dy * 1.2
                }
            }
            if ignoringMoves { return }
            onMove?(p)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = activeTouch, touches.contains(touch) else { return }
            activeTouch = nil
            longPressWork?.cancel()
            onEnd?(moved || longPressed, longPressed ? 0 : touch.tapCount)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = activeTouch, touches.contains(touch) else { return }
            activeTouch = nil
            longPressWork?.cancel()
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
    (10, "10"), (5, "5"), (0, "0"), (-5, "-5"), (-10, "-10"),
    (-20, "-20"), (-30, "-30"), (-50, "-50")
]

/// A console fader: a scale on the left, a thin slot, and a grey cap. Drag anywhere on it (the cap
/// never jumps to your finger). Slide sideways off the strip for extra-fine control.
struct FaderView: View {
    let value: Float
    var tint: Color = Theme.accent
    var maxValue: Float = 1
    var showScale: Bool = true
    var hapticAtUnity: Bool = true
    var capLabel: String? = nil
    /// Fine mode: 4x slower.
    var fine: Bool = false
    /// Red cap, e.g. for gain-on-fader or sends.
    var capTint: Color? = nil
    /// Double-tap (without moving) opens the precision editor. Not long-press: engineers often
    /// rest a finger on a fader.
    var onLongPress: (() -> Void)? = nil
    let onChange: (Float) -> Void
    var onTouch: (Bool) -> Void = { _ in }

    @State private var dragValue: Float = 0
    @State private var lastPoint: CGPoint = .zero
    @State private var touching = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let scaleWidth: CGFloat = showScale && width >= 34 ? min(18, width * 0.34) : 0
            let capHeight = min(44, max(26, height * 0.095))
            let travel = max(1, height - capHeight)
            let clamped = CGFloat(min(max(value, 0), 1))
            let capCenterY = (1 - clamped) * travel + capHeight / 2
            let trackX = scaleWidth + (width - scaleWidth) / 2
            let capWidth = max(18, min(width - scaleWidth - 4, 46))
            ZStack {
                FaderTrack(capHeight: capHeight, scaleWidth: scaleWidth, trackX: trackX, maxValue: maxValue)
                FaderCap(touching: touching, tint: capTint, label: capLabel)
                    .frame(width: capWidth, height: capHeight)
                    .position(x: trackX, y: capCenterY)
            }
            .frame(width: width, height: height)
            .overlay(
                TouchSurface(
                    axis: .vertical,
                    onBegin: { p in
                        touching = true
                        dragValue = value
                        lastPoint = p
                        onTouch(true)
                    },
                    onMove: { p in
                        let dy = p.y - lastPoint.y
                        lastPoint = p
                        let sideways: CGFloat = abs(p.x - width / 2) > max(80, width) ? 0.25 : 1
                        let fine: CGFloat = sideways * (self.fine ? 0.25 : 1)
                        // Never let a short fader become hair-trigger: at least 150 pt per full throw.
                        var next = dragValue - Float(dy / max(travel, 150) * fine)
                        next = min(max(next, 0), maxValue)
                        let unity = X32Math.unityFader
                        if hapticAtUnity && ((dragValue < unity) != (next < unity)) {
                            Haptics.tick()
                        }
                        dragValue = next
                        onChange(next)
                    },
                    onEnd: { moved, taps in
                        touching = false
                        onTouch(false)
                        if !moved && taps == 2 {
                            onLongPress?()
                        }
                    }
                )
            )
        }
        .onDisappear {
            if touching {
                touching = false
                onTouch(false)
            }
        }
    }
}

private struct FaderTrack: View {
    let capHeight: CGFloat
    let scaleWidth: CGFloat
    let trackX: CGFloat
    let maxValue: Float

    var body: some View {
        let limit = CGFloat(maxValue)
        Canvas { ctx, size in
            let travel = max(1, size.height - capHeight)
            let top = capHeight / 2
            func y(_ f: CGFloat) -> CGFloat { top + (1 - f) * travel }

            // marks
            for mark in faderMarks {
                let my = y(CGFloat(X32Math.dbToFader(mark.0)))
                let isUnity = mark.0 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: trackX - (isUnity ? 13 : 10), y: my))
                tick.addLine(to: CGPoint(x: trackX + (isUnity ? 13 : 10), y: my))
                ctx.stroke(tick, with: .color(isUnity ? Color.white.opacity(0.85) : Color.white.opacity(0.32)), lineWidth: isUnity ? 1.5 : 1)
                if scaleWidth > 0 {
                    let text = Text(mark.1)
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundColor(Color.white.opacity(0.5))
                    ctx.draw(text, at: CGPoint(x: scaleWidth - 1, y: my), anchor: .trailing)
                }
            }
            // slot
            let slot = CGRect(x: trackX - 2.5, y: top - 2, width: 5, height: travel + 4)
            ctx.fill(Path(roundedRect: slot, cornerRadius: 2.5), with: .color(Color.black))

            if limit < 1 {
                let ly = y(limit)
                var p = Path()
                p.move(to: CGPoint(x: trackX - 16, y: ly))
                p.addLine(to: CGPoint(x: trackX + 16, y: ly))
                ctx.stroke(p, with: .color(Theme.mute.opacity(0.9)), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            }
        }
    }
}

private struct FaderCap: View {
    let touching: Bool
    let tint: Color?
    let label: String?

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let base = tint
            let shades: [Color] = base.map { c in [c.opacity(0.95), c.opacity(0.7), c.opacity(0.95)] }
                ?? [Color(white: touching ? 0.86 : 0.78), Color(white: touching ? 0.62 : 0.52), Color(white: touching ? 0.80 : 0.70)]
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 3),
                with: .linearGradient(Gradient(colors: shades), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height))
            )
            // grip grooves
            let grooves = 6
            for i in 0..<grooves {
                let gy = size.height * (CGFloat(i) + 0.5) / CGFloat(grooves)
                if abs(gy - size.height / 2) < 3 { continue }
                var g = Path()
                g.move(to: CGPoint(x: 2, y: gy))
                g.addLine(to: CGPoint(x: size.width - 2, y: gy))
                ctx.stroke(g, with: .color(Color.black.opacity(0.22)), lineWidth: 1)
            }
            // centre line
            ctx.fill(Path(CGRect(x: 2, y: size.height / 2 - 1, width: size.width - 4, height: 2)), with: .color(touching ? Theme.accent : Color.white))
            ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3), with: .color(Color.black.opacity(0.5)), lineWidth: 1)
            if let label {
                ctx.draw(Text(label).font(.system(size: 7, weight: .bold)).foregroundColor(Color.black.opacity(0.6)), at: CGPoint(x: size.width / 2, y: size.height * 0.22))
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
    }
}

// MARK: - Horizontal fader

/// Horizontal fader for sends, monitor mixes and phone layouts.
struct HFader: View {
    let value: Float
    var tint: Color = Theme.accent
    var maxValue: Float = 1
    var hapticAtUnity: Bool = true
    var fine: Bool = false
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
                        let sideways: CGFloat = abs(p.y - height / 2) > max(70, height * 1.5) ? 0.25 : 1
                        let fine: CGFloat = sideways * (self.fine ? 0.25 : 1)
                        // Never let a short fader become hair-trigger: at least 150 pt per full throw.
                        var next = dragValue + Float(dx / max(travel, 150) * fine)
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
        .onDisappear {
            if touching {
                touching = false
                onTouch(false)
            }
        }
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

    /// Green to yellow at +4 dBu (-14 dBFS on an X32), red just below clipping.
    static let yellowFrom: Float = -14
    static let redFrom: Float = -2
}

/// A vertical level meter (mono or stereo): unlit segments show dimly, like LED bars.
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
            let yellow = MeterScale.position(MeterScale.yellowFrom)
            let red = MeterScale.position(MeterScale.redFrom)
            let bands: [(CGFloat, CGFloat, Color)] = [(0, yellow, Theme.meterLow), (yellow, red, Theme.meterMid), (red, 1, Theme.meterHigh)]
            for i in 0..<bars {
                let db = i == 0 ? left : right
                let x = CGFloat(i) * (barWidth + gap)
                let pos = MeterScale.position(db)
                ctx.fill(Path(CGRect(x: x, y: 0, width: barWidth, height: size.height)), with: .color(Color.black))
                for band in bands {
                    let dim = CGRect(x: x, y: size.height * (1 - band.1), width: barWidth, height: size.height * (band.1 - band.0))
                    ctx.fill(Path(dim), with: .color(band.2.opacity(0.17)))
                    let a = min(pos, band.0)
                    let b = min(pos, band.1)
                    if b > a {
                        let lit = CGRect(x: x, y: size.height * (1 - b), width: barWidth, height: size.height * (b - a))
                        ctx.fill(Path(lit), with: .color(band.2))
                    }
                }
            }
        }
    }
}

/// Gain reduction as a red bar growing down from the top.
struct GRBar: View {
    let reduction: Float

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.mute.opacity(0.14)))
            let fraction = CGFloat(min(max(reduction, 0), 24) / 24)
            if fraction > 0.01 {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height * fraction)), with: .color(Theme.mute))
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
                    RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.55))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.mute)
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

/// A pan box: white line at the position and a blue wedge from the centre. Drag sideways,
/// double-tap to centre.
struct PanControl: View {
    let value: Float
    var tint: Color = Theme.accent
    var height: CGFloat = 22
    var fine: Bool = false
    var onLongPress: (() -> Void)? = nil
    let onChange: (Float) -> Void
    var onTouch: (Bool) -> Void = { _ in }

    @State private var dragValue: Float = 0.5
    @State private var lastPoint: CGPoint = .zero
    @State private var touching = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let v = CGFloat(min(max(value, 0), 1))
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color.black.opacity(0.35)))
                ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3), with: .color(touching ? tint : Color.white.opacity(0.16)), lineWidth: 1)
                let inset: CGFloat = 4
                let cx = size.width / 2
                let px = inset + v * (size.width - inset * 2)
                if abs(px - cx) > 1 {
                    var wedge = Path()
                    let h = size.height - 3
                    let rise = h * min(1, abs(v - 0.5) * 2) * 0.85
                    wedge.move(to: CGPoint(x: cx, y: h))
                    wedge.addLine(to: CGPoint(x: px, y: h))
                    wedge.addLine(to: CGPoint(x: px, y: h - rise))
                    wedge.closeSubpath()
                    ctx.fill(wedge, with: .color(tint))
                }
                ctx.fill(Path(CGRect(x: px - 1, y: 3, width: 2, height: size.height - 6)), with: .color(Color.white))
            }
            .frame(width: width, height: height)
            .overlay(
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
                        var next = dragValue + Float(dx / max(90, width * 1.5) * (fine ? 0.25 : 1))
                        next = min(max(next, 0), 1)
                        if (dragValue < 0.5) != (next < 0.5) {
                            Haptics.tick()
                        }
                        dragValue = next
                        onChange(next)
                    },
                    onEnd: { moved, taps in
                        touching = false
                        onTouch(false)
                        if !moved && taps >= 2 {
                            onChange(0.5)
                        }
                    }
                )
            )
        }
        .frame(height: height)
        .onDisappear {
            if touching {
                touching = false
                onTouch(false)
            }
        }
    }
}

/// "L32", "C", "R70" style pan text.
func panText(_ v: Float) -> String {
    let p = Int(((v - 0.5) * 200).rounded())
    if abs(p) < 1 { return "C" }
    return p < 0 ? "L\(-p)" : "R\(p)"
}
