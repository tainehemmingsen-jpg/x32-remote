import Foundation

// The scene builder's "AI" side: Apple's on-device language model (iPadOS 26 and later, on iPads
// that have Apple Intelligence) reads the description into a ScenePlan. It runs on the iPad
// itself, so it's free and works with no internet. Everywhere else the built-in parser
// (SceneBuilder.plan) does the job.

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedScene {
    @Guide(description: "A short title for the event, like 'Sunday service', 'Rock gig' or 'Conference'.")
    var title: String

    @Guide(description: "Every microphone or line input that needs its own channel on the mixing desk, in the usual order (drums, bass, guitars, keys, horns, vocals, speech mics, playback). Stereo sources such as keyboards, playback and drum overheads take two inputs whose names end in L and R.")
    var inputs: [GeneratedInput]

    @Guide(description: "The monitor mixes (wedges or in-ear mixes) the performers need, each named after who it's for, like 'Lead Vox' or 'Drums'. Empty when nobody needs monitors, such as a talk or a class with music.")
    var monitorMixes: [String]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedInput {
    @Guide(description: "The channel's name on the desk's scribble strip, at most 12 characters, e.g. Kick, Snare, Bass, Gtr 1, Keys L, Lead Vox, BV 1, Pastor, Lectern, Playback L.")
    var name: String

    @Guide(description: "What kind of source it is, exactly one of: Lead vocal, Backing vocal, Low male vocal, Rap vocal, Choir, Speech, Lapel mic, Headset mic, Kick, Snare, Hi-hat, Toms, Overheads, Cajon, Bass DI, Bass amp, Electric guitar, Acoustic guitar, Keys, Piano, Organ, Synth, Sax, Trumpet, Violin, Playback, DJ.")
    var source: String
}

enum SceneAI {
    /// True when the on-device model can be used right now.
    static var isAvailable: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
    }

    static func plan(from description: String) async throws -> ScenePlan? {
        guard #available(iOS 26.0, macOS 26.0, *) else { return nil }
        let session = LanguageModelSession(instructions: """
            You set up a Behringer X32 digital mixing desk for live events. From a short description of \
            the event or the band, list the inputs that need desk channels and the monitor mixes the \
            performers need. Only include what the description says or clearly implies; a "full band" \
            means drums, bass, guitar, keys and vocals. A drum kit is usually Kick, Snare, Hi-Hat, toms \
            and two overheads. Keep names short.
            """)
        let response = try await session.respond(to: description, generating: GeneratedScene.self)
        return SceneAI.plan(from: response.content)
    }

    @available(iOS 26.0, macOS 26.0, *)
    static func plan(from g: GeneratedScene) -> ScenePlan? {
        let inputs = g.inputs.prefix(32).map { i -> ScenePlan.Input in
            let starter = SceneAI.starter(for: i.source, name: i.name)
            return ScenePlan.Input(i.name, starter, ScenePlan.Group.of(starter: starter))
        }
        guard !inputs.isEmpty else { return nil }
        let title = g.title.trimmingCharacters(in: .whitespaces)
        return ScenePlan(title: title.isEmpty ? "New scene" : title,
                         inputs: Array(inputs),
                         mixes: g.monitorMixes.prefix(12).map { SceneBuilder.deskName($0) })
    }
}
#else
enum SceneAI {
    static var isAvailable: Bool { false }
    static func plan(from description: String) async throws -> ScenePlan? { nil }
}
#endif

extension SceneAI {
    /// The starting point for a source the model named, falling back to the parser's reading of
    /// the source and the channel name.
    static func starter(for source: String, name: String) -> String {
        if let s = StarterPresets.named(source) { return s.name }
        if let s = StarterPresets.all.first(where: { source.lowercased().contains($0.name.lowercased()) }) { return s.name }
        if let guess = SceneBuilder.plan(from: source + " , " + name)?.inputs.first { return guess.starter }
        return "Speech"
    }
}
