import SwiftUI

/// The channel view: a block bar across the top (Overview, Input, Gate, EQ, Comp, Sends, Config)
/// with a live picture of each block, the selected page, and the channel's strip down the right.
struct ChannelView: View {
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
            let wide = geo.size.width >= 700
            VStack(spacing: 0) {
                ChannelHeader(app: app, strip: $strip, tab: tab) {
                    dismiss()
                }
                BlockBar(app: app, strip: strip, tabs: tabs, tab: tab, wide: wide)
                    .frame(height: 58)
                HStack(spacing: 0) {
                    ChannelPage(app: app, strip: strip, tab: tab, wide: wide)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if wide {
                        ChannelSideStrip(app: app, strip: strip)
                            .frame(width: 100)
                    }
                }
                if !wide {
                    CompactStripBar(app: app, strip: strip)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            ToastView(app: app)
        }
        .overlay {
            ValueEditorOverlay(app: app)
        }
        .animation(.easeOut(duration: 0.15), value: app.valueEditor?.id)
        .preferredColorScheme(.dark)
        .onAppear {
            app.visibleDetailStrip = strip
        }
        .onDisappear {
            app.visibleDetailStrip = nil
        }
        .onChange(of: strip) { _, newStrip in
            app.visibleDetailStrip = newStrip
            app.selectedStrip = newStrip
            app.loadDetail(newStrip)
            app.selectOnDesk(newStrip)
        }
    }
}

private struct ChannelPage: View {
    let app: AppModel
    let strip: StripID
    let tab: DetailTab
    let wide: Bool

    var body: some View {
        switch tab {
        case .overview:
            OverviewPage(app: app, strip: strip, wide: wide)
        case .input:
            InputPage(app: app, strip: strip)
        case .gate:
            GatePage(app: app, strip: strip, wide: wide)
        case .eq:
            EQPage(app: app, strip: strip, wide: wide)
        case .comp:
            CompPage(app: app, strip: strip, wide: wide)
        case .sends:
            SendsPage(app: app, strip: strip)
        case .setup:
            SetupPage(app: app, strip: strip)
        }
    }
}

// MARK: - Header

private struct ChannelHeader: View {
    let app: AppModel
    @Binding var strip: StripID
    let tab: DetailTab
    let close: () -> Void

    var body: some View {
        let name = app.param(strip.namePath).string
        HStack(spacing: 4) {
            Button(action: close) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .regular))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name.isEmpty ? strip.footLabel : name)
                            .font(.system(size: 15))
                            .lineLimit(1)
                        Text(tab == .overview ? "Overview" : tab.title)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .foregroundStyle(Theme.text)
                .frame(minWidth: 120, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            Spacer(minLength: 8)
            if ProcessingSection.allCases.contains(where: { strip.supports($0) }) {
                CopyPasteMenu(app: app, strip: strip)
            }
            UndoButton(app: app)
            FineButton(app: app, height: 34)
                .frame(width: 64)
                .padding(.trailing, 6)
            TopIcon(systemName: "arrow.left", label: "Previous channel") {
                step(-1)
            }
            .disabled(strip.kind.count <= 1)
            TopIcon(systemName: "arrow.right", label: "Next channel") {
                step(1)
            }
            .disabled(strip.kind.count <= 1)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(Theme.topBar)
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

/// Copy this channel's processing, or paste what was copied from another channel.
private struct CopyPasteMenu: View {
    let app: AppModel
    let strip: StripID
    @State private var naming = false
    @State private var presetName = ""
    @State private var deleting: ChannelPreset?
    @State private var confirmDelete = false

    var body: some View {
        let available = ProcessingSection.allCases.filter { strip.supports($0) }
        Menu {
            Section("Copy from \(app.stripTitle(strip))") {
                Button("Copy everything") {
                    app.copySettings(from: strip, sections: available)
                }
                ForEach(available) { section in
                    Button("Copy \(section.title)") {
                        app.copySettings(from: strip, sections: [section])
                    }
                }
            }
            if let clip = app.clipboard, clip.source != strip {
                let sections = clip.sections(for: strip)
                if !sections.isEmpty {
                    Section("From \(app.stripTitle(clip.source))") {
                        Button {
                            app.pasteSettings(onto: strip)
                        } label: {
                            Label("Paste \(sections.map(\.title).joined(separator: ", "))", systemImage: "doc.on.clipboard")
                        }
                    }
                }
            }
            Section("Presets") {
                Button {
                    let name = app.param(strip.namePath).string
                    presetName = name.isEmpty ? app.stripTitle(strip) : name
                    naming = true
                } label: {
                    Label("Save as preset…", systemImage: "square.and.arrow.down")
                }
                if !app.presets.isEmpty {
                    Menu {
                        ForEach(app.presets) { preset in
                            PresetMenu(app: app, strip: strip, preset: preset) {
                                deleting = preset
                                confirmDelete = true
                            }
                        }
                    } label: {
                        Label("Load preset", systemImage: "tray.and.arrow.up")
                    }
                }
            }
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 18))
                .foregroundStyle(Theme.text)
                .frame(width: 46, height: 42)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Copy, paste and presets")
        .alert("Save preset", isPresented: $naming) {
            TextField("Name", text: $presetName)
            Button("Save") {
                // Blank names are ignored by savePreset.
                app.savePreset(name: presetName, from: strip)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps \(app.stripTitle(strip))'s preamp, gate, EQ and compressor on this device. A preset with the same name is replaced.")
        }
        .confirmationDialog("Delete preset \"\(deleting?.name ?? "")\"?",
                            isPresented: $confirmDelete, titleVisibility: .visible, presenting: deleting) { preset in
            Button("Delete", role: .destructive) {
                app.deletePreset(preset)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// One preset in the Load menu: load all of it, or just one section.
private struct PresetMenu: View {
    let app: AppModel
    let strip: StripID
    let preset: ChannelPreset
    let delete: () -> Void

    var body: some View {
        let fits = preset.clip.sections(for: strip)
        Menu {
            if fits.isEmpty {
                Text("Nothing in it fits this channel")
            } else {
                Button("Load \(fits.map(\.title).joined(separator: ", "))") {
                    app.loadPreset(preset, onto: strip)
                }
                if fits.count > 1 {
                    ForEach(fits) { section in
                        Button("Load \(section.title) only") {
                            app.loadPreset(preset, only: [section], onto: strip)
                        }
                    }
                }
            }
            Button("Delete preset…", role: .destructive, action: delete)
        } label: {
            Text(preset.name)
        }
    }
}

// MARK: - Block bar

/// One tile per processing block, each showing a live miniature. Tap to open that page.
private struct BlockBar: View {
    let app: AppModel
    let strip: StripID
    let tabs: [DetailTab]
    let tab: DetailTab
    let wide: Bool

    var body: some View {
        GeometryReader { geo in
            let weights = tabs.map { BlockBar.weight($0) }
            let total = weights.reduce(0, +)
            let spacing: CGFloat = 2
            let available = max(0, geo.size.width - spacing * CGFloat(max(tabs.count - 1, 0)) - 4)
            let fitted = available / CGFloat(max(total, 0.01))
            let unit = wide ? fitted : max(fitted, 78)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(tabs) { t in
                        BlockTile(app: app, strip: strip, block: t, selected: t == tab)
                            .frame(width: unit * CGFloat(BlockBar.weight(t)))
                            .onTapGesture {
                                app.detailTab = t
                            }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
            }
            .scrollDisabled(unit == fitted)
        }
        .background(Color.black)
    }

    static func weight(_ t: DetailTab) -> Double {
        switch t {
        case .overview: return 1.1
        case .input: return 1.2
        case .gate: return 1.0
        case .eq: return 1.4
        case .comp: return 1.0
        case .sends: return 1.4
        case .setup: return 0.9
        }
    }
}

private struct BlockTile: View {
    let app: AppModel
    let strip: StripID
    let block: DetailTab
    let selected: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(selected ? Theme.selected : Theme.panel)
            content
        }
        .overlay(Rectangle().strokeBorder(selected ? Color.white.opacity(0.25) : Theme.line, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(block.title)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch block {
        case .overview:
            Text("OVERVIEW")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .input:
            InputBlock(app: app, strip: strip)
                .padding(4)
        case .gate:
            GraphBlock(title: "Gate", on: app.param(strip.gatePath("on")).bool) {
                GateGraph(app: app, strip: strip)
            }
        case .eq:
            GraphBlock(title: "EQ", on: app.param(strip.eqOnPath).bool) {
                EQThumb(app: app, strip: strip, showsZeroLine: false)
            }
        case .comp:
            GraphBlock(title: "Comp", on: app.param(strip.dynPath("on")).bool) {
                CompGraph(app: app, strip: strip)
            }
        case .sends:
            GraphBlock(title: "Sends", on: true) {
                SendsMini(app: app, strip: strip)
            }
        case .setup:
            ConfigBlock(app: app, strip: strip)
        }
    }
}

private struct BlockLabel: View {
    let title: String
    let on: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 10))
            .foregroundStyle(on ? Color.black.opacity(0.8) : Theme.text.opacity(0.8))
            .padding(.horizontal, 7)
            .frame(height: 13)
            .background(RoundedRectangle(cornerRadius: 2).fill(on ? Theme.on : Theme.raised2))
    }
}

private struct GraphBlock<Graph: View>: View {
    let title: String
    let on: Bool
    @ViewBuilder var graph: Graph

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            BlockLabel(title: title, on: on)
            graph
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(4)
    }
}

private struct InputBlock: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let ha = strip.headampIndexPath.map { app.param($0).int(or: -1) } ?? -1
        let hasHeadamp = ha >= 0 && ha < 128
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                chip("+48V", on: hasHeadamp && app.param(StripID.headampPhantomPath(ha)).bool, color: Theme.mute, off: Theme.phantomOff)
                chip("Ø", on: strip.hasPolarity && app.param(strip.preampPath("invert")).bool, color: Theme.on, off: Theme.raised2)
            }
            HStack(spacing: 3) {
                chip("LC", on: strip.hasHighPass && app.param(strip.preampPath("hpon")).bool, color: Theme.on, off: Theme.raised2)
                if strip.hasDelay {
                    chip("Dly", on: app.param(strip.delayPath("on")).bool, color: Theme.on, off: Theme.raised2)
                }
                Text(hasHeadamp ? Specs.headampGain.display(app.param(StripID.headampGainPath(ha)).float(or: 0)) : "")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.text.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func chip(_ text: String, on: Bool, color: Color, off: Color) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(on ? Color.black.opacity(0.8) : Theme.text.opacity(0.8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 2).fill(on ? color : off))
    }
}

/// Miniature of every send level as little vertical bars.
private struct SendsMini: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let count = strip.sendCount
        let levels: [(Float, Bool, Color)] = (0..<count).map { i in
            let n = i + 1
            let target = strip.sendsFeedMatrix ? StripID(.matrix, n) : StripID(.bus, n)
            return (app.param(strip.sendLevelPath(n)).float(or: 0), app.param(strip.sendOnPath(n)).int(or: 1) != 0, Theme.scribble(app.param(target.colorPath).int))
        }
        Canvas { ctx, size in
            guard !levels.isEmpty else { return }
            let w = size.width / CGFloat(levels.count)
            for (i, item) in levels.enumerated() {
                let r = CGRect(x: CGFloat(i) * w + 1, y: 0, width: max(1, w - 2), height: size.height)
                ctx.stroke(Path(r), with: .color(Color.white.opacity(0.12)), lineWidth: 1)
                let h = size.height * CGFloat(min(max(item.0, 0), 1))
                if h > 0.5 {
                    ctx.fill(Path(CGRect(x: r.minX + 1, y: size.height - h, width: max(1, r.width - 2), height: h)), with: .color(item.2.opacity(item.1 ? 1 : 0.3)))
                }
            }
        }
    }
}

private struct ConfigBlock: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let style = ScribbleStyle(colorIndex: app.param(strip.colorPath).int)
        VStack(spacing: 4) {
            BlockLabel(title: "Config", on: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(strip.footLabel)
                .font(.system(size: 10))
                .foregroundStyle(style.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 2).fill(style.fill))
        }
        .padding(4)
    }
}

// MARK: - Right-hand strip

struct ChannelSideStrip: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        VStack(spacing: 5) {
            if let pan = strip.panPath {
                ParamPan(app: app, address: pan, height: 38, editTitle: "\(app.stripTitle(strip)) · Pan")
            } else {
                Color.clear.frame(height: 38)
            }
            MuteButton(app: app, strip: strip, height: 40)
            SoloButton(app: app, strip: strip, height: 40)
            FaderReadout(app: app, address: strip.faderPath, size: 12)
            HStack(spacing: 2) {
                ParamFader(app: app, address: strip.faderPath, steps: 1023, editTitle: "\(app.stripTitle(strip)) · Fader")
                if strip.kind != .dca {
                    MeterView(meter: app.meters.meter(strip), stereo: strip.kind == .main)
                        .frame(width: strip.kind == .main ? 12 : 8)
                        .padding(.vertical, 16)
                }
            }
            Text(strip.footLabel)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text.opacity(0.8))
        }
        .padding(6)
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
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
        HStack(spacing: 8) {
            MuteButton(app: app, strip: strip, height: 40)
                .frame(width: 64)
            SoloButton(app: app, strip: strip, height: 40)
                .frame(width: 64)
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
            FaderReadout(app: app, address: strip.faderPath, size: 12)
                .frame(width: 48)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.panel)
    }
}

// MARK: - Overview

/// Every block of the channel side by side, like a channel strip on a big desk.
struct OverviewPage: View {
    let app: AppModel
    let strip: StripID
    let wide: Bool

    private enum Column: Hashable {
        case config, gate, eq, comp, sends

        var weight: CGFloat {
            switch self {
            case .config: return 0.75
            case .gate, .comp: return 1
            case .eq: return 1.45
            case .sends: return 1.15
            }
        }
    }

    private var columns: [Column] {
        var c: [Column] = [.config]
        if strip.hasGate { c.append(.gate) }
        if strip.hasEQ { c.append(.eq) }
        if strip.hasDynamics { c.append(.comp) }
        if strip.sendCount > 0 { c.append(.sends) }
        return c
    }

    var body: some View {
        let cols = columns
        if wide {
            GeometryReader { geo in
                let usable = max(0, geo.size.width - 4 - CGFloat(cols.count - 1) * 2)
                // The config column's buttons need ~120 pt; the rest share what's left by weight.
                let configWidth = min(usable, max(124, usable * Column.config.weight / cols.reduce(0) { $0 + $1.weight }))
                let others = cols.filter { $0 != .config }
                let otherTotal = max(others.reduce(0) { $0 + $1.weight }, 0.01)
                let rest = max(0, usable - configWidth)
                HStack(spacing: 2) {
                    ForEach(cols, id: \.self) { c in
                        column(c)
                            .frame(width: c == .config ? configWidth : rest * c.weight / otherTotal)
                    }
                }
                .padding(2)
            }
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(cols, id: \.self) { c in
                        column(c)
                            .frame(minHeight: c == .config ? 260 : 380)
                    }
                }
                .padding(2)
            }
        }
    }

    @ViewBuilder
    private func column(_ c: Column) -> some View {
        switch c {
        case .config:
            ConfigColumn(app: app, strip: strip)
        case .gate:
            Cell { GateColumn(app: app, strip: strip) }
        case .eq:
            Cell { EQColumn(app: app, strip: strip) }
        case .comp:
            Cell { CompColumn(app: app, strip: strip) }
        case .sends:
            Cell { SendsColumn(app: app, strip: strip) }
        }
    }
}

private struct ConfigColumn: View {
    let app: AppModel
    let strip: StripID
    @State private var confirmPhantom = false

    var body: some View {
        let ha = strip.headampIndexPath.map { app.param($0).int(or: -1) } ?? -1
        let hasHeadamp = ha >= 0 && ha < 128
        let phantomOn = hasHeadamp && app.param(StripID.headampPhantomPath(ha)).bool
        Cell {
            VStack(spacing: 14) {
                Button {
                    app.detailTab = .setup
                } label: {
                    Text("CONFIG")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .frame(width: 96, height: 46)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.raised2))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                if hasHeadamp {
                    ParamKnob(app: app, address: StripID.headampGainPath(ha), spec: Specs.headampGain, title: "Gain")
                }
                if strip.hasTrim {
                    ParamKnob(app: app, address: strip.preampPath("trim"), spec: Specs.trim, title: "Trim", bipolar: true, resettable: true)
                }
                if !strip.hasInputPage {
                    MainAssignButtons(app: app, strip: strip)
                }
                // The input level fills the middle, so gain can be set by eye.
                HStack(spacing: 6) {
                    MeterView(meter: app.meters.meter(strip), stereo: strip.kind == .main)
                        .frame(width: 14)
                    VStack {
                        Text("0").frame(maxHeight: .infinity, alignment: .top)
                        Text("-60").frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
                }
                .frame(maxHeight: .infinity)
                .padding(.vertical, 4)
                .accessibilityHidden(true)
                if strip.hasPolarity {
                    OnSwitch(app: app, address: strip.preampPath("invert"), title: "Ø", width: 96)
                        .frame(height: 46)
                }
                if hasHeadamp {
                    LitButton(title: "+48V", isOn: phantomOn, color: Theme.mute, height: 46, fontSize: 13, offColor: Theme.phantomOff) {
                        confirmPhantom = true
                    }
                    .frame(width: 96)
                }
            }
            .padding(10)
        }
        .phantomConfirm(isPresented: $confirmPhantom, on: phantomOn) {
            if hasHeadamp {
                app.setBool(StripID.headampPhantomPath(ha), !phantomOn)
            }
        }
    }
}

private struct MainAssignButtons: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        VStack(spacing: 8) {
            if let lr = strip.lrAssignPath {
                OnSwitch(app: app, address: lr, title: "LR", width: 96)
            }
            if let mono = strip.monoAssignPath {
                OnSwitch(app: app, address: mono, title: "M/C", width: 96)
            }
        }
    }
}

extension View {
    /// Asks before switching 48 V phantom power either way.
    func phantomConfirm(isPresented: Binding<Bool>, on: Bool, perform: @escaping () -> Void) -> some View {
        alert(on ? "Turn off 48V phantom power?" : "Turn on 48V phantom power?", isPresented: isPresented) {
            Button(on ? "Turn off 48V" : "Turn on 48V", role: .destructive, action: perform)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(on
                 ? "Condenser mics and DI boxes on this input will go silent."
                 : "Phantom power can damage ribbon mics and some line-level gear. Pull the channel down first.")
        }
    }
}

private struct GateColumn: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let on = app.param(strip.gatePath("on")).bool
        VStack(spacing: 10) {
            OnToggle(app: app, address: strip.gatePath("on"))
            GateGraph(app: app, strip: strip, detailed: true)
                .aspectRatio(1, contentMode: .fit)
                .onTapGesture { app.detailTab = .gate }
            ParamKnob(app: app, address: strip.gatePath("thr"), spec: Specs.gateThreshold, title: "Thr", enabled: on)
            ParamKnob(app: app, address: strip.gatePath("range"), spec: Specs.gateRange, title: "Depth", enabled: on)
            ParamKnob(app: app, address: strip.gatePath("attack"), spec: Specs.attack, title: "Attack", enabled: on)
            ParamKnob(app: app, address: strip.gatePath("release"), spec: Specs.release, title: "Release", enabled: on)
            Spacer(minLength: 0)
        }
        .padding(8)
    }
}

private struct EQColumn: View {
    let app: AppModel
    let strip: StripID

    static func bandName(_ b: Int, of count: Int) -> String {
        let names = count >= 6 ? ["Low", "Low 2", "Lo-mid", "Hi-mid", "High 2", "High"] : ["Low", "Lo-mid", "Hi-mid", "High"]
        return b - 1 < names.count ? names[b - 1] : "Band \(b)"
    }

    var body: some View {
        VStack(spacing: 10) {
            OnToggle(app: app, address: strip.eqOnPath)
            EQGraph(app: app, strip: strip, selectedBand: .constant(0), interactive: false)
                .aspectRatio(1.4, contentMode: .fit)
                .contentShape(Rectangle())
                .onTapGesture { app.detailTab = .eq }
            if strip.hasHighPass {
                HStack(spacing: 8) {
                    OnSwitch(app: app, address: strip.preampPath("hpon"), title: "Lowcut", width: 84)
                        .frame(height: 34)
                    ParamKnob(app: app, address: strip.preampPath("hpf"), spec: Specs.hpf, title: "Freq",
                              enabled: app.param(strip.preampPath("hpon")).bool)
                }
            }
            // Quick gain for each band; the EQ page has frequency, Q and type.
            ForEach(1...max(strip.eqBandCount, 1), id: \.self) { b in
                ParamKnob(app: app, address: strip.eqPath(b, "g"), spec: Specs.eqGain, title: EQColumn.bandName(b, of: strip.eqBandCount),
                          bipolar: true, tint: EQColors.band(b), resettable: true)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
    }
}

private struct CompColumn: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let on = app.param(strip.dynPath("on")).bool
        VStack(spacing: 10) {
            OnToggle(app: app, address: strip.dynPath("on"))
            CompGraph(app: app, strip: strip, detailed: true)
                .aspectRatio(1, contentMode: .fit)
                .onTapGesture { app.detailTab = .comp }
            ParamKnob(app: app, address: strip.dynPath("thr"), spec: Specs.dynThreshold, title: "Thr", enabled: on)
            EnumKnob(app: app, address: strip.dynPath("ratio"), options: X32Enums.ratios, title: "Ratio", suffix: ":1", enabled: on)
            ParamKnob(app: app, address: strip.dynPath("attack"), spec: Specs.attack, title: "Attack", enabled: on)
            ParamKnob(app: app, address: strip.dynPath("release"), spec: Specs.release, title: "Release", enabled: on)
            ParamKnob(app: app, address: strip.dynPath("mgain"), spec: Specs.makeup, title: "Gain", enabled: on)
            Spacer(minLength: 0)
        }
        .padding(8)
    }
}

private struct SendsColumn: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(1...max(strip.sendCount, 1), id: \.self) { n in
                    SendSlider(app: app, strip: strip, n: n)
                }
            }
            .padding(8)
        }
    }
}

/// One send as a coloured slider; shows "Off" when the send is switched off.
private struct SendSlider: View {
    let app: AppModel
    let strip: StripID
    let n: Int
    @State private var drag = DragTarget()

    var body: some View {
        let target = strip.sendsFeedMatrix ? StripID(.matrix, n) : StripID(.bus, n)
        let name = app.param(target.namePath).string
        let color = Theme.scribble(app.param(target.colorPath).int)
        let address = strip.sendLevelPath(n)
        let level = app.param(address)
        let on = app.param(strip.sendOnPath(n)).int(or: 1) != 0
        BarSlider(
            title: name.isEmpty ? target.footLabel : name,
            value: level.float,
            display: !level.isKnown ? "—" : (on ? X32Math.formatFader(level.float) : "Off"),
            tint: on ? color : color.opacity(0.35),
            fine: app.fineMode,
            height: 28,
            onChange: { v in app.dragSet(address, drag, v, steps: 160) },
            onTouch: { began in
                if began { app.beginDrag(address, drag) } else { app.endDrag(drag) }
            }
        )
    }
}

// MARK: - Gate and compressor pages

struct GatePage: View {
    let app: AppModel
    let strip: StripID
    let wide: Bool

    var body: some View {
        let on = app.param(strip.gatePath("on")).bool
        DynamicsLayout(wide: wide) {
            VStack(spacing: 10) {
                OnToggle(app: app, address: strip.gatePath("on"))
                ChoiceList(app: app, address: strip.gatePath("mode"), options: X32Enums.gateModes)
                Spacer(minLength: 0)
            }
        } graph: {
            GateGraph(app: app, strip: strip, detailed: true, interactive: true)
        } controls: {
            ParamKnob(app: app, address: strip.gatePath("thr"), spec: Specs.gateThreshold, title: "Threshold", enabled: on)
            ParamKnob(app: app, address: strip.gatePath("range"), spec: Specs.gateRange, title: "Depth", enabled: on)
            ParamKnob(app: app, address: strip.gatePath("attack"), spec: Specs.attack, title: "Attack", enabled: on)
            ParamKnob(app: app, address: strip.gatePath("hold"), spec: Specs.hold, title: "Hold", enabled: on)
            ParamKnob(app: app, address: strip.gatePath("release"), spec: Specs.release, title: "Release", enabled: on)
            ReductionMeter(meter: app.meters.meter(strip), gate: true)
            KeyControls(app: app, strip: strip, block: "gate", hasSource: true)
        }
    }
}

struct CompPage: View {
    let app: AppModel
    let strip: StripID
    let wide: Bool

    var body: some View {
        let on = app.param(strip.dynPath("on")).bool
        DynamicsLayout(wide: wide) {
            VStack(spacing: 10) {
                OnToggle(app: app, address: strip.dynPath("on"))
                ChoiceList(app: app, address: strip.dynPath("mode"), options: X32Enums.dynModes)
                ChoiceList(app: app, address: strip.dynPath("det"), options: X32Enums.dynDetect)
                ChoiceList(app: app, address: strip.dynPath("env"), options: X32Enums.dynEnvelope)
                OnSwitch(app: app, address: strip.dynPath("auto"), title: "Auto", width: 100)
                    .frame(height: 40)
                Spacer(minLength: 0)
            }
        } graph: {
            CompGraph(app: app, strip: strip, detailed: true, interactive: true)
        } controls: {
            ParamKnob(app: app, address: strip.dynPath("thr"), spec: Specs.dynThreshold, title: "Threshold", enabled: on)
            EnumKnob(app: app, address: strip.dynPath("ratio"), options: X32Enums.ratios, title: "Ratio", suffix: ":1", enabled: on)
            ParamKnob(app: app, address: strip.dynPath("knee"), spec: Specs.knee, title: "Knee", enabled: on)
            ParamKnob(app: app, address: strip.dynPath("mgain"), spec: Specs.makeup, title: "Gain", enabled: on)
            ParamKnob(app: app, address: strip.dynPath("attack"), spec: Specs.attack, title: "Attack", enabled: on)
            ParamKnob(app: app, address: strip.dynPath("hold"), spec: Specs.hold, title: "Hold", enabled: on)
            ParamKnob(app: app, address: strip.dynPath("release"), spec: Specs.release, title: "Release", enabled: on)
            ParamKnob(app: app, address: strip.dynPath("mix"), spec: Specs.dynMix, title: "Mix", enabled: on)
            ReductionMeter(meter: app.meters.meter(strip))
            LabeledChoice(app: app, title: "Position", address: strip.dynPath("pos"), options: ["Pre EQ", "Post EQ"])
            KeyControls(app: app, strip: strip, block: "dyn", hasSource: strip.hasDynKeySource)
        }
    }
}

/// Sidechain ("key") source and filter for the gate or compressor.
private struct KeyControls: View {
    let app: AppModel
    let strip: StripID
    /// "gate" or "dyn"
    let block: String
    let hasSource: Bool

    var body: some View {
        let filterOn = app.param(strip.base + "/\(block)/filter/on").bool
        VStack(alignment: .leading, spacing: 10) {
            Text("Key (sidechain)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 6)
            if hasSource {
                LabeledChoice(app: app, title: "Source", address: strip.base + "/\(block)/keysrc",
                              options: (0...64).map(keySourceLabel))
            }
            HStack(spacing: 10) {
                OnSwitch(app: app, address: strip.base + "/\(block)/filter/on", title: "Filter", width: 90)
                EnumMenu(app: app, address: strip.base + "/\(block)/filter/type", options: X32Enums.keyFilterTypes)
            }
            ParamKnob(app: app, address: strip.base + "/\(block)/filter/f", spec: Specs.eqFreq, title: "Filter freq", enabled: filterOn)
        }
    }
}

extension KeyControls {
    /// The desk names key sources like input sources ("In 5", "USB L", "Bus 3"). Where it's clear
    /// which strip carries that signal, its name is added.
    func keySourceLabel(_ v: Int) -> String {
        if v == 0 { return "Self" }
        let base = X32Enums.sourceName(v)
        guard let strip = StripID.keySource(v) else { return base }
        // Input N is channel N's only when the channel is still patched to it.
        if strip.kind == .channel || strip.kind == .auxIn {
            // A channel or aux in carries that input only while it's still patched to it (both use
            // the same source numbers as the key source).
            if app.param(strip.sourcePath).int(or: -1) != v { return base }
        }
        let name = app.param(strip.namePath).string
        return name.isEmpty ? base : "\(base) · \(name)"
    }
}

/// A label with a dropdown on the right.
struct LabeledChoice: View {
    let app: AppModel
    let title: String
    let address: String
    let options: [String]

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
            Spacer()
            EnumMenu(app: app, address: address, options: options)
        }
    }
}

/// Left buttons, a big square graph, and sliders on the right (stacked on narrow screens).
private struct DynamicsLayout<Side: View, Graph: View, Controls: View>: View {
    let wide: Bool
    @ViewBuilder var side: Side
    @ViewBuilder var graph: Graph
    @ViewBuilder var controls: Controls

    var body: some View {
        if wide {
            HStack(spacing: 2) {
                Cell {
                    side.padding(10)
                }
                .frame(width: 130)
                Cell {
                    graph
                        .aspectRatio(1, contentMode: .fit)
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Cell {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            controls
                        }
                        .padding(12)
                    }
                }
                .frame(width: 300)
            }
            .padding(2)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        side.frame(width: 110)
                        graph.aspectRatio(1, contentMode: .fit)
                    }
                    controls
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Shared bound controls

/// A slider bound to one OSC address via a ParamSpec. (The name is historical: it used to be a knob.)
struct ParamKnob: View {
    let app: AppModel
    let address: String
    let spec: ParamSpec
    let title: String
    var bipolar: Bool = false
    var tint: Color = Theme.accent
    var enabled: Bool = true
    /// Double-tap to reset. Off by default: resetting gain or a threshold mid-show is dangerous.
    var resettable: Bool = false
    /// Long-press opens the precision editor (off inside popovers, where it would open behind them).
    var editable: Bool = true
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
            onLongPress: editable ? { app.editValue(title, address, spec, reset: resettable ? spec.defaultNorm : nil) } : nil,
            onChange: { nv in
                guard app.param(drag.address ?? address).isKnown else { return }
                app.dragSet(address, drag, nv, steps: spec.steps)
            },
            onTouch: { began in
                if began { app.beginDrag(address, drag) } else { app.endDrag(drag) }
            }
        )
        .paramAccessibility(app: app, title: title, address: address, spec: spec, enabled: enabled, reset: resettable ? spec.defaultNorm : nil)
    }
}

/// A slider that steps through a list of named values (e.g. compressor ratio).
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondary)
            }
            .barChip()
        }
    }
}

/// A column of buttons, one per option (gate mode, detector…).
struct ChoiceList: View {
    let app: AppModel
    let address: String
    let options: [String]

    var body: some View {
        let p = app.param(address)
        VStack(spacing: 4) {
            ForEach(0..<options.count, id: \.self) { i in
                LitButton(title: options[i], isOn: p.isKnown && p.int == i, height: 34, fontSize: 12, style: .outline) {
                    app.setInt(address, i)
                }
            }
        }
    }
}

/// An On/Off button with a green rim when on (processing blocks, low cut…).
struct OnSwitch: View {
    let app: AppModel
    let address: String
    var title: String = "On"
    var color: Color = Theme.on
    var width: CGFloat = 64

    var body: some View {
        let on = app.param(address).bool
        LitButton(title: title, isOn: on, height: 40, fontSize: 13, style: .outline) {
            app.setBool(address, !on)
        }
        .frame(width: width)
    }
}

/// The big "On" / "Off" button at the top of each block.
struct OnToggle: View {
    let app: AppModel
    let address: String

    var body: some View {
        let on = app.param(address).bool
        LitButton(title: on ? "On" : "Off", isOn: on, height: 44, fontSize: 14, style: .outline) {
            app.setBool(address, !on)
        }
        .frame(width: 100)
    }
}
