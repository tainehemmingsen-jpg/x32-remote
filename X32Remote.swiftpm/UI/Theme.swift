import SwiftUI

/// Colours and type: deep graphite with one warm signal-amber accent for anything selected or
/// adjustable, and console-standard colours for state (green on, red mute, yellow solo).
enum Theme {
    /// Behind everything.
    static let background = Color(red: 0.047, green: 0.051, blue: 0.059)
    /// Top bars.
    static let topBar = Color(red: 0.035, green: 0.039, blue: 0.045)
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

    static func label(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

/// A console-style button. `.fill` buttons glow in their colour when on and show a dim version
/// of it when off (mute, solo, +48V). `.outline` buttons get a green rim when on ("On", "Fine").
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
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(7, height * 0.22), style: .continuous)
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: isOn && style == .fill ? .bold : .semibold))
                .tracking(fontSize >= 12 ? 0.3 : 0)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .foregroundStyle(textColor)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .background(shape.fill(fill))
                // A soft top highlight, like a backlit console key.
                .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(isOn ? 0.22 : 0.06), .clear],
                                                   startPoint: .top, endPoint: .center)))
                .overlay(shape.strokeBorder(border, lineWidth: style == .outline && isOn ? 1.5 : 1))
                .shadow(color: style == .fill && isOn ? color.opacity(0.45) : .clear, radius: 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .allowsHitTesting(enabled)
    }

    private var fill: Color {
        switch style {
        case .fill: return isOn ? color : (offColor ?? color.opacity(0.16))
        case .outline: return isOn ? Theme.raised2 : Theme.raised
        }
    }

    private var border: Color {
        switch style {
        case .fill: return isOn ? Color.white.opacity(0.25) : Color.white.opacity(0.06)
        case .outline: return isOn ? Theme.on : Color.white.opacity(0.07)
        }
    }

    private var textColor: Color {
        switch style {
        case .fill: return isOn ? Color.black.opacity(0.85) : Theme.text.opacity(0.7)
        case .outline: return isOn ? Theme.text : Theme.secondary
        }
    }
}

/// How a scribble colour is drawn on a button or chip.
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

/// A channel-coloured name button (tap opens the channel).
struct ScribbleView: View {
    let name: String
    let colorIndex: Int
    var placeholder: String = ""
    var height: CGFloat = 34
    var fontSize: CGFloat = 12
    var selected: Bool = false

    var body: some View {
        let style = ScribbleStyle(colorIndex: colorIndex)
        let shownName = name.isEmpty ? placeholder : name
        Text(shownName.uppercased())
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .multilineTextAlignment(.center)
            .foregroundStyle(style.text)
            .tracking(0.4)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(style.fill))
            // Backlit-display sheen.
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.0), Color.black.opacity(0.12)],
                                     startPoint: .top, endPoint: .bottom)))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Color.black.opacity(0.35), lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
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
