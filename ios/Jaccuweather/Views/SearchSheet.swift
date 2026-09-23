import SwiftUI

struct SearchSheet: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                if model.favorites.items.isEmpty == false {
                    Section("Favorites") {
                        ForEach(model.favorites.items) { place in
                            Button(place.displayName) {
                                Task {
                                    await model.select(place)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
                Section("Search") {
                    if model.isSearching {
                        ProgressView()
                    }
                    ForEach(model.searchResults) { place in
                        Button {
                            Task {
                                await model.select(place)
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(place.name)
                                Text(place.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if model.searchQuery.count >= 2 && model.searchResults.isEmpty && model.isSearching == false {
                        Text("No matches")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $model.searchQuery, prompt: "City or place")
            .onChange(of: model.searchQuery) { _, value in
                model.updateSearch(value)
            }
            .navigationTitle("Location")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
