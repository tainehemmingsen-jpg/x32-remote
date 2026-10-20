import SwiftUI

/// Full-screen channel page with tabs (Input, EQ, Dynamics, Sends, Setup) and a fader on the side.
struct ChannelDetailView: View {
    @Bindable var app: AppModel
    @State private var strip: StripID
    @Environment(\.dismiss) private var dismiss

    init(app: AppModel, strip: StripID) {
        self.app = app
        _strip = State(initialValue: strip)
    }

    var body: some View {
        let tabs = DetailTab.available(for: strip)
        let tab = tabs.contains(app.detailTab) ? app.detailTab : (tabs.first ?? .setup)
        GeometryReader { geo in
            let wide = geo.size.width >= 640
            VStack(spacing: 0) {
                DetailHeader(app: app, strip: $strip, tabs: tabs, tab: tab, wide: wide) {
                    dismiss()
                }
                if wide {
                    HStack(spacing: 0) {
                        DetailContent(app: app, strip: strip, tab: tab)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Rectangle().fill(Theme.line).frame(width: 1)
                        SideStrip(app: app, strip: strip)
                            .frame(width: 124)
                            .padding(.vertical, 10)
                    }
                } else {
                    DetailContent(app: app, strip: strip, tab: tab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    CompactStripBar(app: app, strip: strip)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            app.visibleDetailStrip = strip
        }
        .onDisappear {
            app.visibleDetailStrip = nil
        }
        .onChange(of: strip) { _, newStrip in
            app.visibleDetailStrip = newStrip
            app.loadDetail(newStrip)
        }
    }
}

private struct DetailContent: View {
    let app: AppModel
    let strip: StripID
    let tab: DetailTab

    var body: some View {
        switch tab {
        case .input:
            InputPage(app: app, strip: strip)
        case .eq:
            EQPage(app: app, strip: strip)
        case .dynamics:
            DynamicsPage(app: app, strip: strip)
        case .sends:
            SendsPage(app: app, strip: strip)
        case .setup:
            SetupPage(app: app, strip: strip)
        }
    }
}

private struct DetailHeader: View {
    let app: AppModel
    @Binding var strip: StripID
    let tabs: [DetailTab]
    let tab: DetailTab
    let wide: Bool
    let close: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.raised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")

                Button {
                    step(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.raised))
                }
                .buttonStyle(.plain)
                .disabled(strip.kind.count <= 1)
                .accessibilityLabel("Previous")

                DetailTitle(app: app, strip: strip)

                Button {
                    step(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.raised))
                }
                .buttonStyle(.plain)
                .disabled(strip.kind.count <= 1)
                .accessibilityLabel("Next")

                if wide {
                    Spacer(minLength: 10)
                    TabButtons(app: app, tabs: tabs, tab: tab)
                    FineButton(app: app, height: 34)
                        .frame(width: 70)
                }
            }
            if !wide {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        TabButtons(app: app, tabs: tabs, tab: tab)
                    }
                    FineButton(app: app, height: 32)
                        .frame(width: 64)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private func step(_ delta: Int) {
        let count = strip.kind.count
        guard count > 1 else { return }
        var next = strip.index + delta
        if next < 1 { next = count }
        if next > count { next = 1 }
        strip = StripID(strip.kind, next)
    }
}

private struct DetailTitle: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let name = app.param(strip.namePath).string
        let colorIndex = app.param(strip.colorPath).int
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.scribble(colorIndex))
                .frame(width: 8, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(strip.shortLabel.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                Text(name.isEmpty ? strip.defaultName : name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 150, alignment: .leading)
    }
}

private struct TabButtons: View {
    let app: AppModel
    let tabs: [DetailTab]
    let tab: DetailTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { t in
                Button {
                    app.detailTab = t
                } label: {
                    Text(t.title)
                        .fixedSize()
                        .barChip(active: t == tab)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Fader, meter, mute, solo and pan for the channel being edited.
struct SideStrip: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        VStack(spacing: 8) {
            if let pan = strip.panPath {
                VStack(spacing: 3) {
                    ParamPan(app: app, address: pan)
                    PanReadout(app: app, address: pan)
                }
            }
            SoloButton(app: app, strip: strip)
            MuteButton(app: app, strip: strip, height: 36)
            HStack(spacing: 4) {
                ParamFader(app: app, address: strip.faderPath, steps: 1023)
                if strip.kind != .dca {
                    MeterView(meter: app.meters.meter(strip), stereo: strip.kind == .main)
                        .frame(width: strip.kind == .main ? 12 : 6)
                        .padding(.vertical, 18)
                }
            }
            FaderReadout(app: app, address: strip.faderPath)
        }
        .padding(.horizontal, 10)
    }
}

struct PanReadout: View {
    let app: AppModel
    let address: String

    var body: some View {
        Text(panText(app.param(address).float(or: 0.5)))
            .font(Theme.mono(11))
            .foregroundStyle(Theme.secondary)
    }
}

/// Bottom bar version of the side strip for narrow screens.
private struct CompactStripBar: View {
    let app: AppModel
    let strip: StripID
    @State private var drag = DragTarget()

    var body: some View {
        let address = strip.faderPath
        let fader = app.param(address)
        HStack(spacing: 10) {
            MuteButton(app: app, strip: strip, height: 40)
                .frame(width: 70)
            HFader(
                value: fader.float,
                hapticAtUnity: app.settings.hapticAtUnity,
                fine: app.fineMode,
                onChange: { v in app.dragSet(address, drag, v, steps: 1023) },
                onTouch: { began in
                    if began { app.beginDrag(address, drag) } else { app.endDrag(drag) }
                }
            )
            .frame(height: 44)
            FaderReadout(app: app, address: strip.faderPath)
                .frame(width: 56)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.panel)
    }
}

// MARK: - Shared bound controls

/// A slider bar bound to one OSC address via a ParamSpec. (Kept the old name; it used to be a knob.)
struct ParamKnob: View {
    let app: AppModel
    let address: String
    let spec: ParamSpec
    let title: String
    var bipolar: Bool = false
    var tint: Color = Theme.accent
    var enabled: Bool = true
    var size: CGFloat = 54
    /// Double-tap to reset. Off by default: resetting gain or a threshold mid-show is dangerous.
    var resettable: Bool = false
    @State private var drag = DragTarget()

    var body: some View {
        let p = app.param(address)
        let v = p.float(or: spec.defaultNorm)
        BarSlider(
            title: title,
            value: v,
            display: p.isKnown ? spec.display(v) : "—",
            tint: tint,
            bipolar: bipolar,
            enabled: enabled,
            fine: app.fineMode,
            step: 1 / Float(max(spec.steps, 1)),
            defaultValue: resettable ? spec.defaultNorm : nil,
            onChange: { nv in
                guard app.param(drag.address ?? address).isKnown else { return }
                app.dragSet(address, drag, nv, steps: spec.steps)
            },
            onTouch: { began in
                if began { app.beginDrag(address, drag) } else { app.endDrag(drag) }
            }
        )
    }
}

/// A slider bar that steps through a list of named values (e.g. compressor ratio).
struct EnumKnob: View {
    let app: AppModel
    let address: String
    let options: [String]
    let title: String
    var suffix: String = ""
    var tint: Color = Theme.accent
    var enabled: Bool = true
    @State private var drag = DragTarget()

    var body: some View {
        let p = app.param(address)
        let count = max(options.count, 2)
        let index = min(max(p.int, 0), options.count - 1)
        let v = Float(index) / Float(count - 1)
        BarSlider(
            title: title,
            value: v,
            display: p.isKnown ? options[index] + suffix : "—",
            tint: tint,
            enabled: enabled,
            fine: app.fineMode,
            step: 1 / Float(count - 1),
            onChange: { nv in
                let target = drag.address ?? address
                guard app.param(target).isKnown else { return }
                let i = Int((nv * Float(count - 1)).rounded())
                if i != app.param(target).int {
                    app.setInt(target, i)
                    Haptics.click()
                }
            },
            onTouch: { began in
                if began { app.beginDrag(address, drag) } else { app.endDrag(drag) }
            }
        )
    }
}

/// A dropdown for enumerated parameters.
struct EnumMenu: View {
    let app: AppModel
    let address: String
    let options: [String]
    var tint: Color = Theme.accent

    var body: some View {
        let current = app.param(address).int
        let title = (current >= 0 && current < options.count && app.param(address).isKnown) ? options[current] : "—"
        Menu {
            ForEach(0..<options.count, id: \.self) { i in
                Button {
                    app.setInt(address, i)
                } label: {
                    if i == current {
                        Label(options[i], systemImage: "checkmark")
                    } else {
                        Text(options[i])
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondary)
            }
            .barChip()
        }
    }
}

/// An ON/OFF switch bound to an int address.
struct OnSwitch: View {
    let app: AppModel
    let address: String
    var title: String = "ON"
    var color: Color = Theme.on
    var width: CGFloat = 64

    var body: some View {
        let on = app.param(address).bool
        LitButton(title: title, isOn: on, color: color, height: 32) {
            app.setBool(address, !on)
        }
        .frame(width: width)
    }
}
