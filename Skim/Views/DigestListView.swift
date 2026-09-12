import SwiftUI

struct DigestListView: View {
    let source: Source
    @ObservedObject var model: SourceDigestModel
    let density: ListDensity
    @State private var hoverTarget: Headline?

    private let listMinWidth: CGFloat = 300
    private let detailMinWidth: CGFloat = 340

    /// Fraction of the pane's total width given to the headline list. 0.4
    /// defaults to a 60:40 article:list split — the article is the point of
    /// the app, so the list shouldn't be fighting it for space. Persisted so
    /// a manual resize sticks across relaunches, same as the window frame.
    @AppStorage("skim.listWidthFraction") private var listWidthFraction: Double = 0.4
    @State private var dragStartFraction: Double?

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                headlineList
                    .frame(width: listWidth(totalWidth: geo.size.width))

                splitterHandle(totalWidth: geo.size.width)

                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { model.loadIfNeeded(for: source) }
        .onChange(of: source.id) { _, _ in model.loadIfNeeded(for: source) }
    }

    private func listWidth(totalWidth: CGFloat) -> CGFloat {
        let maxWidth = max(totalWidth - detailMinWidth, listMinWidth)
        return min(max(totalWidth * listWidthFraction, listMinWidth), maxWidth)
    }

    private func splitterHandle(totalWidth: CGFloat) -> some View {
        Divider()
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let baseFraction = dragStartFraction ?? listWidthFraction
                                if dragStartFraction == nil { dragStartFraction = listWidthFraction }
                                let baseWidth = totalWidth * baseFraction
                                let maxWidth = max(totalWidth - detailMinWidth, listMinWidth)
                                let proposed = min(max(baseWidth + value.translation.width, listMinWidth), maxWidth)
                                guard totalWidth > 0 else { return }
                                listWidthFraction = proposed / totalWidth
                            }
                            .onEnded { _ in
                                dragStartFraction = nil
                            }
                    )
            )
    }

    private var headlineList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.isLoading(for: source) {
                    ProgressView("Reading \(source.host)…")
                        .padding(24)
                        .frame(maxWidth: .infinity)
                } else if let error = model.headlineError(for: source) {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(24)
                } else {
                    ForEach(model.headlines(for: source)) { headline in
                        headlineRow(headline)
                        Divider().opacity(0.5)
                    }
                }
            }
        }
    }

    private func headlineRow(_ headline: Headline) -> some View {
        let isSelected = model.selectedHeadline == headline
        let isHovered = hoverTarget == headline
        let isComfortable = density == .comfortable

        return Button {
            model.select(headline)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if isComfortable {
                    thumbnail(for: headline)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(headline.title)
                        .font(isComfortable ? .system(size: 15, weight: .semibold) : .system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isComfortable ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: isComfortable)

                    if let failure = model.failedSummaries[headline.urlString] {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 10))
                            Text("Summary unavailable")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.tertiary)
                        .help(failure)
                    } else if let mainIdea = model.cachedDigest(for: headline)?.mainIdea, isHovered || isComfortable {
                        Text(mainIdea)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(isComfortable ? 3 : 2)
                            .transition(.opacity)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, isComfortable ? 14 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoverTarget = hovering ? headline : (hoverTarget == headline ? nil : hoverTarget)
            if hovering {
                model.prefetch(headline)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hoverTarget)
    }

    @ViewBuilder
    private func thumbnail(for headline: Headline) -> some View {
        let size: CGFloat = 84
        if let urlString = headline.imageURLString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.primary.opacity(0.05)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipped()
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                )
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let headline = model.selectedHeadline {
            ArticleDetailView(headline: headline, model: model)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text("Click a headline to read the main idea")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
