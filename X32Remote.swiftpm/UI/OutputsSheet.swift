import SwiftUI

/// Routing: which inputs feed the channels, and what every output carries. Changes ask first,
/// since they move audio straight away.
struct OutputsSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var group: Outputs.Group = .main
    @State private var tab: Tab = .outputs

    enum Tab { case inputs, outputs, blocks }
    @State private var pending: PendingPatch?
    @State private var confirming = false

    struct PendingPatch: Identifiable {
        let address: String
        let output: String
        let value: Int
        let valueName: String
        var message = "The output changes on the desk straight away."
        var id: String { address + "\(value)" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button {
                            tab = .inputs
                        } label: {
                            Text("Inputs").barChip(active: tab == .inputs)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tab == .inputs ? .isSelected : [])
                        ForEach(Outputs.Group.allCases) { g in
                            Button {
                                group = g
                                tab = .outputs
                            } label: {
                                Text(g.title).barChip(active: tab == .outputs && g == group)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(tab == .outputs && g == group ? .isSelected : [])
                        }
                        Button {
                            tab = .blocks
                        } label: {
                            Text("Out blocks").barChip(active: tab == .blocks)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tab == .blocks ? .isSelected : [])
                    }
                    .padding(10)
                }
                ScrollView {
                    LazyVStack(spacing: 2) {
                        switch tab {
                        case .inputs:
                            let playing = app.param(OutputRouting.switchPath).int(or: 0) == 1
                            ForEach(InputRouting.blocks) { block in
                                InputBlockRow(app: app, block: block, dimmed: playing) {
                                    pending = $0
                                    confirming = true
                                }
                            }
                            RouteSwitchRow(app: app) {
                                pending = $0
                                confirming = true
                            }
                            ForEach(OutputRouting.play) { block in
                                InputBlockRow(app: app, block: block, dimmed: !playing) {
                                    pending = $0
                                    confirming = true
                                }
                            }
                            Text("Each block feeds eight channels from the chosen inputs. Gain and phantom power belong to the physical inputs, so check them after a change. The Play blocks are used while the card plays back.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondary)
                                .padding(.top, 8)
                        case .outputs:
                            ForEach(1...group.count, id: \.self) { n in
                                OutputRow(app: app, group: group, number: n) {
                                    pending = $0
                                    confirming = true
                                }
                            }
                        case .blocks:
                            ForEach(OutputRouting.sections, id: \.0) { title, blocks in
                                Text(title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                                ForEach(blocks) { block in
                                    InputBlockRow(app: app, block: block, dimmed: false) {
                                        pending = $0
                                        confirming = true
                                    }
                                }
                            }
                            Text("What leaves the desk on each group of outputs. “Out 1–16” are the signals patched on the Local, Aux, P16, AES and Record tabs.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondary)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 20)
                }
            }
            .background(Theme.background)
            .overlay(alignment: .bottom) {
                ToastView(app: app)
            }
            .navigationTitle("Routing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Patch \(pending?.output ?? "") to \(pending?.valueName ?? "")?",
                                isPresented: $confirming, titleVisibility: .visible, presenting: pending) { p in
                Button("Patch") {
                    app.setInt(p.address, p.value)
                }
                Button("Cancel", role: .cancel) {}
            } message: { p in
                Text(p.message)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Record or play: which set of input blocks the channels use.
private struct RouteSwitchRow: View {
    let app: AppModel
    let ask: (OutputsSheet.PendingPatch) -> Void

    var body: some View {
        let p = app.param(OutputRouting.switchPath)
        HStack(spacing: 10) {
            Text("Channels take")
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
            Spacer()
            ForEach(0..<2, id: \.self) { v in
                let on = p.isKnown && p.int == v
                LitButton(title: v == 0 ? "Record routing" : "Play routing", isOn: on, height: 36, fontSize: 13, style: .outline, enabled: p.isKnown) {
                    if !on {
                        ask(.init(address: OutputRouting.switchPath, output: "the channel inputs", value: v,
                                  valueName: v == 0 ? "the Record routing" : "the Play routing",
                                  message: "Every channel switches to the other set of input blocks straight away."))
                    }
                }
                .frame(width: 140)
            }
        }
        .padding(8)
        .background(Theme.panel)
    }
}

private struct InputBlockRow: View {
    let app: AppModel
    let block: InputRouting.Block
    /// True for the set of blocks the desk isn't using right now (record vs play).
    var dimmed = false
    let ask: (OutputsSheet.PendingPatch) -> Void

    var body: some View {
        let p = app.param(block.path)
        HStack(spacing: 10) {
            Text(block.title)
                .font(Theme.mono(14))
                .foregroundStyle(Theme.secondary)
                .frame(width: 110, alignment: .leading)
            Menu {
                ForEach(0..<InputRouting.offered(block), id: \.self) { v in
                    Button {
                        if p.int != v {
                            ask(.init(address: block.path, output: block.title, value: v, valueName: InputRouting.label(block, v),
                                      message: "Everything on this block changes straight away."))
                        }
                    } label: {
                        if p.isKnown && p.int == v { Label(InputRouting.label(block, v), systemImage: "checkmark") } else { Text(InputRouting.label(block, v)) }
                    }
                }
            } label: {
                HStack {
                    Text(p.isKnown ? InputRouting.label(block, p.int) : "—")
                        .lineLimit(1)
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.raised))
            }
            .disabled(!p.isKnown)
            .accessibilityLabel("\(block.title) routing")
            .accessibilityValue(p.isKnown ? InputRouting.label(block, p.int) : "not read yet")
        }
        .padding(8)
        .background(Theme.panel)
        .opacity(dimmed ? 0.55 : 1)
    }
}

private struct OutputRow: View {
    let app: AppModel
    let group: Outputs.Group
    let number: Int
    let ask: (OutputsSheet.PendingPatch) -> Void

    private func label(_ v: Int) -> String {
        let base = Outputs.sourceName(v)
        if let strip = Outputs.sourceStrip(v), strip.kind != .main, strip.kind != .mono {
            let name = app.param(strip.namePath).string
            if !name.isEmpty { return "\(base) · \(name)" }
        }
        return base
    }

    var body: some View {
        let srcAddress = Outputs.path(group, number, "src")
        let posAddress = Outputs.path(group, number, "pos")
        let invertAddress = Outputs.path(group, number, "invert")
        let src = app.param(srcAddress)
        let pos = app.param(posAddress)
        let invert = app.param(invertAddress)
        let outputName = "\(group.shortLabel) \(number)"
        let delayOn = Outputs.hasDelay(group) ? app.param(Outputs.path(group, number, "delay/on")).bool : false
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(outputName)
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 64, alignment: .leading)
                Menu {
                    Button {
                        if src.int != 0 { ask(.init(address: srcAddress, output: outputName, value: 0, valueName: "Off")) }
                    } label: {
                        if src.int == 0 { Label("Off", systemImage: "checkmark") } else { Text("Off") }
                    }
                    ForEach(Outputs.sourceGroups, id: \.0) { title, range in
                        Menu(title) {
                            ForEach(Array(range), id: \.self) { v in
                                Button {
                                    if src.int != v { ask(.init(address: srcAddress, output: outputName, value: v, valueName: label(v))) }
                                } label: {
                                    if src.isKnown && src.int == v { Label(label(v), systemImage: "checkmark") } else { Text(label(v)) }
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(src.isKnown ? label(src.int) : "—")
                            .lineLimit(1)
                            .foregroundStyle(src.isKnown && src.int == 0 ? Theme.secondary : Theme.text)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                    }
                    .font(.system(size: 14))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.raised))
                }
                .disabled(!src.isKnown)
                .accessibilityLabel("\(outputName) source")
                .accessibilityValue(src.isKnown ? label(src.int) : "not read yet")
            }
            HStack(spacing: 8) {
                Color.clear.frame(width: 64, height: 1)
                if src.isKnown && Outputs.isDirectOut(src.int) {
                    Menu {
                        ForEach(Outputs.tapNames.indices, id: \.self) { i in
                            Button {
                                if pos.int != i {
                                    ask(.init(address: posAddress, output: "\(outputName) tap point", value: i, valueName: Outputs.tapNames[i]))
                                }
                            } label: {
                                if pos.isKnown && pos.int == i { Label(Outputs.tapNames[i], systemImage: "checkmark") } else { Text(Outputs.tapNames[i]) }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Tap:")
                                .foregroundStyle(Theme.secondary)
                            Text(pos.isKnown && Outputs.tapNames.indices.contains(pos.int) ? Outputs.tapNames[pos.int] : "—")
                                .foregroundStyle(Theme.text)
                        }
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.raised))
                    }
                    .accessibilityLabel("\(outputName) tap point")
                }
                LitButton(title: "Ø", isOn: invert.bool, color: Theme.solo, height: 34, fontSize: 14, style: .fill, enabled: invert.isKnown) {
                    app.setBool(invertAddress, !invert.bool)
                }
                .frame(width: 44)
                .accessibilityLabel("\(outputName) polarity")
                .accessibilityValue(invert.bool ? "inverted" : "normal")
                if Outputs.hasDelay(group) {
                    OnSwitch(app: app, address: Outputs.path(group, number, "delay/on"), title: "Delay", width: 70)
                    ParamKnob(app: app, address: Outputs.path(group, number, "delay/time"), spec: Specs.delay, title: "Time", enabled: delayOn)
                        .frame(maxWidth: 220)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .background(Theme.panel)
    }
}
