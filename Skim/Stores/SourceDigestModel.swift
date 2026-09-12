import Foundation
import SwiftUI
import FoundationModels

@MainActor
final class SourceDigestModel: ObservableObject {
    /// How many of a source's freshest headlines get summarized proactively
    /// in the background, so they're ready before the user ever clicks them.
    private static let backgroundPrefetchLimit = 25

    @Published private var headlinesBySource: [UUID: [Headline]] = [:]
    @Published private var loadingSourceIDs: Set<UUID> = []
    @Published private var headlineErrorBySource: [UUID: String] = [:]

    @Published var selectedHeadline: Headline?
    @Published var selectedDigest: ArticleDigest?
    @Published var isSummarizingSelected = false
    @Published var summarizeError: String?

    @Published private(set) var digestCache: [String: ArticleDigest] = [:]
    @Published private(set) var failedSummaries: [String: String] = [:]
    private var pendingDigestURLs: Set<String> = []

    private var backgroundQueue: [Headline] = []
    private var isProcessingBackgroundQueue = false

    func headlines(for source: Source) -> [Headline] {
        headlinesBySource[source.id] ?? []
    }

    func isLoading(for source: Source) -> Bool {
        loadingSourceIDs.contains(source.id)
    }

    func headlineError(for source: Source) -> String? {
        headlineErrorBySource[source.id]
    }

    func loadIfNeeded(for source: Source) {
        guard headlinesBySource[source.id] == nil, !loadingSourceIDs.contains(source.id) else { return }
        load(for: source)
    }

    func reload(for source: Source) {
        load(for: source)
    }

    /// Kicks off headline loading for every given source that hasn't loaded
    /// yet, so background prefetching can warm the cache for sources the
    /// user hasn't opened this session, not just the selected one.
    func loadAll(_ sources: [Source]) {
        for source in sources {
            loadIfNeeded(for: source)
        }
    }

    /// Re-fetches headlines for every source without disturbing whatever is
    /// currently on screen — used for periodic auto-refresh.
    func refreshAll(_ sources: [Source]) {
        for source in sources {
            load(for: source, silent: true)
        }
    }

    private func load(for source: Source, silent: Bool = false) {
        guard let url = source.url else { return }
        let sourceID = source.id
        if !silent {
            headlinesBySource[sourceID] = nil
            headlineErrorBySource[sourceID] = nil
            loadingSourceIDs.insert(sourceID)
        }

        Task {
            do {
                let result = try await ArticleExtractor.loadHeadlines(from: url)
                self.headlinesBySource[sourceID] = result
                self.loadingSourceIDs.remove(sourceID)
                if result.isEmpty {
                    if !silent {
                        self.headlineErrorBySource[sourceID] = "Couldn't find headlines on this page. Try the live site instead."
                    }
                } else {
                    self.headlineErrorBySource[sourceID] = nil
                    self.enqueueBackgroundPrefetch(result)
                }
            } catch {
                self.loadingSourceIDs.remove(sourceID)
                if !silent {
                    self.headlineErrorBySource[sourceID] = "Couldn't load this source. Check your connection and try again."
                }
            }
        }
    }

    func select(_ headline: Headline) {
        selectedHeadline = headline
        summarizeError = nil

        if let cached = digestCache[headline.urlString] {
            selectedDigest = cached
            isSummarizingSelected = false
            return
        }

        // Already know this one fails — show the reason instantly instead of
        // re-running the whole extraction + summarization chain again.
        if let failure = failedSummaries[headline.urlString] {
            selectedDigest = nil
            isSummarizingSelected = false
            summarizeError = failure
            return
        }

        selectedDigest = nil
        guard let url = headline.url else { return }
        isSummarizingSelected = true

        // If this headline is already being summarized (e.g. picked up by
        // background prefetch), don't start a second, redundant session —
        // the in-flight one will update the UI itself once it completes,
        // since it checks `selectedHeadline` at completion time.
        guard !pendingDigestURLs.contains(headline.urlString) else { return }
        pendingDigestURLs.insert(headline.urlString)

        Task {
            await summarize(url: url, key: headline.urlString)
        }
    }

    func prefetch(_ headline: Headline) {
        Task { await summarizeIfNeeded(headline) }
    }

    func cachedDigest(for headline: Headline) -> ArticleDigest? {
        digestCache[headline.urlString]
    }

    private func enqueueBackgroundPrefetch(_ headlines: [Headline]) {
        let candidates = Array(headlines.prefix(Self.backgroundPrefetchLimit))
        let newOnes = candidates.filter {
            digestCache[$0.urlString] == nil && failedSummaries[$0.urlString] == nil && !backgroundQueue.contains($0)
        }
        backgroundQueue.append(contentsOf: newOnes)
        processBackgroundQueueIfNeeded()
    }

    /// Single global serial queue so background prefetching from multiple
    /// sources never runs more than one on-device summarization at a time —
    /// the model is a shared, fairly heavy resource, and user-driven
    /// requests (click, hover) should never have to contend with it.
    private func processBackgroundQueueIfNeeded() {
        guard !isProcessingBackgroundQueue else { return }
        isProcessingBackgroundQueue = true
        Task { [weak self] in
            guard let self else { return }
            while !self.backgroundQueue.isEmpty {
                let next = self.backgroundQueue.removeFirst()
                await self.summarizeIfNeeded(next)
            }
            self.isProcessingBackgroundQueue = false
        }
    }

    private func summarizeIfNeeded(_ headline: Headline) async {
        guard digestCache[headline.urlString] == nil,
              failedSummaries[headline.urlString] == nil,
              !pendingDigestURLs.contains(headline.urlString),
              let url = headline.url else { return }
        pendingDigestURLs.insert(headline.urlString)
        await summarize(url: url, key: headline.urlString)
    }

    private func summarize(url: URL, key: String) async {
        defer { pendingDigestURLs.remove(key) }
        do {
            let (title, body, imageURLString) = try await ArticleExtractor.extractArticle(from: url)
            guard !body.isEmpty else {
                throw SummarizeStepError.emptyBody
            }
            let result = try await Summarizer.summarize(title: title, body: body)
            let digest = ArticleDigest(mainIdea: result.mainIdea, keyPoints: result.keyPoints, imageURLString: imageURLString)
            digestCache[key] = digest
            if selectedHeadline?.urlString == key {
                selectedDigest = digest
                isSummarizingSelected = false
            }
        } catch LanguageModelSession.GenerationError.refusal {
            let message = "Apple's on-device model declined to summarize this one — it flags articles on sensitive topics like war or violence. Try \"Open full article\" instead."
            failedSummaries[key] = message
            if selectedHeadline?.urlString == key {
                isSummarizingSelected = false
                summarizeError = message
            }
        } catch {
            let message = "Couldn't summarize this article. It may not have extractable body text."
            failedSummaries[key] = message
            if selectedHeadline?.urlString == key {
                isSummarizingSelected = false
                summarizeError = message
            }
        }
    }

    enum SummarizeStepError: Error {
        case emptyBody
    }
}
