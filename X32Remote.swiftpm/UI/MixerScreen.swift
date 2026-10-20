import SwiftUI

/// How much of each strip fits on screen.
enum StripDetail: Int, Comparable {
    case compact, medium, full

    static func < (a: StripDetail, b: StripDetail) -> Bool { a.rawValue < b.rawValue }

    static func forHeight(_ h: CGFloat) -> StripDetail {
        if h >= 610 { return .full }
        if h >= 470 { return .medium }
        return .compact
    }
}

/// The console view: a bank of strips, the master of the selected mix, and on an iPad a
/// two-column panel down the right (Fine, Mute Enable, sends on fader | layers, mute groups).
struct MixerScreen: View {
    @Bindable var app: AppModel
    @State private var page = 0

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700
            let column: CGFloat = geo.size.width >= 1100 ? 100 : 86
            let sidebarWidth: CGFloat = wide ? column * 2 + 12 : 0
            let bodyHeight = geo.size.height - 46
            let stripsWidth = geo.size.width - sidebarWidth
            let layout = MixerScreen.pageLayout(strips: app.layer.strips, width: stripsWidth, page: page)
            let detail = StripDetail.forHeight(bodyHeight)
            VStack(spacing: 0) {
                MixerTopBar(app: app, wide: wide, page: $page, pageCount: layout.pageCount, perPage: layout.perPage, total: layout.total)
                HStack(spacing: 0) {
                    StripBank(app: app, strips: layout.visible, detail: detail, tallThumbs: bodyHeight > 900)
                    if wide {
                        MixerSidebar(app: app, column: column, page: $page, pageCount: layout.pageCount, perPage: layout.perPage, total: layout.total)
                            .frame(width: sidebarWidth)
                    }
                }
            }
        }
        .background(Theme.background)
        .onChange(of: app.layer) { _, _ in
            page = 0
        }
        .fullScreenCover(item: $app.detailStrip) { strip in
            ChannelView(app: app, strip: strip)
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

    /// Fits the whole layer (plus the master) when strips can be at least 52 pt wide, otherwise pages of 8.
    static func pageLayout(strips: [StripID], width: CGFloat, page: Int) -> PageLayout {
        let count = strips.count
        guard count > 0 else { return PageLayout(visible: [], pageCount: 1, perPage: 1, total: 0) }
        var perPage = count
        if width / CGFloat(count + 1) < 52 {
            if width / 9 >= 60 {
                perPage = min(8, count)
            } else {
                perPage = max(2, min(count, Int(width / 70) - 1))
            }
        }
        let pageCount = (count + perPage - 1) / perPage
        let current = min(max(page, 0), pageCount - 1)
        let start = current * perPage
        let end = min(count, start + perPage)
        return PageLayout(visible: Array(strips[start..<end]), pageCount: pageCount, perPage: perPage, total: count)
    }
}

/// The strips of the current layer, then the master of the selected mix.
private struct StripBank: View {
    let app: AppModel
    let strips: [StripID]
    let detail: StripDetail
    let tallThumbs: Bool

    var body: some View {
        let sendsBus = app.layer.supportsBusSends ? app.sendsBus : nil
        HStack(spacing: 1) {
            ForEach(strips) { strip in
                StripView(app: app, strip: strip, sendsBus: sendsBus, detail: detail, tallThumbs: tallThumbs)
            }
            Rectangle().fill(Color.black).frame(width: 3)
            if let bus = sendsBus {
                StripView(app: app, strip: StripID(.bus, bus), sendsBus: nil, detail: detail, tallThumbs: tallThumbs, isMaster: true)
            } else {
                StripView(app: app, strip: StripID.mainLR, sendsBus: nil, detail: detail, tallThumbs: tallThumbs, isMaster: true)
            }
        }
        .background(Color.black)
    }
}

// MARK: - Top bar

struct MixerTopBar: View {
    let app: AppModel
    let wide: Bool
    @Binding var page: Int
    let pageCount: Int
    let perPage: Int
    let total: Int
    @State private var showMuteGroups = false

    var body: some View {
        HStack(spacing: 4) {
            ConsoleMenu(app: app)
            Spacer(minLength: 8)
            if !wide {
                LayerMenu(app: app)
                SendsMenu(app: app)
                if pageCount > 1 {
                    PageButtons(page: $page, count: pageCount, perPage: perPage, total: total)
                }
                FineButton(app: app, height: 32)
                    .frame(width: 52)
            }
            TopIcon(systemName: "square.grid.3x2", label: "Mute groups") {
                showMuteGroups = true
            }
            .popover(isPresented: $showMuteGroups) {
                MuteGroupsPopover(app: app)
            }
            TopIcon(systemName: "folder", label: "Scenes") {
                app.loadScenes()
                app.sheet = .scenes
            }
            if wide {
                TopIcon(systemName: "rectangle.3.group", label: "Switch mode") {
                    app.sheet = .modes
                }
            }
            TopIcon(systemName: "gearshape", label: "Settings") {
                app.sheet = .settings
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .background(Theme.topBar)
    }
}

struct TopIcon: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Theme.text)
                .frame(width: 46, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// "Mixer / LR Mix" title. Tap it for the desk menu.
struct ConsoleMenu: View {
    let app: AppModel

    var body: some View {
        let mix: String = {
            guard let bus = app.sendsBus, app.layer.supportsBusSends else { return "LR Mix" }
            let name = app.param(StripID(.bus, bus).namePath).string
            return name.isEmpty ? "Mix \(bus)" : "Mix \(bus) · \(name)"
        }()
        let mixColor: Color = app.sendsBus.map { Theme.scribble(app.param(StripID(.bus, $0).colorPath).int) } ?? Theme.secondary
        Menu {
            Section(app.connectedName + (app.isDemo ? "" : " · " + app.connectedAddress)) {
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
                    .fill(app.linkLost ? Theme.mute : (app.isDemo ? Theme.solo : Theme.on))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Mixer")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text)
                    Text(mix)
                        .font(.system(size: 12))
                        .foregroundStyle(app.sendsBus == nil ? Theme.secondary : mixColor)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 90, alignment: .leading)
            .contentShape(Rectangle())
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
            Text(app.layer.title)
                .lineLimit(1)
                .fixedSize()
                .barChip(active: true)
        }
    }
}

struct SendsMenu: View {
    let app: AppModel

    var body: some View {
        let label: String = app.sendsBus.map { "Mix \($0)" } ?? "LR"
        Menu {
            Button {
                app.selectSendsBus(nil)
            } label: {
                if app.sendsBus == nil {
                    Label("LR Mix", systemImage: "checkmark")
                } else {
                    Text("LR Mix")
                }
            }
            Section("Sends on faders") {
                ForEach(1...16, id: \.self) { bus in
                    SendsMenuItem(app: app, bus: bus)
                }
            }
        } label: {
            Text(label)
                .lineLimit(1)
                .fixedSize()
                .barChip(active: app.sendsBus != nil)
        }
    }
}

private struct SendsMenuItem: View {
    let app: AppModel
    let bus: Int

    var body: some View {
        let name = app.param(StripID(.bus, bus).namePath).string
        let title = name.isEmpty ? "Mix \(bus)" : "Mix \(bus) · \(name)"
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
                        .barChip(active: page == p)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func label(_ p: Int) -> String {
        let first = p * perPage + 1
        let last = min(total, (p + 1) * perPage)
        return first == last ? "\(first)" : "\(first)-\(last)"
    }
}

private struct MuteGroupsPopover: View {
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mute groups")
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 8), count: 3), spacing: 8) {
                ForEach(1...6, id: \.self) { n in
                    MuteGroupButton(app: app, group: n, height: 52)
                }
            }
        }
        .padding(16)
        .background(Theme.panel)
        .presentationCompactAdaptation(.popover)
        .preferredColorScheme(.dark)
    }
}

struct MuteGroupButton: View {
    let app: AppModel
    let group: Int
    var height: CGFloat = 40

    var body: some View {
        let address = "/config/mute/\(group)"
        let on = app.param(address).bool
        LitButton(title: "MG \(group)", isOn: on, color: Theme.mute, height: height, fontSize: 13, offColor: Theme.muteOff) {
            app.setBool(address, !on)
        }
    }
}

// MARK: - Sidebar

/// Two columns: Fine / Mute Enable / sends-on-fader list on the left,
/// layers, mute groups and clear-solo on the right.
struct MixerSidebar: View {
    let app: AppModel
    let column: CGFloat
    @Binding var page: Int
    let pageCount: Int
    let perPage: Int
    let total: Int

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 4) {
                SideButton(title: "Fine", active: app.fineMode, style: .outline) {
                    app.fineMode.toggle()
                    Haptics.click()
                }
                SideButton(title: "Mute Enable", active: app.muteEnabled, style: .red) {
                    app.muteEnabled.toggle()
                    Haptics.click()
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        SideButton(title: "LR Mix", active: app.sendsBus == nil, stripe: Theme.solo) {
                            app.selectSendsBus(nil)
                        }
                        ForEach(1...16, id: \.self) { bus in
                            SoFButton(app: app, bus: bus)
                        }
                    }
                }
            }
            .frame(width: column)
            VStack(spacing: 4) {
                ForEach(MixerLayer.allCases) { layer in
                    SideButton(title: layer.title, active: app.layer == layer, stripe: MixerSidebar.stripe(layer)) {
                        app.selectLayer(layer)
                    }
                }
                if pageCount > 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<pageCount, id: \.self) { p in
                            SideButton(title: pageLabel(p), active: min(page, pageCount - 1) == p, height: 36) {
                                page = p
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                Text("Mute groups")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                    ForEach(1...6, id: \.self) { n in
                        MuteGroupButton(app: app, group: n, height: 34)
                    }
                }
                ClearSoloButton(app: app)
            }
            .frame(width: column)
        }
        .padding(4)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
    }

    static func stripe(_ layer: MixerLayer) -> Color {
        switch layer {
        case .inputs1, .inputs2: return Theme.on
        case .aux: return Color(red: 0.96, green: 0.62, blue: 0.22)
        case .buses: return Theme.scribble(6)
        case .matrix: return Theme.scribble(5)
        case .dca: return Theme.mute
        }
    }

    private func pageLabel(_ p: Int) -> String {
        let first = p * perPage + 1
        let last = min(total, (p + 1) * perPage)
        return "\(first)-\(last)"
    }
}

/// A sidebar button: dark, optional colour stripe on the left, green rim when selected.
struct SideButton: View {
    enum Style { case select, outline, red }

    let title: String
    let active: Bool
    var stripe: Color? = nil
    var style: Style = .select
    var height: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if let stripe {
                    Rectangle().fill(stripe).frame(width: 9)
                }
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(style == .red && active ? Color.white : Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(rim ? Theme.on : Color.white.opacity(0.07), lineWidth: rim ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rim: Bool { active && style != .red }

    private var fill: Color {
        if style == .red && active { return Theme.mute }
        return active ? Theme.raised2 : Theme.raised
    }
}

private struct SoFButton: View {
    let app: AppModel
    let bus: Int

    var body: some View {
        let strip = StripID(.bus, bus)
        let name = app.param(strip.namePath).string
        let color = Theme.scribble(app.param(strip.colorPath).int)
        SideButton(title: name.isEmpty ? "Mix \(bus)" : name, active: app.sendsBus == bus, stripe: color) {
            app.selectSendsBus(app.sendsBus == bus ? nil : bus)
        }
    }
}

struct ClearSoloButton: View {
    let app: AppModel

    var body: some View {
        let anySolo = app.param("/-stat/solo").bool
        LitButton(title: anySolo ? "Clear Solo" : "No Solo", isOn: anySolo, color: Theme.solo, height: 40, fontSize: 13, offColor: Theme.raised) {
            app.clearSolo()
        }
        .disabled(!anySolo)
    }
}

/// Makes every fader, pan and slider move 4x more slowly under your finger.
struct FineButton: View {
    let app: AppModel
    var height: CGFloat = 36

    var body: some View {
        LitButton(title: "Fine", isOn: app.fineMode, height: height, fontSize: 13, style: .outline) {
            app.fineMode.toggle()
            Haptics.click()
        }
    }
}

// MARK: - Strip

struct StripView: View {
    let app: AppModel
    let strip: StripID
    let sendsBus: Int?
    var detail: StripDetail = .full
    var tallThumbs = false
    var isMaster = false

    var body: some View {
        let selected = app.selectedStrip == strip
        let busColor: Color? = sendsBus.map { Theme.scribble(app.param(StripID(.bus, $0).colorPath).int) }
        let faderAddress = sendsBus.map { strip.sendLevelPath($0) } ?? strip.faderPath
        let thumb: CGFloat = tallThumbs ? 62 : 46
        VStack(spacing: 3) {
            if detail >= .medium {
                SourceChip(app: app, strip: strip, isMaster: isMaster)
                    .frame(height: 20)
                GainCell(app: app, strip: strip)
                    .frame(height: 30)
                StripLights(app: app, strip: strip)
                    .frame(height: 29)
            }
            if detail == .full {
                StripThumbs(app: app, strip: strip, height: thumb)
            }
            StripName(app: app, strip: strip)
            MuteButton(app: app, strip: strip, height: 28)
            SoloButton(app: app, strip: strip, height: 28)
            StripPanSlot(app: app, strip: strip, sendsBus: sendsBus)
                .frame(height: 22)
            FaderReadout(app: app, address: faderAddress)
            StripFader(app: app, strip: strip, address: faderAddress, steps: sendsBus == nil ? 1023 : 160, capTint: busColor)
            Text(strip.footLabel)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 14)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Theme.panel)
        .overlay(
            Rectangle().strokeBorder(selected ? Theme.on : Color.clear, lineWidth: 1.5)
        )
    }
}

private struct StripName: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let name = app.param(strip.namePath).string
        ScribbleView(name: name, colorIndex: app.param(strip.colorPath).int, placeholder: strip.defaultName, height: 32, fontSize: 11)
            .onTapGesture {
                app.openDetail(strip, tab: strip.kind == .dca ? .setup : .overview)
            }
            .accessibilityLabel("\(strip.shortLabel) \(name)")
            .accessibilityAddTraits(.isButton)
    }
}

private struct StripPanSlot: View {
    let app: AppModel
    let strip: StripID
    let sendsBus: Int?

    var body: some View {
        if let bus = sendsBus {
            SendOnButton(app: app, strip: strip, bus: bus)
        } else if let panPath = strip.panPath {
            ParamPan(app: app, address: panPath)
        } else {
            Color.clear
        }
    }
}

private struct StripFader: View {
    let app: AppModel
    let strip: StripID
    let address: String
    let steps: Int
    let capTint: Color?

    var body: some View {
        HStack(spacing: 2) {
            ParamFader(app: app, address: address, steps: steps, capTint: capTint)
            if strip.kind != .dca {
                MeterView(meter: app.meters.meter(strip), stereo: strip.kind == .main)
                    .frame(width: strip.kind == .main ? 11 : 6)
                    .padding(.vertical, 14)
                if strip.hasDynamics {
                    GRBar(reduction: app.meters.meter(strip).dynReduction)
                        .frame(width: 3)
                        .padding(.vertical, 14)
                }
            }
        }
    }
}

/// Where the channel's signal comes from ("Loc 01", "A 05"), in the channel colour.
private struct SourceChip: View {
    let app: AppModel
    let strip: StripID
    let isMaster: Bool

    var body: some View {
        let style = ScribbleStyle(colorIndex: app.param(strip.colorPath).int)
        Text(label)
            .font(.system(size: 11))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(style.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Rectangle().fill(style.fill))
    }

    private var label: String {
        if isMaster { return strip.kind == .main ? "Main" : "Bus master" }
        if let path = strip.headampIndexPath {
            let ha = app.param(path).int(or: -1)
            if ha >= 0 && ha < 128 {
                return StripSource.headampLabel(ha)
            }
            if strip.kind == .channel {
                let src = app.param(strip.sourcePath)
                return src.isKnown ? X32Enums.sourceName(src.int) : ""
            }
        }
        return strip.footLabel
    }
}

enum StripSource {
    /// Headamps 0-31 are the local inputs, 32-79 AES50 A, 80-127 AES50 B.
    static func headampLabel(_ ha: Int) -> String {
        switch ha {
        case 0..<32: return String(format: "Loc %02d", ha + 1)
        case 32..<80: return String(format: "A %02d", ha - 31)
        default: return String(format: "B %02d", ha - 79)
        }
    }
}

/// Preamp gain (or trim) with a small bar. Drag sideways to change it.
private struct GainCell: View {
    let app: AppModel
    let strip: StripID
    @State private var drag = DragTarget()

    var body: some View {
        let ha = strip.headampIndexPath.map { app.param($0).int(or: -1) } ?? -1
        if ha >= 0 && ha < 128 {
            let address = StripID.headampGainPath(ha)
            let p = app.param(address)
            MiniSlider(
                value: p.float(or: 0),
                display: p.isKnown ? Specs.headampGain.display(p.float) : "—",
                fine: app.fineMode,
                onChange: { v in app.dragSet(address, drag, v, steps: Specs.headampGain.steps) },
                onTouch: { began in
                    if began { app.beginDrag(address, drag) } else { app.endDrag(drag) }
                }
            )
        } else if strip.hasTrim {
            let address = strip.preampPath("trim")
            let p = app.param(address)
            MiniSlider(
                value: p.float(or: 0.5),
                display: p.isKnown ? Specs.trim.display(p.float) : "—",
                bipolar: true,
                fine: app.fineMode,
                onChange: { v in app.dragSet(address, drag, v, steps: Specs.trim.steps) },
                onTouch: { began in
                    if began { app.beginDrag(address, drag) } else { app.endDrag(drag) }
                }
            )
        } else {
            Color.clear
        }
    }
}

/// A tiny value-over-bar slider for the strip's gain.
struct MiniSlider: View {
    let value: Float
    let display: String
    var bipolar = false
    var fine = false
    let onChange: (Float) -> Void
    var onTouch: (Bool) -> Void = { _ in }

    @State private var dragValue: Float = 0
    @State private var lastPoint: CGPoint = .zero
    @State private var touching = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            VStack(spacing: 2) {
                Text(display)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                MiniBar(value: value, bipolar: bipolar, touching: touching)
                    .frame(height: 10)
            }
            .padding(.horizontal, 2)
            .frame(width: width, height: geo.size.height)
            .overlay(
                TouchSurface(
                    axis: .horizontal,
                    onBegin: { p in
                        touching = true
                        dragValue = value
                        lastPoint = p
                        onTouch(true)
                    },
                    onMove: { p in
                        let dx = p.x - lastPoint.x
                        lastPoint = p
                        var next = dragValue + Float(dx / 240) * (fine ? 0.25 : 1)
                        next = min(max(next, 0), 1)
                        dragValue = next
                        onChange(next)
                    },
                    onEnd: { _, _ in
                        touching = false
                        onTouch(false)
                    }
                )
            )
        }
        .onDisappear {
            if touching {
                touching = false
                onTouch(false)
            }
        }
    }
}

private struct MiniBar: View {
    let value: Float
    let bipolar: Bool
    let touching: Bool

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.black.opacity(0.35)))
            let v = CGFloat(min(max(value, 0), 1))
            let start = bipolar ? min(v, 0.5) : 0
            let end = bipolar ? max(v, 0.5) : v
            let fill = CGRect(x: 1 + start * (size.width - 2), y: 1, width: max(2, (end - start) * (size.width - 2)), height: size.height - 2)
            ctx.fill(Path(roundedRect: fill, cornerRadius: 1.5), with: .color(Theme.accent))
            ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2), with: .color(touching ? Theme.text : Color.white.opacity(0.14)), lineWidth: 1)
        }
    }
}

/// +48 / G / EQ / C. Gate, EQ and compressor toggle on tap; +48 opens the input page instead
/// (phantom power is never switched from the mixer by accident).
private struct StripLights: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let ha = strip.headampIndexPath.map { app.param($0).int(or: -1) } ?? -1
        let hasHeadamp = ha >= 0 && ha < 128
        let phantom = hasHeadamp && app.param(StripID.headampPhantomPath(ha)).bool
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                StripLight(text: "+48", on: phantom, color: Theme.mute, off: Theme.phantomOff, present: hasHeadamp) {
                    app.openDetail(strip, tab: .input)
                }
                StripLight(text: "G", on: strip.hasGate && app.param(strip.gatePath("on")).bool, color: Theme.on, off: Theme.raised2, present: strip.hasGate) {
                    toggle(strip.gatePath("on"))
                }
            }
            HStack(spacing: 2) {
                StripLight(text: "EQ", on: strip.hasEQ && app.param(strip.eqOnPath).bool, color: Theme.on, off: Theme.raised2, present: strip.hasEQ) {
                    toggle(strip.eqOnPath)
                }
                StripLight(text: "C", on: strip.hasDynamics && app.param(strip.dynPath("on")).bool, color: Theme.on, off: Theme.raised2, present: strip.hasDynamics) {
                    toggle(strip.dynPath("on"))
                }
            }
        }
    }

    private func toggle(_ address: String) {
        let p = app.param(address)
        guard p.isKnown else { return }
        app.setBool(address, !p.bool)
    }
}

private struct StripLight: View {
    let text: String
    let on: Bool
    let color: Color
    let off: Color
    let present: Bool
    let action: () -> Void

    var body: some View {
        if present {
            LitButton(title: text, isOn: on, color: color, height: 13.5, fontSize: 9, offColor: off, action: action)
        } else {
            Color.black.opacity(0.2)
                .frame(maxWidth: .infinity)
                .frame(height: 13.5)
        }
    }
}

/// Gate, EQ and compressor pictures. Tap one to open that page.
private struct StripThumbs: View {
    let app: AppModel
    let strip: StripID
    let height: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            ThumbSlot(app: app, strip: strip, tab: .gate, present: strip.hasGate, height: height) {
                GateGraph(app: app, strip: strip)
            }
            ThumbSlot(app: app, strip: strip, tab: .eq, present: strip.hasEQ, height: height) {
                EQThumb(app: app, strip: strip)
            }
            ThumbSlot(app: app, strip: strip, tab: .comp, present: strip.hasDynamics, height: height) {
                CompGraph(app: app, strip: strip)
            }
        }
    }
}

private struct ThumbSlot<Content: View>: View {
    let app: AppModel
    let strip: StripID
    let tab: DetailTab
    let present: Bool
    let height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if present {
            content
                .frame(height: height)
                .contentShape(Rectangle())
                .onTapGesture {
                    app.openDetail(strip, tab: tab)
                }
        } else {
            Theme.graphBack.opacity(0.4)
                .frame(height: height)
        }
    }
}

struct MuteButton: View {
    let app: AppModel
    let strip: StripID
    var height: CGFloat = 30

    var body: some View {
        let muted = app.param(strip.onPath).int(or: 1) == 0
        LitButton(title: "MUTE", isOn: muted, color: Theme.mute, height: height, fontSize: 12, offColor: Theme.muteOff, enabled: app.muteEnabled) {
            app.toggleMute(strip)
        }
    }
}

struct SoloButton: View {
    let app: AppModel
    let strip: StripID
    var height: CGFloat = 30

    var body: some View {
        let solo = app.param(strip.soloPath).bool
        LitButton(title: "SOLO", isOn: solo, color: Theme.solo, height: height, fontSize: 12, offColor: Theme.soloOff) {
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
        LitButton(title: on ? "ON" : "OFF", isOn: on, color: Theme.on, height: 22, fontSize: 10, offColor: Theme.raised) {
            app.setBool(address, !on)
        }
    }
}

struct ParamPan: View {
    let app: AppModel
    let address: String
    var height: CGFloat = 22
    @State private var drag = DragTarget()

    var body: some View {
        let p = app.param(address)
        PanControl(
            value: p.float(or: 0.5),
            height: height,
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
    var label: String? = nil
    var maxValue: Float = 1
    var capTint: Color? = nil
    @State private var drag = DragTarget()

    var body: some View {
        let p = app.param(address)
        FaderView(
            value: p.float,
            maxValue: maxValue,
            showScale: app.settings.showFaderScale,
            hapticAtUnity: app.settings.hapticAtUnity,
            capLabel: label,
            fine: app.fineMode,
            capTint: capTint,
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
    var size: CGFloat = 11

    var body: some View {
        let p = app.param(address)
        Text(p.isKnown ? X32Math.formatFader(p.float) : "—")
            .font(Theme.mono(size))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: 14)
    }
}
