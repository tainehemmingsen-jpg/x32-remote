import SwiftUI
import UniformTypeIdentifiers

/// Scenes kept on this iPad: imported from X32-Edit (.scn files), saved from the desk, or made
/// in the app. Any of them can be sent to the desk when you connect, and exported back out.
struct SceneLibrarySheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var sending: SceneFile?
    @State private var renaming: SceneFile?
    @State private var newName = ""
    @State private var deleting: SceneFile?
    @State private var exportURL: ExportFile?
    @State private var savingDesk = false
    @State private var deskSceneName = ""

    struct ExportFile: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        LibraryAction(title: "Import .scn", symbol: "square.and.arrow.down") { importing = true }
                        LibraryAction(title: "Save the desk here", symbol: "arrow.down.doc") {
                            deskSceneName = ""
                            savingDesk = true
                        }
                        .disabled(app.sceneTransfer != nil)
                        LibraryAction(title: "Build a scene", symbol: "wand.and.stars") {
                            app.pendingBuilder = true
                            dismiss()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Make a scene in X32-Edit, save it (File › Save Scene), and get the .scn file onto this iPad with AirDrop or the Files app. Import it here, and send it to the desk whenever you're connected.")
                }

                if let t = app.sceneTransfer {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t.kind == .sending ? "Sending “\(t.name)” to the desk…" : "Reading the desk…")
                                .font(.system(size: 14, weight: .medium))
                            ProgressView(value: Double(t.done), total: Double(max(t.total, 1)))
                            HStack {
                                Text("\(t.done) of \(t.total)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.secondary)
                                Spacer()
                                Button("Stop", role: .destructive) { app.cancelSceneTransfer() }
                                    .font(.system(size: 13))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(app.sceneLibrary.isEmpty ? "" : "On this iPad") {
                    if app.sceneLibrary.isEmpty {
                        Text("No scenes yet.")
                            .foregroundStyle(Theme.secondary)
                    }
                    ForEach(app.sceneLibrary) { scene in
                        SceneRow(scene: scene) {
                            sending = scene
                        }
                        .contextMenu {
                            Button { sending = scene } label: { Label("Send to desk…", systemImage: "arrow.up.doc") }
                            Button {
                                newName = scene.name
                                renaming = scene
                            } label: { Label("Rename", systemImage: "pencil") }
                            Button { export(scene) } label: { Label("Export .scn", systemImage: "square.and.arrow.up") }
                            Button(role: .destructive) { deleting = scene } label: { Label("Delete", systemImage: "trash") }
                        }
                        .swipeActions {
                            Button(role: .destructive) { deleting = scene } label: { Label("Delete", systemImage: "trash") }
                            Button { export(scene) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                                .tint(Theme.accent)
                        }
                    }
                }
            }
            .navigationTitle("Scene library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                ToastView(app: app)
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [UTType(filenameExtension: "scn") ?? .data, .plainText, .data],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url),
                       let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                        app.importScene(text: text, fileName: url.lastPathComponent)
                    } else {
                        app.showToast("Couldn't read \(url.lastPathComponent)")
                    }
                }
            }
            .sheet(item: $sending) { scene in
                SendSceneSheet(app: app, scene: scene) { sending = nil }
            }
            .sheet(item: $exportURL) { file in
                ShareSheet(items: [file.url])
            }
            .alert("Rename scene", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if var s = renaming {
                        s.name = newName.trimmingCharacters(in: .whitespaces).isEmpty ? s.name : newName
                        app.updateInLibrary(s)
                    }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .alert("Save the desk on this iPad", isPresented: $savingDesk) {
                TextField("Scene name", text: $deskSceneName)
                Button("Save") { app.readDeskIntoLibrary(name: deskSceneName) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Reads every setting from the desk (takes a few seconds) and keeps it here as a scene.")
            }
            .confirmationDialog("Delete “\(deleting?.name ?? "")” from this iPad?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let d = deleting { app.deleteFromLibrary(d) }
                    deleting = nil
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func export(_ scene: SceneFile) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(scene.fileName)
        do {
            try scene.text(firmware: app.console?.firmware ?? "4.0").write(to: url, atomically: true, encoding: .utf8)
            exportURL = ExportFile(url: url)
        } catch {
            app.showToast("Couldn't write the file")
        }
    }
}

private struct LibraryAction: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}

private struct SceneRow: View {
    let scene: SceneFile
    let send: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(scene.name)
                    .font(.system(size: 16, weight: .semibold))
                Text(scene.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                Text("\(scene.origin.title) · \(scene.created.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer()
            Button(action: send) {
                Label("Send to desk", systemImage: "arrow.up.doc")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Capsule().fill(Theme.accent.opacity(0.25)))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

/// What to send, and whether to also keep it in one of the desk's scene slots.
private struct SendSceneSheet: View {
    let app: AppModel
    let scene: SceneFile
    let close: () -> Void
    @State private var parts: Set<SceneFile.Part> = Set(SceneFile.Part.allCases.filter(\.onByDefault))
    @State private var saveOnDesk = false
    @State private var slot = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(scene.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
                Section("Send") {
                    ForEach(SceneFile.Part.allCases) { part in
                        let count = scene.lines.filter { part.contains(SceneFile.path(of: $0)) }.count
                        Toggle(isOn: Binding(get: { parts.contains(part) }, set: { on in
                            if on { parts.insert(part) } else { parts.remove(part) }
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(part.title)
                                Text(count == 0 ? "Not in this scene" : "\(count) settings")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.tertiary)
                            }
                        }
                        .disabled(count == 0)
                    }
                }
                Section {
                    Toggle("Also keep it on the desk as a scene", isOn: $saveOnDesk)
                    if saveOnDesk {
                        Stepper(String(format: "Scene slot %02d", slot) + slotNote, value: $slot, in: 0...99)
                    }
                } footer: {
                    Text(parts.contains(.preamps)
                         ? "Preamp gain and 48V will change. Pull the faders down first, and check nothing that minds phantom power is plugged in."
                         : "This changes the desk straight away, like recalling a scene. Undo can't take it back.")
                }
            }
            .navigationTitle("Send “\(scene.name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        app.sendToDesk(scene, parts: parts, saveAs: saveOnDesk ? slot : nil)
                        close()
                    }
                    .disabled(parts.isEmpty || app.sceneTransfer != nil)
                }
            }
            .onAppear {
                // Suggest the first empty slot on the desk.
                app.loadScenes()
                slot = (0..<100).first { app.param(String(format: "/-show/showfile/scene/%03d/hasdata", $0)).int == 0 } ?? 0
            }
        }
        .preferredColorScheme(.dark)
    }

    private var slotNote: String {
        let name = app.param(String(format: "/-show/showfile/scene/%03d/name", slot)).string
        let used = app.param(String(format: "/-show/showfile/scene/%03d/hasdata", slot)).int != 0
        return used ? " (replaces “\(name)”)" : " (empty)"
    }
}

/// The system share sheet (AirDrop, Files, Mail…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
