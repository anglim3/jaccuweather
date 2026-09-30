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
                    dataSourcesCard

                    WeatherCard(title: "Appearance", titleStyle: .section) {
                        Text("Dark keeps the navy glass. Light follows the forecast and paints the same sky as the website.")
                            .font(.footnote)
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 4) {
                            appearanceChoice(.dark, title: "Dark", systemImage: "moon.fill")
                            appearanceChoice(.light, title: "Light", systemImage: "sun.max.fill")
                        }
                        .padding(4)
                        .jwGlass(.stat)
                        Text(skyLine)
                            .font(.footnote)
                            .foregroundStyle(theme.faint)
                            .accessibilityIdentifier("appearance-sky")
                    }

                    WeatherCard(title: "Notifications", titleStyle: .section) {
                        Text("A refresh that finds a new active National Weather Service alert for this place can notify this phone. Each alert is shown once. Nothing is sent to a server.")
                            .font(.footnote)
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(isOn: alertNotificationsBinding) {
                            Text("Alert notifications")
                                .font(.body.weight(.semibold))
                        }
                        .tint(theme.accent)
                        .accessibilityIdentifier("alert-notifications-toggle")
                        Text("A forecast refresh can also notify this phone when rain or snow looks likely to start in the next few hours. This uses the forecast already on the phone. It does not use a server push.")
                            .font(.footnote)
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(isOn: precipNotificationsBinding) {
                            Text("Precipitation notifications")
                                .font(.body.weight(.semibold))
                        }
                        .tint(theme.accent)
                        .accessibilityIdentifier("precip-notifications-toggle")
                        if !model.alertNotificationNote.isEmpty {
                            Text(model.alertNotificationNote)
                                .font(.footnote)
                                .foregroundStyle(theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("alert-notifications-note")
                            Button("Open iOS Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.accent)
                        }
                        Text("Uses the forecast already loaded in the app. When tonight’s low is at or below 32°, this phone can show one local notice. Nothing is sent from a server.")
                            .font(.footnote)
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(isOn: freezeNotificationsBinding) {
                            Text("Freeze warnings")
                                .font(.body.weight(.semibold))
                        }
                        .tint(theme.accent)
                        .accessibilityIdentifier("freeze-notifications-toggle")
                        if !model.freezeNotificationNote.isEmpty {
                            Text(model.freezeNotificationNote)
                                .font(.footnote)
                                .foregroundStyle(theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("freeze-notifications-note")
                            Button("Open iOS Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.accent)
                        }
                    }

                    #if DEBUG
                    WeatherCard(title: "Debug", titleStyle: .section) {
                        Text("Posts one sample local notification. It is not a live National Weather Service alert.")
                            .font(.footnote)
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            Task { await model.postSampleAlertNotification() }
                        } label: {
                            Text("Post sample notification")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                        .jwGlass(.stat)
                        .accessibilityIdentifier("alert-notification-sample")
                        Text("Posts one sample precipitation notification. It is not a live forecast.")
                            .font(.footnote)
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            Task { await model.postSamplePrecipNotification() }
                        } label: {
                            Text("Post sample precipitation")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                        .jwGlass(.stat)
                        .accessibilityIdentifier("precip-notification-sample")
                        Text("Posts one sample freeze notice. It is not a live forecast.")
                            .font(.footnote)
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            Task { await model.postSampleFreezeNotification() }
                        } label: {
                            Text("Post freeze sample")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                        .jwGlass(.stat)
                        .accessibilityIdentifier("freeze-notification-sample")
                    }
                    #endif

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
            .onAppear {
                load()
                Task { await model.refreshAlertNotificationStatus() }
                Task { await model.refreshFreezeNotificationStatus() }
            }
        }
    }

    private var dataSourcesCard: some View {
        WeatherCard(title: "Data sources", titleStyle: .section) {
            Text("Forecasts, air quality, and the pollen fallback come from Open-Meteo. Ensemble values are averaged for display.")
                .font(.footnote)
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: APIEndpoints.openMeteo) {
                Text("Weather data by Open-Meteo.com")
                    .font(.subheadline.weight(.semibold))
                    .underline()
            }
            .accessibilityIdentifier("open-meteo-credit")
            Link(destination: APIEndpoints.ccBy4) {
                Text("CC BY 4.0")
                    .font(.subheadline.weight(.semibold))
                    .underline()
            }
            .accessibilityIdentifier("cc-by-credit")
            Text("Radar, alerts, and US snow totals come from NOAA and the National Weather Service.")
                .font(.footnote)
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Link(destination: APIEndpoints.noaaRadarCredit) {
                Text("NOAA / NWS disclaimer")
                    .font(.subheadline.weight(.semibold))
                    .underline()
            }
            .accessibilityIdentifier("nws-disclaimer-credit")
        }
        .tint(theme.accent)
    }

    private var precipNotificationsBinding: Binding<Bool> {
        Binding(
            get: { model.precipNotificationsOn },
            set: { enabled in
                Task { await model.setPrecipNotificationsEnabled(enabled) }
            }
        )
    }

    private var freezeNotificationsBinding: Binding<Bool> {
        Binding(
            get: { model.freezeNotificationsOn },
            set: { enabled in
                Task { await model.setFreezeNotificationsEnabled(enabled) }
            }
        )
    }

    private var alertNotificationsBinding: Binding<Bool> {
        Binding(
            get: { model.alertNotificationsOn },
            set: { enabled in
                Task { await model.setAlertNotificationsEnabled(enabled) }
            }
        )
    }

    private var skyLine: String {
        if model.appearance == .light {
            if model.weather == nil { return "The sky fills in when the forecast loads." }
            return "Sky: \(model.pageSky.title)"
        }
        return "Navy background"
    }

    private func appearanceChoice(_ value: JWAppearance, title: String, systemImage: String) -> some View {
        let selected = model.appearance == value
        return Button {
            model.setAppearance(value)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? theme.text : theme.muted)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: JWMetrics.radiusSm, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(value == .light ? "appearance-light" : "appearance-dark")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
