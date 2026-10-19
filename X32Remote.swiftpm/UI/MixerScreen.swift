import SwiftUI

/// The full console view: a bank of strips, the master strip and the top bar.
struct MixerScreen: View {
    @Bindable var app: AppModel
    @State private var page = 0

    var body: some View {
        GeometryReader { geo in
            let masterWidth: CGFloat = geo.size.width > 900 ? 118 : 96
            let layout = MixerScreen.pageLayout(strips: app.layer.strips, width: geo.size.width - masterWidth - 28, page: page)
            VStack(spacing: 0) {
                MixerTopBar(app: app, page: $page, pageCount: layout.pageCount, perPage: layout.perPage, total: layout.total)
                if let bus = app.sendsBus, app.layer.supportsBusSends {
                    SendsBanner(app: app, bus: bus)
                }
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        ForEach(layout.visible) { strip in
                            StripView(app: app, strip: strip, sendsBus: app.layer.supportsBusSends ? app.sendsBus : nil)
                        }
                    }
                    Rectangle()
                        .fill(Theme.line)
                        .frame(width: 1)
                        .padding(.vertical, 20)
                    MasterStrip(app: app)
                        .frame(width: masterWidth)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
        }
        .background(Theme.background)
        .onChange(of: app.layer) { _, _ in
            page = 0
        }
        .fullScreenCover(item: $app.detailStrip) { strip in
            ChannelDetailView(app: app, strip: strip)
        }
        .sheet(item: $app.sheet) { sheet in
            switch sheet {
            case .scenes:
                ScenesSheet(app: app)
            case .settings:
                SettingsSheet(app: app)
            case .modes:
                ModesSheet(app: app)
            }
        }
    }

    struct PageLayout {
        let visible: [StripID]
        let pageCount: Int
        let perPage: Int
        let total: Int
    }

    /// Shows a whole layer when strips can be at least 56 pt wide, otherwise pages of 8 (or fewer on phones).
    static func pageLayout(strips: [StripID], width: CGFloat, page: Int) -> PageLayout {
        let count = strips.count
        guard count > 0 else { return PageLayout(visible: [], pageCount: 1, perPage: 1, total: 0) }
        var perPage = count
        if width / CGFloat(count) < 56 {
            if width / 8 >= 56 {
                perPage = min(8, count)
            } else {
                perPage = max(3, min(count, Int(width / 60)))
            }
        }
        let pageCount = (count + perPage - 1) / perPage
        let current = min(max(page, 0), pageCount - 1)
        let start = current * perPage
        let end = min(count, start + perPage)
        return PageLayout(visible: Array(strips[start..<end]), pageCount: pageCount, perPage: perPage, total: count)
    }
}

// MARK: - Top bar

struct MixerTopBar: View {
    @Bindable var app: AppModel
    @Binding var page: Int
    let pageCount: Int
    let perPage: Int
    let total: Int

    var body: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ConsoleMenu(app: app)
                    Spacer(minLength: 6)
                    LayerButtons(app: app)
                    if pageCount > 1 {
                        PageButtons(page: $page, count: pageCount, perPage: perPage, total: total)
                    }
                    Spacer(minLength: 6)
                    SendsMenu(app: app)
                }
                compactRow
                ScrollView(.horizontal, showsIndicators: false) {
                    compactRow
                }
            }
            ViewThatFits(in: .horizontal) {
                secondRow
                ScrollView(.horizontal, showsIndicators: false) {
                    secondRow
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private var compactRow: some View {
        HStack(spacing: 8) {
            ConsoleMenu(app: app)
            Spacer(minLength: 6)
            LayerMenu(app: app)
            if pageCount > 1 {
                PageButtons(page: $page, count: pageCount, perPage: perPage, total: total)
            }
            SendsMenu(app: app)
        }
    }

    private var secondRow: some View {
        HStack(spacing: 8) {
            MuteGroupBar(app: app)
            Spacer(minLength: 6)
            ClearSoloButton(app: app)
            SceneButton(app: app)
        }
    }
}

struct ConsoleMenu: View {
    let app: AppModel

    var body: some View {
        Menu {
            Section(app.connectedName + (app.isDemo ? "" : " · " + app.connectedAddress)) {
                Button {
                    app.loadScenes()
                    app.sheet = .scenes
                } label: {
                    Label("Scenes", systemImage: "square.stack.3d.up")
                }
                Button {
                    app.sheet = .modes
                } label: {
                    Label("Switch mode", systemImage: "rectangle.3.group")
                }
                Button {
                    app.sheet = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            Button(role: .destructive) {
                app.disconnect()
            } label: {
                Label("Disconnect", systemImage: "power")
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(app.linkLost ? Theme.mute : (app.isDemo ? Theme.accent : Theme.on))
                    .frame(width: 9, height: 9)
                Text(app.connectedName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondary)
            }
            .barChip()
        }
    }
}

struct LayerButtons: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MixerLayer.allCases) { layer in
                Button {
                    app.selectLayer(layer)
                } label: {
                    Text(layer.title)
                        .lineLimit(1)
                        .fixedSize()
                        .barChip(active: app.layer == layer)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LayerMenu: View {
    let app: AppModel

    var body: some View {
        Menu {
            ForEach(MixerLayer.allCases) { layer in
                Button {
                    app.selectLayer(layer)
                } label: {
                    if app.layer == layer {
                        Label(layer.title, systemImage: "checkmark")
                    } else {
                        Text(layer.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(app.layer.title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .barChip(active: true)
        }
    }
}

struct PageButtons: View {
    @Binding var page: Int
    let count: Int
    let perPage: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { p in
                Button {
                    page = p
                } label: {
                    Text(label(p))
                        .fixedSize()
                        .barChip(active: page == p, tint: Theme.text)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func label(_ p: Int) -> String {
        let first = p * perPage + 1
        let last = min(total, (p + 1) * perPage)
        return first == last ? "\(first)" : "\(first)–\(last)"
    }
}

struct SendsMenu: View {
    let app: AppModel

    var body: some View {
        let label: String = {
            guard let bus = app.sendsBus else { return "Main mix" }
            let name = app.param(StripID(.bus, bus).namePath).string
            return name.isEmpty ? "Bus \(bus)" : "\(bus) · \(name)"
        }()
        let busColor = app.sendsBus.map { Theme.scribble(app.param(StripID(.bus, $0).colorPath).int) } ?? Theme.accent
        Menu {
            Button {
                app.selectSendsBus(nil)
            } label: {
                if app.sendsBus == nil {
                    Label("Main mix", systemImage: "checkmark")
                } else {
                    Text("Main mix")
                }
            }
            Section("Sends on faders") {
                ForEach(1...16, id: \.self) { bus in
                    SendsMenuItem(app: app, bus: bus)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: app.sendsBus == nil ? "slider.vertical.3" : "arrow.turn.down.right")
                Text(label)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .barChip(active: app.sendsBus != nil, tint: busColor)
        }
    }
}

private struct SendsMenuItem: View {
    let app: AppModel
    let bus: Int

    var body: some View {
        let name = app.param(StripID(.bus, bus).namePath).string
        let title = name.isEmpty ? "Bus \(bus)" : "Bus \(bus) · \(name)"
        Button {
            app.selectSendsBus(bus)
        } label: {
            if app.sendsBus == bus {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

struct MuteGroupBar: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 5) {
            Text("MUTE\nGROUPS")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Theme.tertiary)
                .multilineTextAlignment(.trailing)
            ForEach(1...6, id: \.self) { n in
                MuteGroupButton(app: app, group: n)
            }
        }
    }
}

private struct MuteGroupButton: View {
    let app: AppModel
    let group: Int

    var body: some View {
        let address = "/config/mute/\(group)"
        let on = app.param(address).bool
        LitButton(title: "\(group)", isOn: on, color: Theme.mute, height: 30, fontSize: 13) {
            app.setBool(address, !on)
        }
        .frame(width: 40)
    }
}

struct ClearSoloButton: View {
    let app: AppModel

    var body: some View {
        let anySolo = app.param("/-stat/solo").bool
        Button {
            app.clearSolo()
        } label: {
            Text(anySolo ? "Clear solo" : "No solo")
                .barChip(active: anySolo, tint: Theme.solo)
        }
        .buttonStyle(.plain)
        .disabled(!anySolo)
    }
}

struct SceneButton: View {
    let app: AppModel

    var body: some View {
        let current = app.param("/-show/prepos/current").int
        let name = app.param(String(format: "/-show/showfile/scene/%03d/name", max(0, current))).string
        Button {
            app.loadScenes()
            app.sheet = .scenes
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                Text(name.isEmpty ? String(format: "Scene %02d", max(0, current)) : String(format: "%02d %@", max(0, current), name))
                    .lineLimit(1)
            }
            .barChip()
        }
        .buttonStyle(.plain)
    }
}

/// Coloured banner shown while faders control sends to a mix bus.
struct SendsBanner: View {
    let app: AppModel
    let bus: Int

    var body: some View {
        let strip = StripID(.bus, bus)
        let name = app.param(strip.namePath).string
        let color = Theme.scribble(app.param(strip.colorPath).int)
        HStack(spacing: 10) {
            Image(systemName: "arrow.turn.down.right")
            Text("Faders are sends to")
                .foregroundStyle(Color.black.opacity(0.7))
            Text(name.isEmpty ? "Bus \(bus)" : "Bus \(bus) · \(name)")
                .fontWeight(.bold)
            Spacer()
            Button {
                app.selectSendsBus(nil)
            } label: {
                Text("Back to main mix")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.black.opacity(0.25)))
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(color.opacity(0.9))
    }
}

// MARK: - Strips

struct StripView: View {
    let app: AppModel
    let strip: StripID
    let sendsBus: Int?

    var body: some View {
        let busTint: Color? = sendsBus.map { Theme.scribble(app.param(StripID(.bus, $0).colorPath).int) }
        let tint = busTint ?? Theme.accent
        VStack(spacing: 6) {
            StripScribble(app: app, strip: strip)
            if let bus = sendsBus {
                SendOnButton(app: app, strip: strip, bus: bus)
            } else if let panPath = strip.panPath {
                ParamPan(app: app, address: panPath)
            } else {
                Color.clear.frame(height: 22)
            }
            SoloButton(app: app, strip: strip)
            MuteButton(app: app, strip: strip)
            HStack(spacing: 3) {
                if let bus = sendsBus {
                    ParamFader(app: app, address: strip.sendLevelPath(bus), steps: 160, tint: tint, label: "SEND")
                } else {
                    ParamFader(app: app, address: strip.faderPath, steps: 1023, tint: tint, label: nil)
                }
                if strip.kind != .dca {
                    MeterView(meter: app.meters.meter(strip))
                        .frame(width: 5)
                        .padding(.vertical, 18)
                }
            }
            FaderReadout(app: app, address: sendsBus.map { strip.sendLevelPath($0) } ?? strip.faderPath)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StripScribble: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let name = app.param(strip.namePath).string
        let color = app.param(strip.colorPath).int
        ScribbleView(name: name, colorIndex: color, number: strip.numberLabel, placeholder: strip.defaultName)
            .onTapGesture {
                app.openDetail(strip)
            }
            .accessibilityLabel("\(strip.shortLabel) \(name)")
            .accessibilityAddTraits(.isButton)
    }
}

struct MuteButton: View {
    let app: AppModel
    let strip: StripID
    var height: CGFloat = 32

    var body: some View {
        let muted = app.param(strip.onPath).int(or: 1) == 0
        LitButton(title: "MUTE", isOn: muted, color: Theme.mute, height: height) {
            app.toggleMute(strip)
        }
    }
}

struct SoloButton: View {
    let app: AppModel
    let strip: StripID
    var height: CGFloat = 26

    var body: some View {
        let solo = app.param(strip.soloPath).bool
        LitButton(title: "SOLO", isOn: solo, color: Theme.solo, height: height) {
            app.toggleSolo(strip)
        }
    }
}

struct SendOnButton: View {
    let app: AppModel
    let strip: StripID
    let bus: Int

    var body: some View {
        let address = strip.sendOnPath(bus)
        let on = app.param(address).int(or: 1) != 0
        LitButton(title: on ? "SEND ON" : "SEND OFF", isOn: on, color: Theme.on, height: 22, fontSize: 9) {
            app.setBool(address, !on)
        }
    }
}

struct ParamPan: View {
    let app: AppModel
    let address: String

    var body: some View {
        let p = app.param(address)
        PanControl(
            value: p.float(or: 0.5),
            onChange: { v in app.setFloat(address, v, steps: 100) },
            onTouch: { began in app.touch(address, began) }
        )
    }
}

/// A fader bound to one OSC address.
struct ParamFader: View {
    let app: AppModel
    let address: String
    let steps: Int
    var tint: Color = Theme.accent
    var label: String? = nil
    var maxValue: Float = 1

    var body: some View {
        let p = app.param(address)
        FaderView(
            value: p.float,
            tint: tint,
            maxValue: maxValue,
            showScale: app.settings.showFaderScale,
            hapticAtUnity: app.settings.hapticAtUnity,
            capLabel: label,
            onChange: { v in app.setFloat(address, v, steps: steps) },
            onTouch: { began in app.touch(address, began) }
        )
    }
}

struct FaderReadout: View {
    let app: AppModel
    let address: String

    var body: some View {
        let p = app.param(address)
        Text(p.isKnown ? X32Math.formatFader(p.float) : "—")
            .font(Theme.mono(12, .semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
    }
}

/// The right-hand master: Main LR normally, or the selected bus while in sends-on-faders.
struct MasterStrip: View {
    let app: AppModel

    var body: some View {
        if let bus = app.sendsBus, app.layer.supportsBusSends {
            MasterColumn(app: app, strip: StripID(.bus, bus), caption: "BUS MASTER", stereo: false)
        } else {
            MasterColumn(app: app, strip: StripID.mainLR, caption: "MAIN LR", stereo: true)
        }
    }
}

struct MasterColumn: View {
    let app: AppModel
    let strip: StripID
    let caption: String
    let stereo: Bool

    var body: some View {
        let tint = strip.kind == .bus ? Theme.scribble(app.param(strip.colorPath).int) : Theme.accent
        VStack(spacing: 6) {
            Text(caption)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Theme.tertiary)
            StripScribble(app: app, strip: strip)
            if let panPath = strip.panPath {
                ParamPan(app: app, address: panPath)
            }
            SoloButton(app: app, strip: strip)
            MuteButton(app: app, strip: strip)
            HStack(spacing: 4) {
                ParamFader(app: app, address: strip.faderPath, steps: 1023, tint: tint)
                MeterView(meter: app.meters.meter(strip), stereo: stereo)
                    .frame(width: stereo ? 12 : 6)
                    .padding(.vertical, 18)
            }
            FaderReadout(app: app, address: strip.faderPath)
        }
    }
}
