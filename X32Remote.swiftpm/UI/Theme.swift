import SwiftUI

enum Theme {
    static let background = Color(red: 0.047, green: 0.051, blue: 0.063)
    static let panel = Color(red: 0.082, green: 0.090, blue: 0.110)
    static let raised = Color(red: 0.122, green: 0.133, blue: 0.157)
    static let raised2 = Color(red: 0.165, green: 0.176, blue: 0.204)
    static let line = Color.white.opacity(0.08)
    static let lineStrong = Color.white.opacity(0.16)
    static let text = Color(white: 0.93)
    static let secondary = Color(white: 0.62)
    static let tertiary = Color(white: 0.42)
    static let accent = Color(red: 1.0, green: 0.60, blue: 0.18)
    static let mute = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let solo = Color(red: 0.98, green: 0.79, blue: 0.18)
    static let on = Color(red: 0.24, green: 0.80, blue: 0.47)
    static let meterLow = Color(red: 0.25, green: 0.82, blue: 0.45)
    static let meterMid = Color(red: 0.98, green: 0.80, blue: 0.20)
    static let meterHigh = Color(red: 0.96, green: 0.30, blue: 0.25)

    /// X32 scribble-strip colours. 0-7 normal, 8-15 inverted.
    static func scribble(_ index: Int) -> Color {
        switch ((index % 8) + 8) % 8 {
        case 1: return Color(red: 0.93, green: 0.26, blue: 0.28)
        case 2: return Color(red: 0.27, green: 0.80, blue: 0.42)
        case 3: return Color(red: 0.96, green: 0.83, blue: 0.22)
        case 4: return Color(red: 0.26, green: 0.53, blue: 0.98)
        case 5: return Color(red: 0.86, green: 0.36, blue: 0.86)
        case 6: return Color(red: 0.22, green: 0.80, blue: 0.86)
        case 7: return Color(white: 0.90)
        default: return Color(white: 0.30)
        }
    }

    static func isInverted(_ index: Int) -> Bool {
        index >= 8
    }

    static func label(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

/// A rounded, lit-when-on button used for mute, solo, send on and similar switches.
struct LitButton: View {
    let title: String
    let isOn: Bool
    var color: Color = Theme.accent
    var height: CGFloat = 30
    var fontSize: CGFloat = 11
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isOn ? Color.black.opacity(0.85) : Theme.secondary)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? color : Theme.raised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isOn ? color.opacity(0.9) : Theme.line, lineWidth: 1)
                )
                .shadow(color: isOn ? color.opacity(0.45) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }
}

/// The coloured name label at the top of a strip, styled like the X32's scribble strips.
struct ScribbleView: View {
    let name: String
    let colorIndex: Int
    let number: String
    var placeholder: String = ""
    var height: CGFloat = 46
    var selected: Bool = false

    var body: some View {
        let style = ScribbleView.style(colorIndex: colorIndex, selected: selected)
        let shownName = name.isEmpty ? placeholder : name
        VStack(spacing: 2) {
            Text(number)
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .opacity(0.75)
            Text(shownName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(style.text)
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(style.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(style.border, lineWidth: selected ? 2 : 1)
        )
        .contentShape(Rectangle())
    }

    struct Style {
        let text: Color
        let fill: Color
        let border: Color
    }

    static func style(colorIndex: Int, selected: Bool) -> Style {
        let color = Theme.scribble(colorIndex)
        let inverted = Theme.isInverted(colorIndex)
        let off = colorIndex % 8 == 0
        let text: Color
        let fill: Color
        if off {
            text = Theme.secondary
            fill = Theme.raised
        } else if inverted {
            text = color
            fill = Theme.raised
        } else {
            text = Color.black.opacity(0.85)
            fill = color.opacity(0.92)
        }
        let border: Color
        if selected {
            border = Theme.accent
        } else if inverted && !off {
            border = color
        } else {
            border = Theme.line
        }
        return Style(text: text, fill: fill, border: border)
    }
}

/// Small rounded section container.
struct Panel<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .tracking(0.8)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

extension View {
    /// Standard glassy capsule style for top-bar buttons.
    func barChip(active: Bool = false, tint: Color = Theme.accent) -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? Color.black.opacity(0.85) : Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? tint : Theme.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(active ? tint : Theme.line, lineWidth: 1)
            )
    }
}
