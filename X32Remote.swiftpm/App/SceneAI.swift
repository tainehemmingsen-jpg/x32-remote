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
    @Guide(description: "A title for the event in two or three words.")
    var title: String

    @Guide(description: "The sound sources the description mentions or clearly implies, with how many of each. A band has one entry per instrument; 'drum kit' covers the whole kit. Don't add speech mics unless someone speaks, and don't add instruments that aren't mentioned.")
    var sources: [GeneratedSource]

    @Guide(description: "True when the performers need monitor mixes (wedges, in-ears, foldback). False for a talk, a class or a DJ.")
    var monitors: Bool
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedSource {
    @Guide(.anyOf(SceneBuilder.sourceKinds))
    var kind: String

    @Guide(description: "How many of this kind, 1 to 8.")
    var count: Int
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
            You read a short description of a live event or band and list the sound sources that need \
            channels on the mixing desk. Only list what the description says or clearly implies: a \
            "full band" or "covers band" means drum kit, bass, electric guitar, keys and lead vocal with \
            backing vocal; a church service usually has a pastor, a worship leader (lead vocal), backing \
            vocals, acoustic guitar, keys, bass, drum kit and playback; a conference has a lectern, \
            handheld mics and playback; a gym class has an instructor headset and playback. Never add \
            speech mics to a band, or instruments nobody mentioned.
            """)
        let response = try await session.respond(to: description, generating: GeneratedScene.self)
        return SceneAI.plan(from: response.content, original: description)
    }

    @available(iOS 26.0, macOS 26.0, *)
    static func plan(from g: GeneratedScene, original: String) -> ScenePlan? {
        SceneBuilder.plan(title: g.title, kinds: g.sources.map { ($0.kind, $0.count) }, monitors: g.monitors, original: original)
    }
}
#else
enum SceneAI {
    static var isAvailable: Bool { false }
    static func plan(from description: String) async throws -> ScenePlan? { nil }
}
#endif
