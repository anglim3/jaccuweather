import SwiftUI

struct SettingsView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @AppStorage(JWAppearance.storageKey) private var appearance = JWAppearance.dark
    @State private var googleKey = ""
    @State private var tomorrowKey = ""
    @State private var nwsAgent = ""
    @State private var savedNote = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Keys stay in this device’s Keychain. Blank pollen keys keep the Open-Meteo fallback. Nothing here is written into the project.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("Dark").tag(JWAppearance.dark)
                        Text("Light").tag(JWAppearance.light)
                    }
                    .pickerStyle(.segmented)
                    Text("Saved on this device. Dark stays the default deep-blue glass. Light uses a pale glass palette.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Pollen") {
                    SecureField("Google Pollen API key", text: $googleKey)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Tomorrow.io API key", text: $tomorrowKey)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("Next fetch") {
                        Text(previewSource)
                            .font(.footnote)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    TextField("User-Agent", text: $nwsAgent, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(2...4)
                    Text("api.weather.gov requires an identifying User-Agent. Use a contact you control. The built-in default has no email address.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("NWS User-Agent")
                }

                Section {
                    Button("Save and refresh") { save(refresh: true) }
                    Button("Clear stored keys") { clearStored() }
                        .foregroundStyle(.red)
                }

                if !savedNote.isEmpty {
                    Section {
                        Text(savedNote).font(.footnote)
                    }
                }
            }
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
