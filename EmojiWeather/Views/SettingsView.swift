import StoreKit
import SwiftUI
import WidgetKit

/// Units, clock, motion and Skymoji+. "Automatic" follows the region in iOS Settings.
struct SettingsView: View {
    @Environment(PurchaseManager.self) private var purchases

    @AppStorage(DisplaySettings.temperatureKey, store: SharedStore.defaults)
    private var temperature: TemperatureSetting = .automatic
    @AppStorage(DisplaySettings.clockKey, store: SharedStore.defaults)
    private var clock: ClockSetting = .automatic
    @AppStorage(DisplaySettings.animateScenesKey, store: SharedStore.defaults)
    private var animateScenes = true

    @AppStorage(SceneStyle.packKey, store: SharedStore.defaults)
    private var scenePack: ScenePack = .classic
    @AppStorage(SceneStyle.customEmojiKey, store: SharedStore.defaults)
    private var customEmoji = ""

    @State private var showingPaywall = false
    @State private var showingManageSubscription = false

    private var regionUnitName: String {
        DisplaySettings.regionTemperatureUnit == .fahrenheit ? "°F" : "°C"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $temperature) {
                        Text("Automatic (\(regionUnitName))").tag(TemperatureSetting.automatic)
                        Text("Celsius (°C)").tag(TemperatureSetting.celsius)
                        Text("Fahrenheit (°F)").tag(TemperatureSetting.fahrenheit)
                    } label: {
                        Label("Temperature", systemImage: "thermometer.medium")
                    }

                    Picker(selection: $clock) {
                        Group {
                            if DisplaySettings.regionUses12HourClock {
                                Text("Automatic (12-hour)")
                            } else {
                                Text("Automatic (24-hour)")
                            }
                        }
                        .tag(ClockSetting.automatic)
                        Text("12-hour").tag(ClockSetting.twelveHour)
                        Text("24-hour").tag(ClockSetting.twentyFourHour)
                    } label: {
                        Label("Clock", systemImage: "clock")
                    }
                } header: {
                    Text("Units")
                } footer: {
                    Text("Automatic follows your region in iOS Settings > General > Language & Region.")
                }

                Section {
                    Toggle(isOn: $animateScenes) {
                        Label("Animated scenes", systemImage: "sparkles")
                    }
                } header: {
                    Text("Motion")
                } footer: {
                    Text("When Reduce Motion is on, scenes move slowly and lightning doesn't flash. Turn this off for still scenes.")
                }

                Section {
                    plusLink {
                        ScenePackView()
                    } label: {
                        LabeledContent {
                            Text(scenePack.title)
                        } label: {
                            Label("Scene pack", systemImage: "leaf")
                        }
                    }
                    plusLink {
                        CustomEmojiView()
                    } label: {
                        LabeledContent {
                            let customCount = SceneStyle.decodeCustom(customEmoji).count
                            if customCount > 0 { Text("\(customCount) custom") }
                        } label: {
                            Label("Your own emoji", systemImage: "face.smiling")
                        }
                    }
                } header: {
                    Text("Scenes")
                } footer: {
                    Text("Dress up every scene for the season, or swap the sun, moon, clouds and more for your own emoji or Genmoji.")
                }

                Section {
                    if purchases.hasPlus {
                        Label("Skymoji+ is active. Thank you!", systemImage: "checkmark.seal.fill")
                        Button("Manage Subscription") { showingManageSubscription = true }
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            Label("Get Skymoji+", systemImage: "sparkles")
                        }
                    }
                    Button("Restore Purchases") {
                        Task { await purchases.restore() }
                    }
                } header: {
                    Text("Skymoji+")
                }

                Section {
                    Link(destination: URL(string: "https://longsview.github.io/skymoji/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    NavigationLink {
                        DataSourcesView()
                    } label: {
                        Label("Data Sources", systemImage: "text.book.closed")
                    }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .manageSubscriptionsSheet(isPresented: $showingManageSubscription)
            .onChange(of: temperature) { WidgetCenter.shared.reloadAllTimelines() }
            .onChange(of: clock) { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    /// Opens the screen for Skymoji+ members, and the paywall for everyone else.
    @ViewBuilder
    private func plusLink<Destination: View, Content: View>(
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder label: () -> Content
    ) -> some View {
        if purchases.hasPlus {
            NavigationLink(destination: destination, label: label)
        } else {
            Button {
                showingPaywall = true
            } label: {
                HStack {
                    label()
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Skymoji+"))
                }
                .foregroundStyle(.primary)
            }
        }
    }
}
