import SwiftUI

// Hardware-style "rack units" for the effects: each family of effects gets its own faceplate
// (reverbs as slide-fader units, delays and modulation as knob units with a display, dynamics
// as a silver panel, amps as a black-and-gold amp head…). All drawn here, no images.

// MARK: - Families and looks

enum FXFamily {
    case reverb, delay, modulation, dynamics, eq, character, amp

    static func of(_ code: String) -> FXFamily {
        switch code {
        case "HALL", "AMBI", "RPLT", "ROOM", "CHAM", "PLAT", "VREV", "VRM", "GATE", "RVRS": return .reverb
        case "DLY", "3TAP", "4TAP", "MODD", "D/RV", "D/CR", "D/FL": return .delay
        case "CRS", "FLNG", "PHAS", "DIMC", "FILT", "ROTA", "PAN", "SUB", "CR/R", "FL/R", "PIT", "PIT2": return .modulation
        case "DES", "DES2", "WAVD", "LIM", "CMB", "CMB2", "FAC", "FAC1M", "FAC2", "LEC", "LEC2", "ULC", "ULC2": return .dynamics
        case "GEQ", "GEQ2", "TEQ", "TEQ2", "P1A", "P1A2", "PQ5", "PQ5S": return .eq
        case "AMP", "AMP2", "DRV", "DRV2": return .amp
        default: return .character
        }
    }

    var look: RackLook {
        switch self {
        case .reverb:
            return RackLook(panelTop: Color(red: 0.16, green: 0.17, blue: 0.19), panelBottom: Color(red: 0.09, green: 0.10, blue: 0.11),
                            accent: Color(red: 0.95, green: 0.62, blue: 0.20), text: Color(white: 0.88), lcd: Color(red: 1.0, green: 0.70, blue: 0.25),
                            knobLight: false, usesFaders: true)
        case .delay:
            return RackLook(panelTop: Color(red: 0.10, green: 0.13, blue: 0.18), panelBottom: Color(red: 0.05, green: 0.07, blue: 0.10),
                            accent: Color(red: 0.25, green: 0.70, blue: 1.0), text: Color(white: 0.88), lcd: Color(red: 0.35, green: 0.85, blue: 1.0),
                            knobLight: false, usesFaders: false)
        case .modulation:
            return RackLook(panelTop: Color(red: 0.17, green: 0.11, blue: 0.20), panelBottom: Color(red: 0.09, green: 0.06, blue: 0.11),
                            accent: Color(red: 0.80, green: 0.45, blue: 1.0), text: Color(white: 0.9), lcd: Color(red: 0.85, green: 0.60, blue: 1.0),
                            knobLight: false, usesFaders: false)
        case .dynamics:
            return RackLook(panelTop: Color(white: 0.74), panelBottom: Color(white: 0.56),
                            accent: Color(red: 0.75, green: 0.12, blue: 0.10), text: Color(white: 0.10), lcd: Color(red: 1.0, green: 0.30, blue: 0.20),
                            knobLight: false, usesFaders: false)
        case .eq:
            return RackLook(panelTop: Color(red: 0.22, green: 0.28, blue: 0.34), panelBottom: Color(red: 0.14, green: 0.18, blue: 0.22),
                            accent: Color(red: 0.95, green: 0.90, blue: 0.75), text: Color(white: 0.92), lcd: Color(red: 0.55, green: 1.0, blue: 0.55),
                            knobLight: true, usesFaders: false)
        case .amp:
            return RackLook(panelTop: Color(white: 0.11), panelBottom: Color(white: 0.04),
                            accent: Color(red: 0.86, green: 0.70, blue: 0.36), text: Color(red: 0.92, green: 0.82, blue: 0.58), lcd: Color(red: 1.0, green: 0.55, blue: 0.20),
                            knobLight: true, usesFaders: false)
        case .character:
            return RackLook(panelTop: Color(red: 0.12, green: 0.18, blue: 0.15), panelBottom: Color(red: 0.06, green: 0.10, blue: 0.08),
                            accent: Color(red: 0.40, green: 0.95, blue: 0.60), text: Color(white: 0.9), lcd: Color(red: 0.45, green: 1.0, blue: 0.65),
                            knobLight: false, usesFaders: false)
        }
    }
}

struct RackLook {
    let panelTop: Color
    let panelBottom: Color
    let accent: Color
    let text: Color
    let lcd: Color
    /// Silver/cream knob caps instead of black ones.
    let knobLight: Bool
    /// Main settings as slide faders (reverbs) rather than knobs.
    let usesFaders: Bool
}

// MARK: - The rack unit frame

/// A rack unit: ears with screws, a panel, and the effect's name on it.
struct RackUnit<Content: View>: View {
    let title: String
    let code: String
    let look: RackLook
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            RackEar()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title.uppercased())
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .italic()
                        .tracking(1)
                        .foregroundStyle(look.text.opacity(0.92))
                        .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Rectangle()
                        .fill(look.accent)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .offset(y: -6)
                    Text(code)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(look.accent)
                }
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [look.panelTop, look.panelBottom], startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                // Brushed texture: faint horizontal lines.
                Canvas { ctx, size in
                    var y: CGFloat = 0
                    while y < size.height {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)), with: .color(Color.white.opacity(0.025)))
                        y += 3
                    }
                }
                .allowsHitTesting(false)
            )
            RackEar()
        }
        // Ears run the full height of the panel even inside a scroll view.
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.8), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
    }
}

private struct RackEar: View {
    var body: some View {
        VStack {
            Screw()
            Spacer()
            Screw()
        }
        .padding(.vertical, 10)
        .frame(width: 26)
        .frame(maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.18)], startPoint: .leading, endPoint: .trailing))
    }
}

private struct Screw: View {
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(white: 0.75), Color(white: 0.35)], center: .topLeading, startRadius: 1, endRadius: 10))
            Rectangle().fill(Color.black.opacity(0.6)).frame(width: 9, height: 1.5).rotationEffect(.degrees(35))
        }
        .frame(width: 11, height: 11)
        .accessibilityHidden(true)
    }
}

// MARK: - Faceplate

/// All of an effect's settings on its rack unit.
struct FXFaceplate: View {
    let app: AppModel
    let slot: Int
    let type: Int
    let params: [Effects.Param]

    var body: some View {
        let code = Effects.typeCode(slot: slot, type: type) ?? ""
        let family = FXFamily.of(code)
        let look = family.look
        let values = params.filter { if case .choice = $0.kind { return false } else { return true } }
        let choices = params.filter { if case .choice = $0.kind { return true } else { return false } }
        let faderCount = look.usesFaders ? min(values.count, 6) : 0
        let faders = Array(values.prefix(faderCount))
        let knobs = Array(values.dropFirst(faderCount))
        RackUnit(title: Effects.typeName(slot: slot, type: type), code: code, look: look) {
            if let timePar = Effects.tapTimeParameter(slot: slot, type: type) {
                RackTapDisplay(app: app, address: Effects.parPath(slot, timePar), look: look)
                    .id(slot)
            }
            if !faders.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(faders, id: \.number) { p in
                        RackParam(app: app, slot: slot, param: p, look: look, asFader: true)
                    }
                }
            }
            if !choices.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(choices, id: \.number) { p in
                        RackChoice(app: app, address: Effects.parPath(slot, p.number), name: p.name, options: choiceOptions(p), look: look)
                    }
                }
            }
            if !knobs.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .center, spacing: 14) {
                    ForEach(knobs, id: \.number) { p in
                        RackParam(app: app, slot: slot, param: p, look: look, asFader: false)
                    }
                }
            }
        }
    }

    private func choiceOptions(_ p: Effects.Param) -> [String] {
        if case .choice(let o) = p.kind { return o }
        return []
    }
}

private struct RackParam: View {
    let app: AppModel
    let slot: Int
    let param: Effects.Param
    let look: RackLook
    let asFader: Bool

    private static let percentSpec = ParamSpec(.linear(0, 100), steps: 1000, unit: "%", decimals: 0, defaultNorm: 0.5)

    var body: some View {
        let spec: ParamSpec = {
            switch param.kind {
            case .value(let s): return s
            default: return RackParam.percentSpec
            }
        }()
        let address = Effects.parPath(slot, param.number)
        if asFader {
            RackFader(app: app, address: address, name: param.name, spec: spec, look: look)
        } else {
            RackKnob(app: app, address: address, name: param.name, spec: spec, look: look)
        }
    }
}

// MARK: - Knob

/// A big rotary knob: drag up or down to turn it. Long-press to type a value.
struct RackKnob: View {
    let app: AppModel
    let address: String
    let name: String
    let spec: ParamSpec
    let look: RackLook
    var size: CGFloat = 68
    @State private var drag = DragTarget()
    @State private var start: Float = 0
    @State private var touching = false
    @State private var startPoint: CGPoint = .zero

    var body: some View {
        let p = app.param(address)
        let norm = CGFloat(min(max(p.float(or: spec.defaultNorm), 0), 1))
        VStack(spacing: 5) {
            Text(name.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(look.text.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let r = min(sz.width, sz.height) / 2
                // Scale: 270° arc of ticks.
                for i in 0...10 {
                    let a = Angle.degrees(135 + 270 * Double(i) / 10).radians
                    let r1 = r - 1, r2 = r - (i % 5 == 0 ? 7 : 4)
                    var t = Path()
                    t.move(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
                    t.addLine(to: CGPoint(x: c.x + cos(a) * r2, y: c.y + sin(a) * r2))
                    ctx.stroke(t, with: .color(look.text.opacity(0.55)), lineWidth: 1)
                }
                // Lit arc up to the value.
                var arc = Path()
                arc.addArc(center: c, radius: r - 2.5, startAngle: .degrees(135), endAngle: .degrees(135 + 270 * Double(norm)), clockwise: false)
                ctx.stroke(arc, with: .color(look.accent.opacity(p.isKnown ? 0.9 : 0.2)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                // Knob body.
                let kr = r - 10
                let body = CGRect(x: c.x - kr, y: c.y - kr, width: kr * 2, height: kr * 2)
                let capColors: [Color] = look.knobLight ? [Color(white: 0.92), Color(white: 0.55)] : [Color(white: 0.32), Color(white: 0.06)]
                ctx.fill(Path(ellipseIn: body.offsetBy(dx: 0, dy: 2)), with: .color(.black.opacity(0.45)))
                ctx.fill(Path(ellipseIn: body), with: .radialGradient(Gradient(colors: capColors), center: CGPoint(x: c.x - kr * 0.35, y: c.y - kr * 0.45), startRadius: 1, endRadius: kr * 1.6))
                ctx.stroke(Path(ellipseIn: body.insetBy(dx: kr * 0.18, dy: kr * 0.18)), with: .color(Color.white.opacity(look.knobLight ? 0.35 : 0.08)), lineWidth: 1)
                // Pointer.
                let a = Angle.degrees(135 + 270 * Double(norm)).radians
                var pointer = Path()
                pointer.move(to: CGPoint(x: c.x + cos(a) * kr * 0.25, y: c.y + sin(a) * kr * 0.25))
                pointer.addLine(to: CGPoint(x: c.x + cos(a) * kr * 0.92, y: c.y + sin(a) * kr * 0.92))
                ctx.stroke(pointer, with: .color(look.knobLight ? Color.black.opacity(0.8) : Color.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            .frame(width: size, height: size)
            .overlay(
                TouchSurface(
                    onLongPress: { app.editValue(name, address, spec) },
                    onBegin: { pt in
                        touching = true
                        start = p.float(or: spec.defaultNorm)
                        startPoint = pt
                        app.beginDrag(address, drag)
                    },
                    onMove: { pt in
                        // Up (or right) turns it up.
                        let sensitivity: Float = app.fineMode ? 800 : 220
                        let delta = Float(-(pt.y - startPoint.y) + (pt.x - startPoint.x) * 0.5) / sensitivity
                        app.dragSet(address, drag, min(max(start + delta, 0), 1), steps: spec.steps)
                    },
                    onEnd: { _, _ in
                        touching = false
                        app.endDrag(drag)
                    }
                )
            )
            RackLCD(text: p.isKnown ? spec.display(p.float) : "—", look: look, active: touching)
        }
        .frame(minWidth: 92)
        .paramAccessibility(app: app, title: name, address: address, spec: spec)
    }
}

// MARK: - Fader

/// A slide fader with an LED ladder beside it, for the reverbs' main settings.
struct RackFader: View {
    let app: AppModel
    let address: String
    let name: String
    let spec: ParamSpec
    let look: RackLook
    var height: CGFloat = 250
    @State private var drag = DragTarget()
    @State private var start: Float = 0
    @State private var touching = false

    var body: some View {
        let p = app.param(address)
        let norm = CGFloat(min(max(p.float(or: spec.defaultNorm), 0), 1))
        VStack(spacing: 6) {
            Text(name.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(look.text.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Canvas { ctx, size in
                    let capH: CGFloat = 32
                    let travel = size.height - capH
                    let slotX = size.width / 2 + 6
                    // LED ladder on the left: lit up to the value.
                    let leds = 12
                    for i in 0..<leds {
                        let t = CGFloat(i) / CGFloat(leds - 1)
                        let y = capH / 2 + (1 - t) * travel
                        let lit = p.isKnown && t <= norm + 0.001
                        let led = CGRect(x: slotX - 27, y: y - 3.5, width: 7, height: 7)
                        ctx.fill(Path(ellipseIn: led), with: .color(lit ? look.accent : look.accent.opacity(0.15)))
                    }
                    // Slot.
                    let slot = CGRect(x: slotX - 3, y: capH / 2, width: 6, height: travel)
                    ctx.fill(Path(roundedRect: slot, cornerRadius: 3), with: .color(.black.opacity(0.85)))
                    ctx.stroke(Path(roundedRect: slot, cornerRadius: 3), with: .color(Color.white.opacity(0.12)), lineWidth: 1)
                    // Cap.
                    let capY = (1 - norm) * travel
                    let cap = CGRect(x: slotX - 17, y: capY, width: 34, height: capH)
                    ctx.fill(Path(roundedRect: cap.offsetBy(dx: 0, dy: 2), cornerRadius: 3), with: .color(.black.opacity(0.5)))
                    ctx.fill(Path(roundedRect: cap, cornerRadius: 3), with: .linearGradient(
                        Gradient(colors: [Color(white: 0.92), Color(white: 0.62), Color(white: 0.80)]),
                        startPoint: CGPoint(x: cap.midX, y: cap.minY), endPoint: CGPoint(x: cap.midX, y: cap.maxY)))
                    ctx.fill(Path(CGRect(x: cap.minX + 3, y: cap.midY - 1, width: cap.width - 6, height: 2)), with: .color(touching ? look.accent : Color.black.opacity(0.75)))
                }
                .frame(width: w, height: h)
                .overlay(
                    TouchSurface(
                        axis: .vertical,
                        onLongPress: { app.editValue(name, address, spec) },
                        onBegin: { pt in
                            touching = true
                            start = p.float(or: spec.defaultNorm)
                            app.beginDrag(address, drag)
                            lastY = pt.y
                            accumulated = 0
                        },
                        onMove: { pt in
                            accumulated += pt.y - lastY
                            lastY = pt.y
                            let travel = max(h - 32, 40)
                            let delta = Float(-accumulated / travel) * (app.fineMode ? 0.25 : 1)
                            app.dragSet(address, drag, min(max(start + delta, 0), 1), steps: spec.steps)
                        },
                        onEnd: { _, _ in
                            touching = false
                            app.endDrag(drag)
                        }
                    )
                )
            }
            .frame(height: height)
            RackLCD(text: p.isKnown ? spec.display(p.float) : "—", look: look, active: touching)
        }
        .frame(minWidth: 40, maxWidth: .infinity)
        .paramAccessibility(app: app, title: name, address: address, spec: spec)
    }

    @State private var lastY: CGFloat = 0
    @State private var accumulated: CGFloat = 0
}

// MARK: - Display and switches

/// A small digital readout.
struct RackLCD: View {
    let text: String
    let look: RackLook
    var active = false
    var fontSize: CGFloat = 14

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
            .foregroundStyle(look.lcd)
            .shadow(color: look.lcd.opacity(0.6), radius: 3)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(active ? look.accent : Color.white.opacity(0.1), lineWidth: 1))
    }
}

/// An on/off setting as a toggle switch, a short list as LED buttons, a long list as a stepper display.
private struct RackChoice: View {
    let app: AppModel
    let address: String
    let name: String
    let options: [String]
    let look: RackLook

    var body: some View {
        let p = app.param(address)
        let current = p.int
        VStack(alignment: .leading, spacing: 5) {
            Text(name.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(look.text.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if options.count == 2 && (options.map { $0.uppercased() } == ["OFF", "ON"]) {
                Button {
                    guard p.isKnown else { return }
                    app.setInt(address, current == 0 ? 1 : 0)
                    Haptics.click()
                } label: {
                    HStack(spacing: 8) {
                        LED(on: p.isKnown && current == 1, color: look.accent)
                        Text(current == 1 ? "ON" : "OFF")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(look.text)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.35)))
                }
                .buttonStyle(.plain)
            } else if options.count <= 4 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(options.indices, id: \.self) { i in
                        Button {
                            guard p.isKnown, current != i else { return }
                            app.setInt(address, i)
                            Haptics.click()
                        } label: {
                            HStack(spacing: 8) {
                                LED(on: p.isKnown && current == i, color: look.accent)
                                Text(options[i])
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(look.text)
                                    .lineLimit(1)
                            }
                            .frame(minHeight: 26)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    StepButton(symbol: "chevron.left", look: look) {
                        if p.isKnown && current > 0 { app.setInt(address, current - 1) }
                    }
                    Menu {
                        ForEach(options.indices, id: \.self) { i in
                            Button(options[i]) { app.setInt(address, i) }
                        }
                    } label: {
                        RackLCD(text: p.isKnown && options.indices.contains(current) ? options[current] : "—", look: look)
                    }
                    StepButton(symbol: "chevron.right", look: look) {
                        if p.isKnown && current < options.count - 1 { app.setInt(address, current + 1) }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue(p.isKnown && options.indices.contains(current) ? options[current] : "not read yet")
    }
}

private struct StepButton: View {
    let symbol: String
    let look: RackLook
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(look.text)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }
}

struct LED: View {
    let on: Bool
    let color: Color

    var body: some View {
        Circle()
            .fill(on ? color : Color(white: 0.15))
            .overlay(Circle().fill(RadialGradient(colors: [Color.white.opacity(on ? 0.7 : 0.15), .clear], center: .topLeading, startRadius: 0, endRadius: 6)))
            .shadow(color: on ? color.opacity(0.9) : .clear, radius: 4)
            .frame(width: 10, height: 10)
    }
}

/// The delay time on a big display with a TAP button, inside the delay's rack unit.
private struct RackTapDisplay: View {
    let app: AppModel
    let address: String
    let look: RackLook
    @State private var tempo = TapTempo()
    @State private var flash = false

    private func tap() {
        let p = app.param(address)
        guard p.isKnown else { return }
        if let newMS = tempo.tap(at: ProcessInfo.processInfo.systemUptime) {
            app.setFloat(address, Effects.delayTimeSpec.norm(Float(newMS)), steps: Effects.delayTimeSpec.steps)
        }
        flash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.2)) { flash = false }
        }
    }

    var body: some View {
        let p = app.param(address)
        let ms = Double(Effects.delayTimeSpec.value(p.float))
        HStack(spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(p.isKnown ? "\(Int(ms.rounded())) ms" : "—")
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundStyle(look.lcd)
                    .shadow(color: look.lcd.opacity(0.6), radius: 4)
                Text(p.isKnown ? String(format: "%.1f BPM", TapTempo.bpm(ms: ms)) : " ")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(look.lcd.opacity(0.75))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minWidth: 120, alignment: .trailing)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            Text("TAP")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(flash ? Color.black : look.text)
                .frame(width: 96, height: 58)
                .background(RoundedRectangle(cornerRadius: 8).fill(flash ? look.accent : Color.black.opacity(0.4)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(look.accent, lineWidth: 2))
                .opacity(p.isKnown ? 1 : 0.4)
                .overlay(TouchSurface(onBegin: { _ in tap() }, onEnd: { _, _ in }, immediate: true))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tap tempo")
                .accessibilityHint("Tap repeatedly in time with the music to set the delay time")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { tap() }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Picker

/// Every effect a slot can hold, as little rack units, grouped. Tap one to choose it.
struct EffectPicker: View {
    let slot: Int
    let current: Int
    let choose: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Effects.typeMenu(slot: slot), id: \.0) { title, types in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                                ForEach(types, id: \.0) { value, name in
                                    Button {
                                        dismiss()
                                        if value != current { choose(value) }
                                    } label: {
                                        MiniRackUnit(code: Effects.typeCode(slot: slot, type: value) ?? "", name: name, selected: value == current)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(name + (value == current ? ", loaded" : ""))
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Choose an effect for FX \(slot)")
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

/// A small drawing of an effect's rack unit, for the picker and the slot list.
struct MiniRackUnit: View {
    let code: String
    let name: String
    var selected = false

    var body: some View {
        let family = FXFamily.of(code)
        let look = family.look
        VStack(spacing: 6) {
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .linearGradient(
                    Gradient(colors: [look.panelTop, look.panelBottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                // Ears and screws.
                for x in [CGFloat(0), size.width - 12] {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 12, height: size.height)), with: .color(Color(white: 0.25)))
                    for y in [CGFloat(8), size.height - 8] {
                        ctx.fill(Path(ellipseIn: CGRect(x: x + 3, y: y - 3, width: 6, height: 6)), with: .color(Color(white: 0.6)))
                    }
                }
                ctx.fill(Path(CGRect(x: 18, y: 10, width: size.width * 0.35, height: 2)), with: .color(look.accent))
                let inner = CGRect(x: 18, y: 18, width: size.width - 36, height: size.height - 26)
                switch family {
                case .reverb:
                    for i in 0..<6 {
                        let x = inner.minX + inner.width * (CGFloat(i) + 0.5) / 6
                        ctx.fill(Path(CGRect(x: x - 1.5, y: inner.minY, width: 3, height: inner.height)), with: .color(.black.opacity(0.8)))
                        let y = inner.minY + inner.height * CGFloat([0.3, 0.6, 0.45, 0.2, 0.55, 0.4][i])
                        ctx.fill(Path(roundedRect: CGRect(x: x - 7, y: y - 4, width: 14, height: 8), cornerRadius: 2), with: .color(Color(white: 0.85)))
                    }
                case .eq where code.hasPrefix("GEQ") || code.hasPrefix("TEQ"):
                    for i in 0..<16 {
                        let x = inner.minX + inner.width * (CGFloat(i) + 0.5) / 16
                        ctx.fill(Path(CGRect(x: x - 0.75, y: inner.minY, width: 1.5, height: inner.height)), with: .color(.black.opacity(0.8)))
                        let y = inner.midY + sin(CGFloat(i) * 0.7) * inner.height * 0.2
                        ctx.fill(Path(CGRect(x: x - 4, y: y - 2, width: 8, height: 4)), with: .color(Color(white: 0.85)))
                    }
                default:
                    if family == .delay || family == .modulation || family == .character {
                        let lcd = CGRect(x: inner.minX, y: inner.minY, width: inner.width * 0.34, height: inner.height * 0.55)
                        ctx.fill(Path(roundedRect: lcd, cornerRadius: 2), with: .color(.black))
                        ctx.fill(Path(CGRect(x: lcd.minX + 4, y: lcd.midY - 1, width: lcd.width - 8, height: 2)), with: .color(look.lcd))
                    }
                    let start = (family == .delay || family == .modulation || family == .character) ? inner.minX + inner.width * 0.4 : inner.minX
                    let count = 4
                    let span = inner.maxX - start
                    for i in 0..<count {
                        let r = min(span / CGFloat(count) * 0.36, inner.height * 0.4)
                        let c = CGPoint(x: start + span * (CGFloat(i) + 0.5) / CGFloat(count), y: inner.midY)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                 with: .color(look.knobLight ? Color(white: 0.85) : Color(white: 0.12)))
                        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(look.accent.opacity(0.7)), lineWidth: 1.5)
                    }
                }
            }
            .frame(height: 74)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(selected ? Theme.on : Color.black, lineWidth: selected ? 3 : 1))
            Text(name)
                .font(.system(size: 14, weight: selected ? .bold : .regular))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
