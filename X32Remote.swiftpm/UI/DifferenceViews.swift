import SwiftUI

// MARK: - Mix check

/// Every input looked over for the usual gig problems, each with a fix.
struct MixCheckSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                let issues = app.mixCheckIssues()
                List {
                    if issues.isEmpty {
                        Section {
                            HStack(spacing: 14) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(Theme.on)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("All clear")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Nothing clipping, no voices without a low cut, no open channels with nothing on them. It keeps watching while this is open.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    let problems = issues.filter { $0.severity == .problem }
                    let checks = issues.filter { $0.severity == .check }
                    if !problems.isEmpty {
                        Section("Fix these") {
                            ForEach(problems) { IssueRow(app: app, issue: $0, close: { dismiss() }) }
                        }
                    }
                    if !checks.isEmpty {
                        Section("Worth a look") {
                            ForEach(checks) { IssueRow(app: app, issue: $0, close: { dismiss() }) }
                        }
                    }
                    Section {
                        Text("Levels are judged on the loudest moment of the last minute, so run it while the band plays or during the service.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
            .navigationTitle("Mix check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) { ToastView(app: app) }
            .onAppear { app.loadMixCheck() }
        }
        .preferredColorScheme(.dark)
    }
}

private struct IssueRow: View {
    let app: AppModel
    let issue: MixCheck.Issue
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: issue.severity == .problem ? "exclamationmark.triangle.fill" : "lightbulb")
                .font(.system(size: 18))
                .foregroundStyle(issue.severity == .problem ? Theme.mute : Theme.solo)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(issue.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            fixButton
                .frame(width: 150)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var fixButton: some View {
        switch issue.fix {
        case .autoGain?:
            if let s = issue.strip { GainWizardButton(app: app, strip: s, height: 36) }
        case .changes(_, let label)?:
            Button {
                app.applyFix(issue)
            } label: {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent))
            }
            .buttonStyle(ConsoleKeyStyle())
        case .open(let tab)?:
            Button {
                if let s = issue.strip {
                    app.pendingDetail = s
                    app.pendingDetailTab = DetailTab(rawValue: tab) ?? .overview
                    close()
                }
            } label: {
                Text("Open \(DetailTab(rawValue: tab)?.title ?? "channel")")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised2))
            }
            .buttonStyle(ConsoleKeyStyle())
        case nil:
            EmptyView()
        }
    }
}

// MARK: - What changed

/// A saved scene against the desk now: every difference, each with Put back.
struct CompareSheet: View {
    let app: AppModel
    let scene: SceneFile
    @Environment(\.dismiss) private var dismiss
    @State private var confirmAll = false

    var body: some View {
        NavigationStack {
            List {
                if let t = app.sceneTransfer, t.kind == .reading {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reading the desk…")
                            ProgressView(value: Double(t.done), total: Double(max(t.total, 1)))
                        }
                    }
                } else if let c = app.comparison, c.scene.id == scene.id {
                    if c.unread > 0 {
                        Section {
                            Label("\(c.unread) settings didn't answer, so they weren't compared. Compare again to retry.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.solo)
                        }
                    }
                    if c.changes.isEmpty {
                        Section {
                            Label(c.unread > 0 ? "Everything that answered matches “\(scene.name)”" : "The desk matches “\(scene.name)”",
                                  systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Theme.on)
                        }
                    } else {
                        Section {
                            ForEach(c.changes) { change in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(change.title)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text(change.summary)
                                            .font(.system(size: 13))
                                            .foregroundStyle(Theme.secondary)
                                            .lineLimit(3)
                                    }
                                    Spacer()
                                    Button("Put back") { app.restore([change]) }
                                        .buttonStyle(.bordered)
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Text("\(c.changes.count) changed since “\(scene.name)” · saved → now")
                        }
                    }
                }
            }
            .navigationTitle("What's changed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Put all back") { confirmAll = true }
                        .disabled((app.comparison?.changes.isEmpty ?? true) || app.sceneTransfer != nil)
                }
            }
            .confirmationDialog("Put all \(app.comparison?.changes.count ?? 0) settings back to “\(scene.name)”?", isPresented: $confirmAll, titleVisibility: .visible) {
                Button("Put all back", role: .destructive) {
                    if let c = app.comparison { app.restore(c.changes) }
                }
            }
            .overlay(alignment: .bottom) { ToastView(app: app) }
            .onAppear { app.compareWithDesk(scene) }
            .onDisappear {
                if app.sceneTransfer?.kind == .reading { app.cancelSceneTransfer() }
                app.endComparison()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Setlist

/// Songs in order: tap Next and the delays follow the tempo, channels sitting out are muted,
/// and the notes for the song come up.
struct SetlistSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingSong: EditSong?
    @State private var naming = false
    @State private var newName = ""

    struct EditSong: Identifiable {
        var song: Setlist.Song
        let isNew: Bool
        var id: UUID { song.id }
    }

    private var list: Setlist? { app.setlists.first { $0.id == app.currentSetlistID } }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = geo.size.width >= 760
                HStack(spacing: 0) {
                    songList
                        .frame(width: wide ? 380 : geo.size.width)
                    if wide {
                        nowPlaying
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.background)
                    }
                }
            }
            .navigationTitle(list?.name ?? "Setlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(app.setlists) { l in
                            Button(l.name) {
                                app.leaveSetlist()
                                app.currentSetlistID = l.id
                            }
                        }
                        Button {
                            newName = ""
                            naming = true
                        } label: { Label("New setlist", systemImage: "plus") }
                    } label: {
                        Label("Setlists", systemImage: "music.note.list")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New setlist", isPresented: $naming) {
                TextField("Name (e.g. Friday at the Rose)", text: $newName)
                Button("Create") {
                    let l = Setlist(name: newName.isEmpty ? "Setlist" : newName)
                    app.saveSetlists(app.setlists + [l])
                    app.leaveSetlist()
                    app.currentSetlistID = l.id
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $editingSong) { edit in
                SongEditor(app: app, song: edit.song, isNew: edit.isNew) { saved in
                    save(saved)
                } delete: {
                    delete(edit.song.id)
                }
            }
            .overlay(alignment: .bottom) { ToastView(app: app) }
            .onAppear {
                if app.currentSetlistID == nil { app.currentSetlistID = app.setlists.first?.id }
                app.loadEffects()
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var songList: some View {
        if let list {
            List {
                ForEach(Array(list.songs.enumerated()), id: \.element.id) { i, song in
                    Button {
                        app.playSong(i)
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(i + 1)")
                                .font(Theme.mono(14, .semibold))
                                .foregroundStyle(app.currentSongIndex == i ? Color.black : Theme.secondary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(app.currentSongIndex == i ? Theme.accent : Theme.raised2))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.name)
                                    .font(.system(size: 16, weight: app.currentSongIndex == i ? .bold : .medium))
                                    .foregroundStyle(Theme.text)
                                Text(songDetail(song))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.tertiary)
                            }
                            Spacer()
                        }
                    }
                    .swipeActions {
                        Button { editingSong = EditSong(song: song, isNew: false) } label: { Label("Edit", systemImage: "pencil") }
                            .tint(Theme.accent)
                    }
                    .contextMenu {
                        Button { editingSong = EditSong(song: song, isNew: false) } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { delete(song.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .onMove { from, to in
                    var l = list
                    l.songs.move(fromOffsets: from, toOffset: to)
                    replace(l)
                }
                Button {
                    editingSong = EditSong(song: Setlist.Song(name: "", bpm: nil), isNew: true)
                } label: {
                    Label("Add a song", systemImage: "plus")
                }
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.tertiary)
                Text("No setlist yet")
                    .font(.system(size: 18, weight: .semibold))
                Text("Add the songs with their tempo, notes and who sits out. During the gig, tap Next: the delays follow the tempo and channels not playing are muted.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                Button("New setlist") {
                    newName = ""
                    naming = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var nowPlaying: some View {
        VStack(spacing: 18) {
            if let list, let i = app.currentSongIndex, list.songs.indices.contains(i) {
                let song = list.songs[i]
                Text("NOW · \(i + 1) of \(list.songs.count)")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
                Text(song.name)
                    .font(.system(size: 40, weight: .heavy))
                    .multilineTextAlignment(.center)
                if let bpm = song.bpm {
                    Text(String(format: "%.0f BPM · delays %.0f ms", bpm, SetlistMath.delayMS(bpm: bpm)))
                        .font(Theme.mono(16))
                        .foregroundStyle(Theme.secondary)
                }
                if !song.sittingOut.isEmpty {
                    Text("Sitting out: " + song.sittingOut.compactMap { StripID(id: $0) }.map { app.stripTitle($0) }.joined(separator: ", "))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.mute)
                        .multilineTextAlignment(.center)
                }
                if !song.notes.isEmpty {
                    Text(song.notes)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.text)
                        .padding(16)
                        .frame(maxWidth: 520)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
                }
                if i + 1 < list.songs.count {
                    Text("Next: \(list.songs[i + 1].name)")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.tertiary)
                }
            } else if let list, !list.songs.isEmpty {
                Image(systemName: "play.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)
                Text("\(list.songs.count) song\(list.songs.count == 1 ? "" : "s") ready")
                    .font(.system(size: 22, weight: .semibold))
                Text("Start plays the first song: its delays set to the tempo, and anyone sitting out muted. Tap any song to jump to it.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            } else {
                Image(systemName: "music.note.list")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.tertiary)
                Text(list == nil ? "Pick a setlist" : "No songs yet")
                    .font(.system(size: 22, weight: .semibold))
                Text(list == nil ? "Choose one from the list on the left, or make a new one." : "Add the songs on the left: each can have a tempo for the delays, notes for the engineer, and a list of who sits out.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Spacer().frame(height: 10)
            if list?.songs.isEmpty == false {
            HStack(spacing: 14) {
                LitButton(title: "◀ Previous", isOn: false, height: 64, fontSize: 18) {
                    if let i = app.currentSongIndex, i > 0 { app.playSong(i - 1) }
                }
                .frame(width: 180)
                LitButton(title: app.currentSongIndex == nil ? "Start ▶" : "Next ▶", isOn: true, color: Theme.accent, height: 64, fontSize: 20) {
                    let next = (app.currentSongIndex ?? -1) + 1
                    if let list, next < list.songs.count { app.playSong(next) }
                }
                .frame(width: 240)
            }
            }
        }
        .padding(30)
    }

    private func songDetail(_ s: Setlist.Song) -> String {
        var parts: [String] = []
        if let bpm = s.bpm { parts.append(String(format: "%.0f BPM", bpm)) }
        if !s.sittingOut.isEmpty { parts.append("\(s.sittingOut.count) sitting out") }
        if !s.notes.isEmpty { parts.append(s.notes) }
        return parts.joined(separator: " · ")
    }

    private func replace(_ l: Setlist) {
        app.saveSetlists(app.setlists.map { $0.id == l.id ? l : $0 })
    }

    private func save(_ song: Setlist.Song) {
        guard var l = list else { return }
        if let i = l.songs.firstIndex(where: { $0.id == song.id }) { l.songs[i] = song } else { l.songs.append(song) }
        replace(l)
    }

    private func delete(_ id: UUID) {
        guard var l = list else { return }
        l.songs.removeAll { $0.id == id }
        replace(l)
    }
}

private struct SongEditor: View {
    let app: AppModel
    @State var song: Setlist.Song
    let isNew: Bool
    let save: (Setlist.Song) -> Void
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var taps: [TimeInterval] = []
    @State private var bpmText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Song name", text: $song.name)
                        .font(.system(size: 17, weight: .semibold))
                }
                Section {
                    HStack {
                        TextField("BPM", text: $bpmText)
                            .keyboardType(.decimalPad)
                            .font(Theme.mono(20))
                            .frame(width: 110)
                            .onChange(of: bpmText) { _, t in song.bpm = Double(t) }
                        Spacer()
                        Button {
                            taps.append(Date().timeIntervalSinceReferenceDate)
                            if let bpm = SetlistMath.bpm(fromTaps: taps) {
                                song.bpm = bpm
                                bpmText = String(format: "%.0f", bpm)
                            }
                        } label: {
                            Text("TAP")
                                .font(.system(size: 18, weight: .heavy))
                                .frame(width: 110, height: 52)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.25)))
                        }
                        .buttonStyle(ConsoleKeyStyle())
                    }
                } header: {
                    Text("Tempo")
                } footer: {
                    Text("The delay effects in slots 1–4 are set to a quarter note at this tempo. Leave it empty to leave them alone.")
                }
                Section("Notes for the engineer") {
                    TextField("e.g. Sax solo after 2nd chorus, push vox", text: $song.notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                        ForEach(StripID.all(.channel) + StripID.all(.auxIn)) { s in
                            let name = app.param(s.namePath).string
                            if !name.isEmpty {
                                let out = song.sittingOut.contains(s.id)
                                Button {
                                    if out { song.sittingOut.removeAll { $0 == s.id } } else { song.sittingOut.append(s.id) }
                                } label: {
                                    Text(name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .foregroundStyle(out ? Color.white : Theme.text)
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(RoundedRectangle(cornerRadius: 7).fill(out ? Theme.mute : Theme.raised))
                                }
                                .buttonStyle(ConsoleKeyStyle())
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Sitting this one out")
                } footer: {
                    Text("Muted while this song plays, and unmuted again for the next one that has them.")
                }
                if !isNew {
                    Section {
                        Button("Delete song", role: .destructive) {
                            delete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add a song" : "Edit song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(song)
                        dismiss()
                    }
                    .disabled(song.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { bpmText = song.bpm.map { String(format: "%.0f", $0) } ?? "" }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Talk over music

/// Pick the mic and the music channels; the music dips whenever the mic is used.
struct DuckSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var mic: StripID = StripID(.channel, 1)
    @State private var music: Set<StripID> = []
    @State private var depth: Double = 15

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: Binding(get: { app.duckOn }, set: { on in
                        commit()
                        app.setDucking(on)
                    })) {
                        Label("Talk over music", systemImage: "speaker.wave.2.bubble.left")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .disabled(music.isEmpty)
                } footer: {
                    Text("While someone talks on the mic, the music drops by \(Int(depth)) dB, and comes back up a moment after they stop. Uses the music channels' gates in duck mode.")
                }
                Section("The mic") {
                    Picker("Mic", selection: $mic) {
                        ForEach(StripID.all(.channel) + StripID.all(.auxIn)) { s in
                            Text(app.stripTitle(s)).tag(s)
                        }
                    }
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                        ForEach(StripID.all(.channel)) { s in
                            let on = music.contains(s)
                            Button {
                                if on { music.remove(s) } else { music.insert(s) }
                            } label: {
                                Text(app.stripTitle(s))
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .foregroundStyle(on ? Color.black : Theme.text)
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.accent : Theme.raised))
                            }
                            .buttonStyle(ConsoleKeyStyle())
                            .disabled(s == mic)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("The music (channels)")
                } footer: {
                    Text("Music on an aux input can't be ducked (aux ins have no gate): patch it to a pair of channels instead.")
                }
                Section("How far it dips") {
                    Slider(value: $depth, in: 6...30, step: 1)
                    Text("\(Int(depth)) dB")
                        .font(Theme.mono(14))
                }
            }
            .navigationTitle("Talk over music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commit()
                        if app.duckOn { app.setDucking(true) }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let d = app.settings.duck {
                    mic = d.mic
                    music = Set(d.music)
                    depth = Double(d.depth)
                } else if let guess = StripID.all(.channel).first(where: { MixCheck.isVoice(app.param($0.namePath).string) }) {
                    mic = guess
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func commit() {
        let ordered = StripID.all(.channel).filter { music.contains($0) }
        app.setDuck(DuckSetup(mic: mic, music: ordered, depth: Float(depth)))
    }
}

/// The Talk-over-music switch for the Simple screen and the top bar.
struct DuckButton: View {
    let app: AppModel
    var height: CGFloat = 40

    var body: some View {
        if app.settings.duck != nil {
            LitButton(title: app.duckOn ? "TALKING OVER MUSIC" : "Talk over music", isOn: app.duckOn, color: Theme.accent, height: height, fontSize: 13) {
                app.setDucking(!app.duckOn)
            }
        }
    }
}
