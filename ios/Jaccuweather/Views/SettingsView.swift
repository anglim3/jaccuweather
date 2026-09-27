import SwiftUI

struct SettingsView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var googleKey = ""
    @State private var tomorrowKey = ""
    @State private var nwsAgent = ""
    @State private var savedNote = ""

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JWMetrics.sectionGap) {
                    WeatherCard(title: "On this device", titleStyle: .section) {
                        Text("Keys stay in this device’s Keychain. Blank pollen keys keep the Open-Meteo fallback. Nothing here is written into the project.")
                            .font(.footnote)
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    WeatherCard(title: "Pollen", titleStyle: .section) {
                        field("Google Pollen API key") {
                            SecureField("Paste key", text: $googleKey)
                                .textContentType(.password)
                        }
                        field("Tomorrow.io API key") {
                            SecureField("Paste key", text: $tomorrowKey)
                                .textContentType(.password)
                        }
                        HStack {
                            Text("Next fetch")
                                .font(.subheadline)
                                .foregroundStyle(theme.muted)
                            Spacer(minLength: 12)
                            Text(previewSource)
                                .font(.footnote)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(theme.text)
                        }
                        .padding(.top, 4)
                    }

                    WeatherCard(title: "NWS User-Agent", titleStyle: .section) {
                        field("User-Agent") {
                            TextField("Contact you control", text: $nwsAgent, axis: .vertical)
                                .lineLimit(2...4)
                        }
                        Text("api.weather.gov requires an identifying User-Agent. Use a contact you control. The built-in default has no email address.")
                            .font(.footnote)
                            .foregroundStyle(theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 10) {
                        Button { save(refresh: true) } label: {
                            Text("Save and refresh")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                        .jwGlass(.panel)

                        Button { clearStored() } label: {
                            Text("Clear stored keys")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(JWTone.red)
                        .jwGlass(.stat)
                    }

                    if !savedNote.isEmpty {
                        Text(savedNote)
                            .font(.footnote)
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .jwScreenChrome()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.muted)
            content()
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .foregroundStyle(theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .jwGlass(.stat)
        }
    }

    private var previewSource: String {
        let google = googleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let tomorrow = tomorrowKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !google.isEmpty { return "Google → Tomorrow → Open-Meteo" }
        if !tomorrow.isEmpty { return "Tomorrow → Open-Meteo" }
        return "Open-Meteo"
    }

    private func load() {
        googleKey = KeychainStore.string(for: KeychainStore.googlePollenKey) ?? ""
        tomorrowKey = KeychainStore.string(for: KeychainStore.tomorrowKey) ?? ""
        nwsAgent = KeychainStore.string(for: KeychainStore.nwsUserAgentKey) ?? Secrets.nwsUserAgent
    }

    private func save(refresh: Bool) {
        KeychainStore.set(googleKey, for: KeychainStore.googlePollenKey)
        KeychainStore.set(tomorrowKey, for: KeychainStore.tomorrowKey)
        let agent = nwsAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        if agent.isEmpty || agent == Secrets.defaultNWSUserAgent {
            KeychainStore.delete(KeychainStore.nwsUserAgentKey)
        } else {
            KeychainStore.set(agent, for: KeychainStore.nwsUserAgentKey)
        }
        savedNote = "Saved on this device. Pollen path: \(Secrets.pollenSourceLabel)."
        if refresh {
            Task { await model.refresh() }
        }
    }

    private func clearStored() {
        KeychainStore.delete(KeychainStore.googlePollenKey)
        KeychainStore.delete(KeychainStore.tomorrowKey)
        KeychainStore.delete(KeychainStore.nwsUserAgentKey)
        googleKey = ""
        tomorrowKey = ""
        nwsAgent = Secrets.defaultNWSUserAgent
        savedNote = "Keychain cleared. Pollen uses Open-Meteo until you add a key."
        Task { await model.refresh() }
    }
}
