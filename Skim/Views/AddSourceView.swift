import SwiftUI

struct AddSourceView: View {
    @EnvironmentObject private var store: SourceStore
    @Binding var isPresented: Bool

    @State private var urlText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a source")
                .font(.system(size: 13, weight: .semibold))

            TextField("nytimes.com", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($fieldFocused)
                .onSubmit(save)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                Button(isSaving ? "Adding…" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .padding(16)
        .onAppear { fieldFocused = true }
    }

    private func save() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = normalize(trimmed)
        guard let url = URL(string: normalized), url.host != nil else {
            errorMessage = "That doesn't look like a valid website."
            return
        }

        isSaving = true
        errorMessage = nil
        let newSource = Source(urlString: normalized, title: url.host?.replacingOccurrences(of: "www.", with: "") ?? normalized)
        store.add(newSource)
        isPresented = false

        Task {
            if let data = await FaviconFetcher.fetch(for: normalized) {
                await MainActor.run {
                    store.updateFavicon(for: newSource.id, data: data)
                }
            }
        }

        Task {
            if let name = await SiteMetadataFetcher.fetchName(for: url) {
                await MainActor.run {
                    store.updateTitle(for: newSource.id, title: name)
                }
            }
        }
    }

    private func normalize(_ input: String) -> String {
        if input.lowercased().hasPrefix("http://") || input.lowercased().hasPrefix("https://") {
            return input
        }
        return "https://\(input)"
    }
}
