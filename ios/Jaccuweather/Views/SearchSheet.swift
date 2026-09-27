import SwiftUI

struct SearchSheet: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var waitingForFix = false

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                searchPill(query: $model.searchQuery)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                List {
                    Section {
                        Button(action: useMyLocation) {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "location.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(theme.accent)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use my location")
                                        .foregroundStyle(theme.text)
                                    Text(waitingForFix ? "Finding your location…" : "Weather for where this phone is")
                                        .font(.caption)
                                        .foregroundStyle(theme.muted)
                                }
                                Spacer(minLength: 8)
                                if waitingForFix {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(theme.accent)
                                }
                            }
                        }
                        .accessibilityLabel("Use my location")
                        .accessibilityHint("Weather for where this phone is")
                        .listRowBackground(rowFill)
                    } header: {
                        SectionEyebrow(title: "Here")
                    }

                    if model.favorites.items.isEmpty == false {
                        Section {
                            ForEach(model.favorites.items) { place in
                                Button {
                                    Task {
                                        await model.select(place)
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(theme.gold)
                                            .frame(width: 28)
                                            .accessibilityHidden(true)
                                        Text(place.displayName)
                                            .foregroundStyle(theme.text)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        model.favorites.remove(place)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .listRowBackground(rowFill)
                            }
                        } header: {
                            SectionEyebrow(title: "Favorites")
                        }
                    }

                    if model.isSearching || model.searchResults.isEmpty == false || model.searchQuery.count >= 2 {
                        Section {
                            if model.isSearching {
                                HStack {
                                    ProgressView()
                                        .tint(theme.accent)
                                    Text("Searching")
                                        .font(.subheadline)
                                        .foregroundStyle(theme.muted)
                                }
                                .listRowBackground(rowFill)
                            }
                            ForEach(model.searchResults) { place in
                                Button {
                                    Task {
                                        await model.select(place)
                                        dismiss()
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(place.name)
                                            .foregroundStyle(theme.text)
                                        Text(place.displayName)
                                            .font(.caption)
                                            .foregroundStyle(theme.muted)
                                    }
                                }
                                .listRowBackground(rowFill)
                            }
                            if model.searchQuery.count >= 2 && model.searchResults.isEmpty && model.isSearching == false {
                                Text("No matches")
                                    .foregroundStyle(theme.faint)
                                    .listRowBackground(rowFill)
                            }
                        } header: {
                            SectionEyebrow(title: "Results")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .listRowSeparatorTint(theme.divider)
            }
            .jwScreenChrome()
            .onChange(of: model.searchQuery) { _, value in
                model.updateSearch(value)
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
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

    private var rowFill: Color { theme.card }

    private func searchPill(query: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.faint)
            TextField("Search city...", text: query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundStyle(theme.text)
                .tint(theme.accent)
            if query.wrappedValue.isEmpty == false {
                Button {
                    query.wrappedValue = ""
                    model.updateSearch("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.card, in: Capsule())
        .overlay(Capsule().stroke(theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
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
