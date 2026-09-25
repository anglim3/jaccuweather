import SwiftUI

struct SearchSheet: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var waitingForFix = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    Button(action: useMyLocation) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "location.fill")
                                .font(.body.weight(.semibold))
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use my location")
                                Text(waitingForFix ? "Finding your location…" : "Weather for where this phone is")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if waitingForFix {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .accessibilityLabel("Use my location")
                    .accessibilityHint("Weather for where this phone is")
                }
                if model.favorites.items.isEmpty == false {
                    Section("Favorites") {
                        ForEach(model.favorites.items) { place in
                            Button(place.displayName) {
                                Task {
                                    await model.select(place)
                                    dismiss()
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    model.favorites.remove(place)
                                } label: {
                                    Label("Remove", systemImage: "trash")
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
            .onChange(of: model.hasResolvedPlace) { _, resolved in
                if waitingForFix && resolved { dismiss() }
            }
            .onChange(of: model.showsPlacePrompt) { _, prompted in
                if waitingForFix && prompted { dismiss() }
            }
            .onChange(of: model.isLocating) { _, locating in
                guard waitingForFix, locating == false else { return }
                if model.hasResolvedPlace || model.showsPlacePrompt { dismiss() }
            }
        }
    }

    private func useMyLocation() {
        model.requestDeviceLocation()
        if model.hasResolvedPlace || model.showsPlacePrompt {
            dismiss()
        } else {
            waitingForFix = true
        }
    }
}
