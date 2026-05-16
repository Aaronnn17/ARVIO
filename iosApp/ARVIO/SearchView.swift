import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Search")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(ArvioTheme.textPrimary)

            TextField("Search movies, shows and episodes", text: $query)
                .textInputAutocapitalization(.never)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
                .foregroundStyle(ArvioTheme.textPrimary)
                .onSubmit {
                    Task { await appState.tmdb.search(query) }
                }
                .onChange(of: query) { _, value in
                    Task { await appState.tmdb.search(value) }
                }

            MediaRail(title: query.isEmpty ? "Suggested" : "Results", items: query.isEmpty ? featuredItems : appState.tmdb.searchResults)

            Spacer()
        }
        .padding(28)
    }
}
