import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SourceStore
    @StateObject private var digestModel = SourceDigestModel()
    @State private var viewMode: ViewMode = .digest
    @State private var reloadToken = 0
    @AppStorage("skim.listDensity") private var listDensityRaw: String = ListDensity.comfortable.rawValue

    private var listDensity: ListDensity {
        ListDensity(rawValue: listDensityRaw) ?? .comfortable
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case digest = "Digest"
        case live = "Live Site"
        var id: String { rawValue }
    }

    /// Headlines go stale gradually, not by the minute, and re-checking costs
    /// a real re-scrape plus on-device summarization for whatever's new — so
    /// this favors a calm background cadence over aggressive freshness.
    private static let autoRefreshInterval: TimeInterval = 15 * 60

    var body: some View {
        HStack(spacing: 0) {
            SourceRailView()

            Group {
                if let source = store.selectedSource {
                    mainContent(for: source)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
        .onChange(of: store.selectedSourceID) { _, _ in
            viewMode = .digest
        }
        .onChange(of: store.sources.map(\.id)) { _, _ in
            digestModel.loadAll(store.sources)
        }
        .task {
            digestModel.loadAll(store.sources)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.autoRefreshInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                digestModel.refreshAll(store.sources)
            }
        }
    }

    @ViewBuilder
    private func mainContent(for source: Source) -> some View {
        VStack(spacing: 0) {
            toolbar(for: source)
            Divider()

            switch viewMode {
            case .digest:
                DigestListView(source: source, model: digestModel, density: listDensity)
            case .live:
                WebViewContainer(url: source.url ?? URL(string: "about:blank")!, reloadToken: $reloadToken)
            }
        }
    }

    private func toolbar(for source: Source) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(source.title)
                .font(.system(size: 13, weight: .semibold))

            if source.title.caseInsensitiveCompare(source.host) != .orderedSame {
                Text(source.host)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button {
                if viewMode == .digest {
                    digestModel.reload(for: source)
                } else {
                    reloadToken += 1
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 20)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .rotationEffect(.degrees(digestModel.isLoading(for: source) ? 360 : 0))
                    .animation(
                        digestModel.isLoading(for: source)
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: digestModel.isLoading(for: source)
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh \(viewMode == .digest ? "headlines" : "page")")
            .padding(.leading, 4)

            Spacer()

            if viewMode == .digest {
                densityToggle
                    .padding(.trailing, 8)
            }

            Picker("", selection: $viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var densityToggle: some View {
        HStack(spacing: 2) {
            densityButton(.compact, icon: "list.bullet", help: "Compact list")
            densityButton(.comfortable, icon: "rectangle.grid.1x2", help: "Comfortable list with images")
        }
        .padding(3)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func densityButton(_ density: ListDensity, icon: String, help: String) -> some View {
        let isSelected = listDensity == density
        return Button {
            listDensityRaw = density.rawValue
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .background(isSelected ? Color.primary.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Add up to 5 sources to get started")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
