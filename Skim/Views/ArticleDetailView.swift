import SwiftUI

struct ArticleDetailView: View {
    let headline: Headline
    @ObservedObject var model: SourceDigestModel

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content(availableWidth: proxy.size.width)
            }
        }
    }

    private func content(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            header

            if model.isSummarizingSelected || model.summarizeError != nil {
                // One stable HStack/Spacer wrapper for both states, so the
                // isSummarizing → error transition swaps only the inner
                // content instead of removing and reinserting this whole
                // centered container — doing the latter was somehow leaving
                // it (and, as a side effect, the sibling link below) with a
                // stale, too-narrow measured width in this particular
                // GeometryReader/ScrollView nesting.
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if model.isSummarizingSelected {
                        ProgressView()
                            .controlSize(.small)
                        Text("Summarizing…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else if let error = model.summarizeError {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 0)
                }
                // Forces SwiftUI to treat this as fresh content exactly when
                // the summarizing → error/success transition happens, rather
                // than risk it inheriting a stale, too-narrow width measured
                // while the much smaller "Summarizing…" indicator was there.
                .id(model.isSummarizingSelected ? "loading" : (model.summarizeError ?? "none"))
            } else if let digest = model.selectedDigest {
                digestBody(digest)
            }

            if let url = headline.url {
                HStack {
                    Spacer(minLength: 0)
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text("Open full article")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 13, weight: .medium))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(28)
        .frame(width: min(560, availableWidth))
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 18) {
            let imageURLString = model.selectedDigest?.imageURLString ?? headline.imageURLString
            if let imageURLString, let imageURL = URL(string: imageURLString) {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.primary.opacity(0.06)
                    }
                }
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipped()
            }

            HStack {
                Spacer(minLength: 0)
                Text(headline.title)
                    .font(.system(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                Spacer(minLength: 0)
            }
        }
    }

    private func digestBody(_ digest: ArticleDigest) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: 8, height: 8)
                    .padding(.top, 8)
                    .frame(width: 22, alignment: .leading)
                Text(digest.mainIdea)
                    .font(.system(size: 19, weight: .medium))
                    .lineSpacing(6)
                    .foregroundStyle(.primary)
            }

            if !digest.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(digest.keyPoints.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .leading)
                            Text(point)
                                .font(.system(size: 15))
                                .lineSpacing(5)
                                .foregroundStyle(.primary.opacity(0.82))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 11)

                        if index < digest.keyPoints.count - 1 {
                            Divider()
                                .opacity(0.4)
                                .padding(.leading, 36)
                        }
                    }
                }
            }
        }
    }
}
