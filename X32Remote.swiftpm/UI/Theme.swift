import SwiftUI

/// Colours and type: a console's surface. Dark steel, rubber keys with LEDs, channel names on
/// console tape, panel legends in narrow caps, and the desk's own colours for state (green on,
/// red mute, yellow solo, amber for what's selected).
enum Theme {
    /// Behind everything.
    static let background = Color(red: 0.090, green: 0.098, blue: 0.106)
    /// Top bars: the desk's screen surround.
    static let topBar = Color(red: 0.122, green: 0.133, blue: 0.145)
    /// Strip and panel cells.
    static let panel = Color(red: 0.086, green: 0.094, blue: 0.110)
    /// Buttons and wells.
    static let raised = Color(red: 0.133, green: 0.145, blue: 0.165)
    static let raised2 = Color(red: 0.180, green: 0.196, blue: 0.220)
    /// Selected tab / pressed state.
    static let selected = Color(red: 0.235, green: 0.251, blue: 0.282)
    /// Hairlines between cells.
    static let line = Color.white.opacity(0.07)
    static let lineStrong = Color.white.opacity(0.16)
    /// Graph background and grid.
    static let graphBack = Color(red: 0.063, green: 0.075, blue: 0.094)
    static let graphGrid = Color.white.opacity(0.09)

    static let text = Color(white: 0.94)
    static let secondary = Color(white: 0.62)
    static let tertiary = Color(white: 0.40)

    /// The app's one accent: selection, focus, parameter fills.
    static let accent = Color(red: 1.0, green: 0.62, blue: 0.22)
    /// A deeper amber for the far end of fills.
    static let accentDeep = Color(red: 0.86, green: 0.40, blue: 0.10)
    /// Curves on the gate / EQ / compressor graphs.
    static let curve = Color(red: 1.0, green: 0.80, blue: 0.40)
    /// "On" outlines and lit processing lights.
    static let on = Color(red: 0.36, green: 0.86, blue: 0.42)
    static let mute = Color(red: 1.0, green: 0.30, blue: 0.27)
    static let muteOff = Color(red: 0.22, green: 0.07, blue: 0.07)
    static let solo = Color(red: 1.0, green: 0.82, blue: 0.20)
    static let soloOff = Color(red: 0.21, green: 0.18, blue: 0.06)
    static let phantomOff = Color(red: 0.24, green: 0.08, blue: 0.08)

    static let meterLow = Color(red: 0.36, green: 0.88, blue: 0.42)
    static let meterMid = Color(red: 1.0, green: 0.82, blue: 0.24)
    static let meterHigh = Color(red: 1.0, green: 0.30, blue: 0.25)

    /// X32 scribble-strip colours. 0-7 normal, 8-15 inverted.
    static func scribble(_ index: Int) -> Color {
        switch ((index % 8) + 8) % 8 {
        case 1: return Color(red: 0.91, green: 0.33, blue: 0.29)
        case 2: return Color(red: 0.47, green: 0.87, blue: 0.36)
        case 3: return Color(red: 0.93, green: 0.84, blue: 0.40)
        case 4: return Color(red: 0.27, green: 0.62, blue: 0.97)
        case 5: return Color(red: 0.62, green: 0.38, blue: 0.80)
        case 6: return Color(red: 0.36, green: 0.86, blue: 0.93)
        case 7: return Color(white: 0.88)
        default: return Color(white: 0.30)
        }
    }

    static func isInverted(_ index: Int) -> Bool {
        index >= 8
    }

    // MARK: Console surface (the "console tape" look)

    /// The desk's surface: dark steel.
    static let steel = Color(red: 0.090, green: 0.098, blue: 0.106)
    /// A channel strip's panel, a shade lighter at the top.
    static let stripTop = Color(red: 0.125, green: 0.137, blue: 0.149)
    static let stripBottom = Color(red: 0.106, green: 0.114, blue: 0.125)
    /// Rubber keys.
    static let keyTop = Color(red: 0.227, green: 0.243, blue: 0.259)
    static let keyBottom = Color(red: 0.173, green: 0.184, blue: 0.200)
    /// Console tape and the marker on it.
    static let tape = Color(red: 0.922, green: 0.898, blue: 0.824)
    static let marker = Color(red: 0.11, green: 0.11, blue: 0.11)
    /// LED amber: selected layers, lit processing, readouts.
    static let led = Color(red: 1.0, green: 0.69, blue: 0.18)
    static let readout = Color(red: 1.0, green: 0.81, blue: 0.48)

    /// `a` moved `amount` of the way to `b` (Color.mix needs iOS 18).
    static func blend(_ a: Color, _ b: Color, _ amount: CGFloat) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(a).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(b).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(amount, 0), 1)
        return Color(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, opacity: a1 + (a2 - a1) * t)
    }

    /// Panel legends: narrow caps, as printed on a desk.
    static func legend(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = ConsoleFonts.condensedBold
        case .medium, .regular, .light, .thin, .ultraLight: name = ConsoleFonts.condensedMedium
        default: name = ConsoleFonts.condensedSemiBold
        }
        return .custom(name, fixedSize: size)
    }

    /// Channel names written on the tape.
    static func markerFont(_ size: CGFloat) -> Font {
        .custom(ConsoleFonts.marker, fixedSize: size)
    }

    static func label(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

/// A console-style button. `.fill` buttons glow in their colour when on and show a dim version
/// of it when off (mute, solo, +48V). `.outline` buttons get a green rim when on ("On", "Fine").
///
/// Nothing about it animates: it changes the frame the desk does. `instant` keys act the moment a
/// finger lands (like a hardware key), not when it lifts; use them on the strips and sidebar, not
/// inside scrolling lists (where a touch might be the start of a scroll).
struct LitButton: View {
    enum Style { case fill, outline }

    let title: String
    let isOn: Bool
    var color: Color = Theme.accent
    var height: CGFloat = 30
    var fontSize: CGFloat = 12
    var style: Style = .fill
    var offColor: Color? = nil
    var enabled: Bool = true
    var instant: Bool = false
    let action: () -> Void

    var body: some View {
        if instant {
            face
                .modifier(PressAction(action: action))
                .opacity(enabled ? 1 : 0.4)
                .allowsHitTesting(enabled)
        } else {
            Button(action: action) { face }
                .buttonStyle(ConsoleKeyStyle())
                .opacity(enabled ? 1 : 0.4)
                .allowsHitTesting(enabled)
        }
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let lit = isOn
        // Mute lights the whole key, as a desk's mute does; every other key lights its LED.
        let tintsFace = lit && style == .fill && color == Theme.mute
        return HStack(spacing: height >= 26 ? 5 : 3) {
            if height >= 22 {
                Circle()
                    .fill(lit ? ledColor : ledColor.opacity(0.22))
                    .frame(width: 6, height: 6)
                    .background {
                        if lit { Circle().fill(ledColor).blur(radius: 3.5) }
                    }
            }
            Text(title.uppercased())
                .font(Theme.legend(fontSize + 1, .bold))
                .tracking(fontSize >= 11 ? 1.1 : 0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(shape.fill(LinearGradient(colors: tintsFace ? [Color(red: 0.31, green: 0.15, blue: 0.14), Color(red: 0.23, green: 0.11, blue: 0.11)]
                                                              : [Theme.keyTop, Theme.keyBottom],
                                              startPoint: .top, endPoint: .bottom)))
        // Key depth: a lit top edge and a hard shadow under it.
        .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.09), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
        .background(shape.fill(Color.black).offset(y: 1.5))
        .contentShape(Rectangle())
        .transaction { $0.animation = nil }
    }

    private var ledColor: Color {
        style == .outline ? Theme.on : color
    }

    private var textColor: Color {
        guard isOn else { return Theme.text.opacity(0.62) }
        if style == .outline { return Theme.text }
        // The legend takes a pale version of the LED colour.
        return Theme.blend(color, .white, 0.45)
    }
}

/// How a scribble colour is drawn on a button or chip.
/// No fade, no spring: pressed keys darken for exactly as long as the finger is down.
struct ConsoleKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.12 : 0)
            .transaction { $0.animation = nil }
    }
}

/// Fires on touch-down, once per touch. Still a button to VoiceOver.
struct PressAction: ViewModifier {
    let action: () -> Void
    @GestureState private var down = false
    @State private var fired = false

    func body(content: Content) -> some View {
        content
            .brightness(down ? -0.12 : 0)
            .transaction { $0.animation = nil }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($down) { _, state, _ in state = true }
                    .onChanged { _ in
                        if !fired {
                            fired = true
                            action()
                        }
                    }
                    .onEnded { _ in fired = false }
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

struct ScribbleStyle {
    let text: Color
    let fill: Color
    let border: Color

    init(colorIndex: Int) {
        let color = Theme.scribble(colorIndex)
        let off = colorIndex % 8 == 0
        if off {
            text = Theme.text
            fill = Theme.raised2
            border = Color.white.opacity(0.08)
        } else if Theme.isInverted(colorIndex) {
            text = color
            fill = Theme.raised
            border = color
        } else {
            text = Color.black.opacity(0.85)
            fill = color
            border = color
        }
    }
}

/// A channel's name, written in marker on a strip of console tape, with a dot of the channel's
/// scribble colour stuck on the corner (a ring for the X32's inverted colours).
struct ScribbleView: View {
    let name: String
    let colorIndex: Int
    var placeholder: String = ""
    var height: CGFloat = 34
    var fontSize: CGFloat = 12
    var selected: Bool = false

    var body: some View {
        let shownName = name.isEmpty ? placeholder : name
        let colored = colorIndex % 8 != 0
        let dot = Theme.scribble(colorIndex)
        Text(shownName)
            .font(Theme.markerFont(fontSize + 1.5))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(Theme.marker.opacity(name.isEmpty ? 0.45 : 1))
            .padding(.horizontal, colored ? 7 : 4)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(TapeShape(seed: TapeShape.seed(shownName)).fill(Theme.tape))
            .overlay(alignment: .topLeading) {
                if colored {
                    Group {
                        if Theme.isInverted(colorIndex) {
                            Circle().strokeBorder(dot, lineWidth: 2)
                        } else {
                            Circle().fill(dot)
                        }
                    }
                    .frame(width: 8, height: 8)
                    .padding(3)
                }
            }
            .overlay {
                if selected {
                    TapeShape(seed: TapeShape.seed(shownName)).stroke(Theme.accent, lineWidth: 2)
                }
            }
            // Stuck on by hand: never quite straight.
            .rotationEffect(.degrees(TapeShape.tilt(shownName)))
            .compositingGroup()
            .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
            .contentShape(Rectangle())
    }
}

/// A strip of tape with torn ends: straight-ish long edges, ragged short ones.
struct TapeShape: Shape {
    let seed: Int

    static func seed(_ text: String) -> Int {
        text.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    }

    /// A small, steady tilt for a name (the same every time it's drawn).
    static func tilt(_ text: String) -> Double {
        Double(seed(text) % 29 - 14) / 10
    }

    func path(in rect: CGRect) -> Path {
        var rng = seed
        func jitter(_ amount: CGFloat) -> CGFloat {
            rng = (rng &* 1103515245 &+ 12345) & 0x7FFFFFFF
            return CGFloat(rng % 1000) / 1000 * amount
        }
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + jitter(2), y: rect.minY + jitter(1.5)))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.35, y: rect.minY + jitter(1)))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.7, y: rect.minY + jitter(1.2)))
        p.addLine(to: CGPoint(x: rect.maxX - jitter(2), y: rect.minY + jitter(1)))
        // torn right end
        for i in 1...4 {
            p.addLine(to: CGPoint(x: rect.maxX - jitter(2.5), y: rect.minY + h * CGFloat(i) / 5))
        }
        p.addLine(to: CGPoint(x: rect.maxX - jitter(2), y: rect.maxY - jitter(1.5)))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.65, y: rect.maxY - jitter(1)))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.3, y: rect.maxY - jitter(1.2)))
        p.addLine(to: CGPoint(x: rect.minX + jitter(2), y: rect.maxY - jitter(1)))
        // torn left end
        for i in stride(from: 4, through: 1, by: -1) {
            p.addLine(to: CGPoint(x: rect.minX + jitter(2.5), y: rect.minY + h * CGFloat(i) / 5))
        }
        p.closeSubpath()
        return p
    }
}

/// Section container used on the settings-style pages.
struct Panel<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = title {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.secondary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// A block with the dark cell look used for every column on the channel pages.
struct Cell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

extension View {
    /// Flat rectangular button look used in bars and menus.
    func barChip(active: Bool = false, tint: Color = Theme.accent) -> some View {
        self
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? tint.opacity(0.16) : Theme.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(active ? tint : Color.white.opacity(0.07), lineWidth: active ? 1.5 : 1)
            )
    }
}

/// Shows just the icon on phones, icon and title elsewhere.
struct AdaptiveLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }
        }
    }
}
