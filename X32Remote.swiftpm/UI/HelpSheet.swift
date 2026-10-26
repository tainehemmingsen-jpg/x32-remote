import SwiftUI

/// How the app's gestures work, in one place.
struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Tip: Identifiable {
        let symbol: String
        let title: String
        let text: String
        var id: String { title }
    }

    private let sections: [(String, [Tip])] = [
        ("Faders and sliders", [
            Tip(symbol: "hand.draw", title: "Drag anywhere on a fader",
                text: "It never jumps to your finger. Slide sideways off the strip while dragging for fine control. Several faders can move at once."),
            Tip(symbol: "slider.horizontal.3", title: "Slider bars",
                text: "Gain, EQ, dynamics and effect settings are bars: drag left or right anywhere on the bar."),
            Tip(symbol: "hand.tap", title: "Double-tap",
                text: "Resets an EQ gain or trim to 0. On a fader it opens the exact-value editor."),
            Tip(symbol: "arrow.left.and.right", title: "Pan",
                text: "Drag the pan box sideways; it sticks at centre so C is easy to find. Tap it for a big pan pad with L100, L50, C, R50 and R100 buttons."),
            Tip(symbol: "keyboard", title: "Long-press",
                text: "Any slider, gain or pan opens the editor, where you can type a value or step it by 0.1 or 1 dB."),
            Tip(symbol: "scope", title: "Fine",
                text: "With Fine on, everything moves four times more slowly under your finger.")
        ]),
        ("Mixer", [
            Tip(symbol: "rectangle.and.hand.point.up.left", title: "Open a channel",
                text: "Tap a channel's name, or its gain, EQ or compressor picture. Long-press the name to jump to its settings."),
            Tip(symbol: "arrow.left.arrow.right", title: "Sends on faders",
                text: "Pick a mix in the right-hand panel and the faders become that mix's sends. The strips tint in the mix's colour. Gain puts preamp gain on the faders."),
            Tip(symbol: "square.stack.3d.down.right", title: "DCA spill",
                text: "On the DCA layer, tap a DCA's name to see its channels. Tap again to go back."),
            Tip(symbol: "arrow.uturn.backward", title: "Undo",
                text: "The curved arrow undoes your last change. A whole fader move counts as one.")
        ]),
        ("Channel page", [
            Tip(symbol: "chart.xyaxis.line", title: "Gate and compressor graphs",
                text: "Drag the handles on the big graph: the corner sideways for the threshold, the lower gate handle for the depth, the top-right compressor handle up and down for the ratio."),
            Tip(symbol: "waveform.path", title: "EQ curve",
                text: "Drag a numbered point to change its frequency and gain. Tap RTA to see the desk's analyser behind the curve."),
            Tip(symbol: "doc.on.doc", title: "Copy, paste and presets",
                text: "The copy icon copies everything or one section to another channel, or saves it as a preset on this iPad."),
            Tip(symbol: "chevron.left.chevron.right", title: "Previous and next",
                text: "The arrows in the header move through the channels of the current layer.")
        ]),
        ("Effects", [
            Tip(symbol: "hand.point.up.left.and.text", title: "Graphic EQ",
                text: "Drag a band up or down. Sweep sideways to draw a curve. Double-tap a band to reset it."),
            Tip(symbol: "metronome", title: "Tap tempo",
                text: "Delays have a TAP button: tap in time with the music to set the delay time.")
        ]),
        ("Safety", [
            Tip(symbol: "exclamationmark.shield", title: "Things that ask first",
                text: "48 V, scene and cue recalls, stereo links, flattening an EQ, changing an effect type, routing, the signal generator and stopping a recording all ask before they change the desk."),
            Tip(symbol: "lock", title: "Locking",
                text: "In Monitor or Simple mode, set a PIN in Settings and lock the screen so performers or staff can't get to the full mixer.")
        ])
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.0) { title, tips in
                    Section(title) {
                        ForEach(tips) { tip in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: tip.symbol)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 30)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tip.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                    Text(tip.text)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("How to use the app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
