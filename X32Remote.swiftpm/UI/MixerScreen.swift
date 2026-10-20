import SwiftUI

/// The full console view. On an iPad: strips, the master, and a control panel down the right
/// (layers, sends on fader, mute groups). On narrow screens the panel becomes a top bar.
struct MixerScreen: View {
    @Bindable var app: AppModel
    @State private var page = 0

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700
            let panelWidth: CGFloat = wide ? (geo.size.width >= 1100 ? 176 : 156) : 0
            let masterWidth: CGFloat = geo.size.width >= 1100 ? 92 : (wide ? 80 : 76)
            let stripsWidth = geo.size.width - panelWidth - masterWidth - 30
            let layout = MixerScreen.pageLayout(strips: app.layer.strips, width: stripsWidth, page: page)
            let overview = geo.size.height >= 600
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if !wide {
                        MixerTopBar(app: app, page: $page, pageCount: layout.pageCount, perPage: layout.perPage, total: layout.total)
                    }
                    if let bus = app.sendsBus, app.layer.supportsBusSends {
                        SendsBanner(app: app, bus: bus)
                    }
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            ForEach(layout.visible) { strip in
                                StripView(app: app, strip: strip, sendsBus: app.layer.supportsBusSends ? app.sendsBus : nil, overview: overview)
                            }
                        }
                        Rectangle()
                            .fill(Theme.line)
                            .frame(width: 1)
                            .padding(.vertical, 20)
                        MasterStrip(app: app, overview: overview)
                            .frame(width: masterWidth)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                }
                if wide {
                    MixerSidePanel(app: app, page: $page, pageCount: layout.pageCount, perPage: layout.perPage, total: layout.total)
                        .frame(width: panelWidth)
                }
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

    /// Shows a whole layer when strips can be at least 54 pt wide, otherwise pages of 8 (or fewer on phones).
    static func pageLayout(strips: [StripID], width: CGFloat, page: Int) -> PageLayout {
        let count = strips.count
        guard count > 0 else { return PageLayout(visible: [], pageCount: 1, perPage: 1, total: 0) }
        var perPage = count
        if width / CGFloat(count) < 54 {
            if width / 8 >= 56 {
                perPage = min(8, count)
            } else {
                perPage = max(3, min(count, Int(width / 64)))
            }
        }
        let pageCount = (count + perPage - 1) / perPage
        let current = min(max(page, 0), pageCount - 1)
        let start = current * perPage
        let end = min(count, start + perPage)
        return PageLayout(visible: Array(strips[start..<end]), pageCount: pageCount, perPage: perPage, total: count)
    }
}

// MARK: - Side panel (iPad)

struct MixerSidePanel: View {
    let app: AppModel
    @Binding var page: Int
    let pageCount: Int
    let perPage: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ConsoleMenu(app: app)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                FineButton(app: app)
                Button {
                    app.loadScenes()
                    app.sheet = .scenes
                } label: {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.raised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scenes")
            }

            PanelLabel("Mute groups")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                ForEach(1...6, id: \.self) { n in
                    MuteGroupButton(app: app, group: n, height: 34)
                }
            }

            PanelLabel("Layers")
            VStack(spacing: 4) {
                ForEach(MixerLayer.allCases) { layer in
                    PanelRow(title: layer.title, active: app.layer == layer, color: Theme.accent) {
                        app.selectLayer(layer)
                    }
                }
            }
            if pageCount > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<pageCount, id: \.self) { p in
                        PanelRow(title: pageLabel(p), active: min(page, pageCount - 1) == p, color: Theme.text, height: 32) {
                            page = p
                        }
                    }
                }
            }

            PanelLabel("Sends on fader")
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    PanelRow(title: "LR Mix", active: app.sendsBus == nil, color: Theme.accent) {
                        app.selectSendsBus(nil)
                    }
                    ForEach(1...16, id: \.self) { bus in
                        SendsBusRow(app: app, bus: bus)
                    }
                }
            }
            ClearSoloButton(app: app, fullWidth: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.line).frame(width: 1)
        }
    }

    private func pageLabel(_ p: Int) -> String {
        let first = p * perPage + 1
        let last = min(total, (p + 1) * perPage)
        return first == last ? "\(first)" : "\(first)–\(last)"
    }
}

private struct PanelLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(Theme.tertiary)
            .padding(.top, 2)
    }
}

/// A full-width selectable row in the side panel.
private struct PanelRow: View {
    let title: String
    let active: Bool
    let color: Color
    var swatch: Color? = nil
    var height: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let swatch {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(swatch)
                        .frame(width: 4, height: height - 14)
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .foregroundStyle(active ? Color.black.opacity(0.85) : Theme.text)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? color : Theme.raised)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SendsBusRow: View {
    let app: AppModel
    let bus: Int

    var body: some View {
        let strip = StripID(.bus, bus)
        let name = app.param(strip.namePath).string
        let color = Theme.scribble(app.param(strip.colorPath).int)
        PanelRow(title: name.isEmpty ? "Bus \(bus)" : "\(bus) · \(name)", active: app.sendsBus == bus, color: color, swatch: color) {
            app.selectSendsBus(app.sendsBus == bus ? nil : bus)
        }
    }
}

/// Makes every fader, pan and slider bar move 4× more slowly under your finger.
struct FineButton: View {
    let app: AppModel
    var height: CGFloat = 36

    var body: some View {
        LitButton(title: "FINE", isOn: app.fineMode, color: Theme.on, height: height, fontSize: 13) {
            app.fineMode.toggle()
            Haptics.click()
        }
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
            FineButton(app: app, height: 30)
                .frame(width: 64)
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
    var height: CGFloat = 30

    var body: some View {
        let address = "/config/mute/\(group)"
        let on = app.param(address).bool
        LitButton(title: "\(group)", isOn: on, color: Theme.mute, height: height, fontSize: 14) {
            app.setBool(address, !on)
        }
        .frame(minWidth: 40)
    }
}

struct ClearSoloButton: View {
    let app: AppModel
    var fullWidth = false

    var body: some View {
        let anySolo = app.param("/-stat/solo").bool
        if fullWidth {
            LitButton(title: anySolo ? "CLEAR SOLO" : "NO SOLO", isOn: anySolo, color: Theme.solo, height: 36, fontSize: 12) {
                app.clearSolo()
            }
            .disabled(!anySolo)
        } else {
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
    var overview: Bool = true
    var meterStereo: Bool = false
    var caption: String? = nil
    var tintOverride: Color? = nil

    var body: some View {
        let busTint: Color? = sendsBus.map { Theme.scribble(app.param(StripID(.bus, $0).colorPath).int) }
        let tint = tintOverride ?? busTint ?? Theme.accent
        let faderAddress = sendsBus.map { strip.sendLevelPath($0) } ?? strip.faderPath
        VStack(spacing: 5) {
            if overview {
                StripOverview(app: app, strip: strip, caption: caption)
            }
            StripScribble(app: app, strip: strip)
            MuteButton(app: app, strip: strip, height: 34)
            if let bus = sendsBus {
                SendOnButton(app: app, strip: strip, bus: bus)
            } else if let panPath = strip.panPath {
                StripPan(app: app, address: panPath)
            } else {
                Color.clear.frame(height: 36)
            }
            HStack(spacing: 3) {
                ParamFader(app: app, address: faderAddress, steps: sendsBus == nil ? 1023 : 160, tint: tint, label: sendsBus == nil ? nil : "SEND")
                if strip.kind != .dca {
                    MeterView(meter: app.meters.meter(strip), stereo: meterStereo)
                        .frame(width: meterStereo ? 14 : 8)
                        .padding(.vertical, 18)
                }
            }
            FaderReadout(app: app, address: faderAddress)
            SoloButton(app: app, strip: strip, height: 30)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Gain, processing lights and the little EQ / compressor pictures at the top of a strip.
/// Each part opens the matching channel page.
struct StripOverview: View {
    let app: AppModel
    let strip: StripID
    var caption: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            if let caption {
                Text(caption)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
            } else {
                StripGainCell(app: app, strip: strip)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                    .onTapGesture { open(.input) }
            }
            StripLights(app: app, strip: strip)
                .frame(height: 16)
            Group {
                if strip.hasEQ {
                    StripEQThumb(app: app, strip: strip)
                        .contentShape(Rectangle())
                        .onTapGesture { open(.eq) }
                } else {
                    ThumbPlaceholder()
                }
            }
            .frame(height: 30)
            Group {
                if strip.hasDynamics || strip.hasGate {
                    StripDynThumb(app: app, strip: strip)
                        .contentShape(Rectangle())
                        .onTapGesture { open(.dynamics) }
                } else {
                    ThumbPlaceholder()
                }
            }
            .frame(height: 24)
        }
    }

    private func open(_ tab: DetailTab) {
        let tabs = DetailTab.available(for: strip)
        guard tabs.contains(tab) else { return }
        app.detailTab = tab
        app.openDetail(strip)
        app.detailTab = tab
    }
}

private struct ThumbPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.black.opacity(0.18))
    }
}

/// Where the input comes from and its preamp gain, with a thin bar.
struct StripGainCell: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let ha = strip.headampIndexPath.map { app.param($0).int(or: -1) } ?? -1
        let hasHeadamp = ha >= 0 && ha < 128
        let gain = hasHeadamp ? app.param(StripID.headampGainPath(ha)) : nil
        let norm = gain?.float(or: 0) ?? 0
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(hasHeadamp ? StripGainCell.sourceLabel(ha) : (strip.hasTrim ? "TRIM" : ""))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(valueText(hasHeadamp: hasHeadamp, gain: gain))
                .font(Theme.mono(12, .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.raised2)
                    if hasHeadamp {
                        Capsule().fill(Theme.accent.opacity(0.85))
                            .frame(width: max(3, geo.size.width * CGFloat(min(max(norm, 0), 1))))
                    }
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black.opacity(0.25)))
        .opacity(strip.hasInputPage ? 1 : 0.35)
    }

    private func valueText(hasHeadamp: Bool, gain: Param?) -> String {
        if hasHeadamp, let gain, gain.isKnown {
            return Specs.headampGain.display(gain.float)
        }
        if strip.hasTrim {
            let trim = app.param(strip.preampPath("trim"))
            return trim.isKnown ? Specs.trim.display(trim.float) : "—"
        }
        return ""
    }

    /// Headamps 0-31 are the local inputs, 32-79 AES50 A, 80-127 AES50 B.
    static func sourceLabel(_ ha: Int) -> String {
        switch ha {
        case 0..<32: return "IN \(ha + 1)"
        case 32..<80: return "A\(ha - 31)"
        default: return "B\(ha - 79)"
        }
    }
}

/// +48 / gate / EQ / compressor status lights.
struct StripLights: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let ha = strip.headampIndexPath.map { app.param($0).int(or: -1) } ?? -1
        let phantom = ha >= 0 && ha < 128 && app.param(StripID.headampPhantomPath(ha)).bool
        HStack(spacing: 2) {
            Light(text: "48", on: phantom, color: Theme.mute, present: ha >= 0 && ha < 128)
            Light(text: "G", on: strip.hasGate && app.param(strip.gatePath("on")).bool, color: Theme.on, present: strip.hasGate)
            Light(text: "EQ", on: strip.hasEQ && app.param(strip.eqOnPath).bool, color: Theme.accent, present: strip.hasEQ)
            Light(text: "C", on: strip.hasDynamics && app.param(strip.dynPath("on")).bool, color: Theme.accent, present: strip.hasDynamics)
        }
    }

    private struct Light: View {
        let text: String
        let on: Bool
        let color: Color
        let present: Bool

        var body: some View {
            Text(present ? text : "")
                .font(.system(size: 8, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(on ? Color.black.opacity(0.85) : Theme.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(on ? color : Theme.raised.opacity(present ? 1 : 0.4))
                )
        }
    }
}

/// A tiny drawing of the channel's EQ curve (including the low cut).
struct StripEQThumb: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let eqOn = app.param(strip.eqOnPath).bool
        let bands: [EQBandValues] = (1...max(strip.eqBandCount, 1)).map { band in
            EQBandValues(
                band: band,
                type: app.param(strip.eqPath(band, "type")).int(or: 2),
                freqNorm: app.param(strip.eqPath(band, "f")).float(or: 0.5),
                gainNorm: app.param(strip.eqPath(band, "g")).float(or: 0.5),
                qNorm: app.param(strip.eqPath(band, "q")).float(or: 0.5)
            )
        }
        let lowCut: (Double, Int)? = strip.hasHighPass && app.param(strip.preampPath("hpon")).bool
            ? (Double(Specs.hpf.value(app.param(strip.preampPath("hpf")).float(or: 0))), app.param(strip.preampPath("hpslope")).int)
            : nil
        let bandCount = strip.eqBandCount
        Canvas { ctx, size in
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5), with: .color(Color.black.opacity(0.35)))
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: size.height / 2))
            zero.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(zero, with: .color(Color.white.opacity(0.1)), lineWidth: 1)
            let steps = 36
            var curve = Path()
            for i in 0..<steps {
                let norm = Double(i) / Double(steps - 1)
                let f = 20 * pow(1000, norm)
                var db: Double = 0
                if eqOn {
                    for b in bands {
                        db += EQMath.bandDB(type: b.type, band: b.band, bandCount: bandCount, freq: Double(b.freq), gain: Double(b.gain), q: Double(b.q), at: f)
                    }
                }
                if let lc = lowCut {
                    db += EQMath.lowCutDB(freq: lc.0, slope: lc.1, at: f)
                }
                let clamped = max(min(db, 18), -18)
                let point = CGPoint(x: CGFloat(norm) * size.width, y: size.height / 2 - CGFloat(clamped / 18) * (size.height / 2 - 2))
                if i == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            ctx.stroke(curve, with: .color(eqOn || lowCut != nil ? Theme.accent : Theme.tertiary), lineWidth: 1.5)
        }
        .accessibilityLabel("EQ")
        .accessibilityAddTraits(.isButton)
    }
}

/// A tiny compressor transfer curve with a gain-reduction bar.
struct StripDynThumb: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let on = strip.hasDynamics && app.param(strip.dynPath("on")).bool
        let threshold = strip.hasDynamics ? Double(Specs.dynThreshold.value(app.param(strip.dynPath("thr")).float(or: 1))) : 0
        let ratioIndex = min(max(app.param(strip.dynPath("ratio")).int(or: 3), 0), X32Enums.ratioValues.count - 1)
        let ratio = Double(X32Enums.ratioValues[ratioIndex])
        let reduction = Double(app.meters.meter(strip).dynReduction)
        Canvas { ctx, size in
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5), with: .color(Color.black.opacity(0.35)))
            let barWidth: CGFloat = 5
            let plot = CGRect(x: 3, y: 2, width: size.width - barWidth - 8, height: size.height - 4)
            let range: Double = 60
            func x(_ db: Double) -> CGFloat { plot.minX + CGFloat((db + range) / range) * plot.width }
            func y(_ db: Double) -> CGFloat { plot.maxY - CGFloat((db + range) / range) * plot.height }
            var curve = Path()
            curve.move(to: CGPoint(x: x(-range), y: y(-range)))
            if on && threshold > -range {
                curve.addLine(to: CGPoint(x: x(threshold), y: y(threshold)))
                curve.addLine(to: CGPoint(x: x(0), y: y(threshold + (0 - threshold) / ratio)))
            } else {
                curve.addLine(to: CGPoint(x: x(0), y: y(0)))
            }
            ctx.stroke(curve, with: .color(on ? Theme.accent : Theme.tertiary), lineWidth: 1.5)
            let track = CGRect(x: size.width - barWidth - 3, y: 2, width: barWidth, height: size.height - 4)
            ctx.fill(Path(roundedRect: track, cornerRadius: 1.5), with: .color(Theme.raised2))
            if on && reduction > 0.2 {
                let h = track.height * CGFloat(min(reduction, 24) / 24)
                ctx.fill(Path(roundedRect: CGRect(x: track.minX, y: track.minY, width: barWidth, height: h), cornerRadius: 1.5), with: .color(Theme.solo))
            }
        }
        .accessibilityLabel("Dynamics")
        .accessibilityAddTraits(.isButton)
    }
}

/// Pan control with its value underneath.
struct StripPan: View {
    let app: AppModel
    let address: String

    var body: some View {
        VStack(spacing: 2) {
            ParamPan(app: app, address: address)
            Text(panText(app.param(address).float(or: 0.5)))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 12)
        }
        .frame(height: 36)
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
        LitButton(title: on ? "SEND ON" : "SEND OFF", isOn: on, color: Theme.on, height: 36, fontSize: 9) {
            app.setBool(address, !on)
        }
    }
}

struct ParamPan: View {
    let app: AppModel
    let address: String
    @State private var drag = DragTarget()

    var body: some View {
        let p = app.param(address)
        PanControl(
            value: p.float(or: 0.5),
            fine: app.fineMode,
            onChange: { v in app.dragSet(address, drag, v, steps: 100) },
            onTouch: { began in
                if began { app.beginDrag(address, drag) } else { app.endDrag(drag) }
            }
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
    @State private var drag = DragTarget()

    var body: some View {
        let p = app.param(address)
        FaderView(
            value: p.float,
            tint: tint,
            maxValue: maxValue,
            showScale: app.settings.showFaderScale,
            hapticAtUnity: app.settings.hapticAtUnity,
            capLabel: label,
            fine: app.fineMode,
            onChange: { v in app.dragSet(address, drag, v, steps: steps) },
            onTouch: { began in
                if began { app.beginDrag(address, drag) } else { app.endDrag(drag) }
            }
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
    var overview: Bool = true

    var body: some View {
        if let bus = app.sendsBus, app.layer.supportsBusSends {
            let strip = StripID(.bus, bus)
            StripView(app: app, strip: strip, sendsBus: nil, overview: overview, caption: "BUS \(bus)\nMASTER",
                      tintOverride: Theme.scribble(app.param(strip.colorPath).int))
        } else {
            StripView(app: app, strip: StripID.mainLR, sendsBus: nil, overview: overview, meterStereo: true, caption: "MAIN\nLR")
        }
    }
}
