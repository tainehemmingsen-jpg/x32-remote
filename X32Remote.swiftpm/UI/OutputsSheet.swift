import SwiftUI

/// The output patch: what every output carries. Changes ask first, since they move audio
/// on stage straight away.
struct OutputsSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var group: Outputs.Group = .main
    @State private var pending: PendingPatch?

    struct PendingPatch: Identifiable {
        let address: String
        let output: String
        let value: Int
        let valueName: String
        var id: String { address + "\(value)" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Outputs.Group.allCases) { g in
                            Button {
                                group = g
                            } label: {
                                Text(g.title).barChip(active: g == group)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(g == group ? .isSelected : [])
                        }
                    }
                    .padding(10)
                }
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(1...group.count, id: \.self) { n in
                            OutputRow(app: app, group: group, number: n) { pending = $0 }
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
            .navigationTitle("Output patch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(pending.map { "Patch \($0.output) to \($0.valueName)?" } ?? "",
                                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                                titleVisibility: .visible) {
                Button("Patch") {
                    if let p = pending { app.setInt(p.address, p.value) }
                    pending = nil
                }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text("The output changes on the desk straight away.")
            }
        }
        .preferredColorScheme(.dark)
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
        let src = app.param(srcAddress)
        let pos = app.param(posAddress)
        let outputName = "\(group.shortLabel) \(number)"
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
                        .foregroundStyle(src.isKnown && src.int == 0 ? Theme.tertiary : Theme.text)
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
                    Text(pos.isKnown && Outputs.tapNames.indices.contains(pos.int) ? Outputs.tapNames[pos.int] : "—")
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .frame(width: 140, height: 38)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.raised))
                }
                .accessibilityLabel("\(outputName) tap point")
            }
        }
        .padding(8)
        .background(Theme.panel)
    }
}
