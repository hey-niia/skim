import Foundation
import FoundationModels

@Generable
struct ArticleDigestPayload {
    @Guide(description: "One or two concise, neutral sentences capturing the article's single main idea.")
    var mainIdea: String

    @Guide(description: "3 to 8 short bullet points with the concrete substance of the article. If the article is itself a list, ranking, or roundup (e.g. \"best albums of the year\", \"10 things to know\", \"products we recommend\"), the points MUST be the actual named items from that list — specific titles, names, or facts — not a generic description of what the article is about. No filler, no repetition of the main idea.")
    var keyPoints: [String]
}

enum SummarizerAvailability {
    case available
    case unavailable(reason: String)
}

enum Summarizer {
    static func checkAvailability() -> SummarizerAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This Mac doesn't support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Turn on Apple Intelligence in System Settings to get summaries.")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "The on-device model is still downloading. Try again shortly.")
        case .unavailable:
            return .unavailable(reason: "On-device summaries aren't available right now.")
        }
    }

    /// Two things make the on-device model less predictable than a cloud model, so we try
    /// a few progressively gentler configurations before giving up:
    /// 1. It has a hard ~4096-token context window shared by instructions, schema, prompt,
    ///    and output. Token density varies a lot by content (emoji, bylines, and scores in
    ///    listicles tokenize much denser than prose), so a fixed character budget can
    ///    overflow even when the raw text looks short enough.
    /// 2. It has built-in safety guardrails and can refuse content it judges sensitive
    ///    (e.g. war coverage) — more likely to trigger when we push it to be very specific.
    ///    Retrying with a softer, higher-level framing often succeeds where a detail-heavy
    ///    request was refused.
    static func summarize(title: String, body: String) async throws -> (mainIdea: String, keyPoints: [String]) {
        let configs: [(charLimit: Int, detailed: Bool)] = [
            (6000, true),
            (2200, true),
            (4000, false),
        ]
        var lastError: Error = SummarizerError.allAttemptsFailed
        for config in configs {
            do {
                return try await attempt(title: title, body: body, charLimit: config.charLimit, detailed: config.detailed)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func attempt(title: String, body: String, charLimit: Int, detailed: Bool) async throws -> (mainIdea: String, keyPoints: [String]) {
        let trimmedBody = String(body.prefix(charLimit))
        let instructions = detailed
            ? "You summarize news and web articles for a fast, distraction-free reader. Be neutral and factual. Strip noise, ads, and unrelated links; focus only on the actual substance. When the article is itself a list or ranking (e.g. best albums, top 10, roundups), enumerate the real named items it contains — titles, artists, products — rather than describing that a list exists."
            : "You write a brief, high-level, neutral news summary for a general audience. Stay factual but avoid graphic or explicit detail. Focus on who, what, and why it matters, in general terms."
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Article title: \(title)\n\nArticle text:\n\(trimmedBody)"
        let response = try await session.respond(to: prompt, generating: ArticleDigestPayload.self)
        return (response.content.mainIdea, response.content.keyPoints)
    }

    private enum SummarizerError: Error {
        case allAttemptsFailed
    }
}
