import SwiftUI

/// A big, easy pan control: a wide slider that sticks at centre, a large readout, and one-tap
/// positions. Used in a popover from a strip's pan box and on the channel's Config page.
struct PanPad: View {
    let app: AppModel
    let address: String
    let title: String

    private static let presets: [(String, Float)] = [("L100", 0), ("L50", 0.25), ("C", 0.5), ("R50", 0.75), ("R100", 1)]

    var body: some View {
        let p = app.param(address)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Spacer()
                Text(p.isKnown ? panText(p.float) : "—")
                    .font(.system(size: 28, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.text)
            }
            ParamPan(app: app, address: address, height: 64, editTitle: "\(title) · Pan", showsText: false, showsTicks: true)
                .paramAccessibility(app: app, title: "\(title) pan", address: address, spec: Specs.pan, reset: 0.5)
            HStack(spacing: 0) {
                Text("L").frame(maxWidth: .infinity, alignment: .leading)
                Text("C").frame(maxWidth: .infinity)
                Text("R").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.tertiary)
            .padding(.horizontal, 4)
            HStack(spacing: 6) {
                ForEach(PanPad.presets, id: \.0) { label, value in
                    let current = p.isKnown && abs(p.float - value) < 0.005
                    LitButton(title: label, isOn: current, height: 40, fontSize: 14, style: .outline) {
                        guard p.isKnown else { return }
                        app.setFloat(address, value, steps: 100)
                        Haptics.click()
                    }
                    .accessibilityLabel(label == "C" ? "Centre" : label)
                }
            }
            Text("Drag anywhere on the bar. It sticks at centre so you can always find C.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
        }
    }
}
