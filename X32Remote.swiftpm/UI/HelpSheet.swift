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
                text: "It never jumps to your finger. Slide sideways off the strip while dragging for fine control. Several faders can move at once. The value shows above the cap while you hold it."),
            Tip(symbol: "equal", title: "0 dB catch",
                text: "Faders catch at 0 dB with a click. Keep pushing a little further to go past it."),
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
            Tip(symbol: "rectangle.and.hand.point.up.left", title: "Quick editors",
                text: "Tap a strip's gain, gate, EQ or compressor and a small editor opens over the faders, so you never leave the mix. Channel, at its top right, opens the whole channel."),
            Tip(symbol: "rectangle.expand.vertical", title: "Open a channel",
                text: "Tap a channel's name, or touch and hold its gate, EQ or compressor picture."),
            Tip(symbol: "rectangle.grid.1x2", title: "Screen keys",
                text: "Across the top, like the X32's own keys: Monitor (solo, phones and talkback), Meters, Ring out, Mix check, Setlist, Routing, Effects, Scenes and Settings. If the screen is too narrow for the names, they show as icons only."),
            Tip(symbol: "square.stack.3d.up", title: "Snapshots",
                text: "Like a DiGiCo: Store saves the mix as the next snapshot, GO recalls the next one (space bar with a keyboard). Each snapshot can recall only some strips or parts, with a fade time. Recall safes protect strips from every recall. Each recall is one undo."),
            Tip(symbol: "square.stack.3d.up.fill", title: "Desk scenes and scene files",
                text: "Desk scenes are the 100 scenes stored in the X32 itself. Scene files are saved on this iPad, or imported from X32-Edit."),
            Tip(symbol: "hand.tap.fill", title: "Long-press a strip name",
                text: "Open it, rename it, copy or paste its settings, or load a starting point (vocal, kick…)."),
            Tip(symbol: "arrow.left.arrow.right", title: "Sends on faders",
                text: "Pick a mix in the right-hand panel and the faders become that mix's sends. The strips tint in the mix's colour. Gain puts preamp gain on the faders."),
            Tip(symbol: "square.stack.3d.down.right", title: "DCA spill",
                text: "On the DCA layer, tap a DCA's name to see its channels. Tap again to go back."),
            Tip(symbol: "arrow.uturn.backward", title: "Undo",
                text: "The curved arrow undoes your last change. A whole fader move counts as one. After an undo, a redo arrow appears beside it."),
            Tip(symbol: "keyboard", title: "Keyboard shortcuts",
                text: "With a keyboard on the iPad (or on a Mac): ⌘Z undo, ⇧⌘Z redo, ⌘← ⌘→ banks, ⌘1–⌘7 layers, ⌘K Mix check, ⌘E effects, ⌘L setlist, ⌘↓ ⌘↑ next and previous song, ⌘O scenes, space GO next snapshot. In a channel: ⌘[ ⌘] previous and next, Esc to close. Hold ⌘ to see them all.")
        ]),
        ("Channel page", [
            Tip(symbol: "chart.xyaxis.line", title: "Gate and compressor graphs",
                text: "Drag the handles on the big graph: the corner sideways for the threshold, the lower gate handle for the depth, the top-right compressor handle up and down for the ratio."),
            Tip(symbol: "waveform.path", title: "EQ curve",
                text: "Drag a numbered point to change its frequency and gain. Tap RTA to see the desk's analyser behind the curve."),
            Tip(symbol: "doc.on.doc", title: "Copy, paste and presets",
                text: "The copy icon copies everything or one section to another channel, or saves it as a preset on this iPad."),
            Tip(symbol: "chevron.left.chevron.right", title: "Previous and next",
                text: "The arrows in the header move through the channels of the current layer."),
            Tip(symbol: "square.split.2x1", title: "A/B compare",
                text: "Tap A/B in the channel header: the channel as it is now is saved as A. Change anything, then tap A and B to flip between the two versions. Tap Keep when you've decided."),
            Tip(symbol: "square.grid.3x3", title: "Go to…",
                text: "Jump straight to any channel, aux, FX return, bus or matrix from the channel page."),
            Tip(symbol: "wand.and.stars", title: "Auto gain",
                text: "On Home or Input: tap Auto gain, have them play as loud as they will in the show, and tap Listen. After 8 seconds it suggests a gain that leaves 12 dB of headroom; tap Set gain (Undo takes it back)."),
            Tip(symbol: "square.grid.2x2", title: "Start from…",
                text: "Pick what's plugged in (vocal, kick, acoustic guitar, speech…) for a sensible low cut, gate, EQ and compressor to start from.")
        ]),
        ("Listen on this iPad", [
            Tip(symbol: "headphones", title: "Hear solo in your earphones",
                text: "The headphones button in the top bar › Listen on this iPad. Solo anything and hear it in the earphones plugged into this iPad, wherever you're standing. Nothing soloed: you hear the desk's monitor source (usually the main mix)."),
            Tip(symbol: "arrow.triangle.branch", title: "Setting it up",
                text: "The X32 only sends audio out through its USB card. In Listen, tap Send solo to USB 31/32 once (it uses outputs 15/16; choose 7/8 if those are in use). Then either run X32 Listen Bridge on a Mac plugged into the desk's USB port (it streams over Wi-Fi), or plug this iPad into the desk's USB port."),
            Tip(symbol: "cable.connector", title: "Wired earphones",
                text: "Bluetooth earphones add about 200 ms of delay. Wired IEMs are much closer to live. With the iPad plugged into the desk, the earphones need the headphone socket or a USB-C hub with a headphone adapter: the app never plays back into the desk."),
        ]),
        ("Sound check", [
            Tip(symbol: "stethoscope", title: "Mix check",
                text: "The stethoscope in the top bar turns red with a count when something needs fixing. It looks over every channel: clipping or quiet preamps, named channels with no signal, open channels with nothing on them, voices without low cut, big EQ boosts, heavy compression and very high faders. Each one is explained, and most have a one-tap fix. Run it while the band plays, as it judges the last minute."),
            Tip(symbol: "arrow.left.arrow.right", title: "What's changed",
                text: "Save the desk to the scene library after soundcheck. Later, tap What's changed on that scene to see every setting that's moved since, and put any of them back with one tap."),
            Tip(symbol: "music.note.list", title: "Setlist",
                text: "Add the songs with their tempo and who sits out. Tapping a song sets every delay to the song's tempo and mutes the channels that aren't playing (and unmutes the ones that are back). TAP in a song works out the tempo for you. While a setlist runs, the song shows in the top bar with a button for the next one."),
            Tip(symbol: "mic.badge.plus", title: "Talk over music",
                text: "From the console menu: pick a mic and the music channels, and the music dips by itself whenever someone talks into the mic, then comes back up. Made for gym classes, MCs and announcements. The switch also shows in Simple mode."),
            Tip(symbol: "list.number", title: "Paste an input list",
                text: "In Build a scene, paste the input list from a rider (\"1 Kick In\", \"2 Snare Top\"…) and it names, colours and sets up every channel in its numbered slot."),
            Tip(symbol: "waveform.badge.exclamationmark", title: "Ring out",
                text: "The feedback icon in the top bar: pick a wedge's mix or the PA, bring it up slowly until it rings, and tap Cut on the frequency that appears. Each tap cuts a narrow notch in that mix's EQ (tap again to cut deeper). Notches are listed so you can take them out."),
            Tip(symbol: "chart.bar", title: "Meters",
                text: "A line holds each meter's recent peak. A red cap means that signal hit 0 dBFS: tap the meter to clear it."),
            Tip(symbol: "chart.line.downtrend.xyaxis", title: "Gain reduction history",
                text: "The Gate and Compressor pages draw the last few seconds of gain reduction, so you can see how hard they work through a whole phrase.")
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
