import SwiftUI

struct SourceRailView: View {
    @EnvironmentObject private var store: SourceStore
    @State private var hoveredID: UUID?
    @State private var showingAddPopover = false

    var body: some View {
        VStack(spacing: 14) {
            ForEach(store.sources) { source in
                sourceIcon(source)
            }

            if store.canAddMore {
                Button {
                    showingAddPopover = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingAddPopover, arrowEdge: .trailing) {
                    AddSourceView(isPresented: $showingAddPopover)
                }
            }

            Spacer()
        }
        .padding(.vertical, 20)
        .frame(width: 76)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private func sourceIcon(_ source: Source) -> some View {
        let isSelected = store.selectedSourceID == source.id
        let isHovered = hoveredID == source.id

        ZStack(alignment: .topTrailing) {
            Button {
                store.selectedSourceID = source.id
            } label: {
                iconImage(for: source)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(isSelected ? 0.1 : 0.0))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(isSelected ? 0.25 : 0), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .help(source.title)

            if isHovered {
                Button {
                    store.remove(source.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary, Color.primary.opacity(0.08))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
        .onHover { hovering in
            hoveredID = hovering ? source.id : (hoveredID == source.id ? nil : hoveredID)
        }
    }

    @ViewBuilder
    private func iconImage(for source: Source) -> some View {
        if let data = source.faviconData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
        } else {
            Text(source.initial)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
