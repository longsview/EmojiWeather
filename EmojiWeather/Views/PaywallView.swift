import SwiftUI

/// Placeholder paywall. It lists what EmojiWeather+ includes; StoreKit 2 purchase buttons come next.
struct PaywallView: View {
    var reason: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("✨ EmojiWeather+")
                        .font(.largeTitle.bold())
                    if let reason {
                        Text(reason)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(PlusFeature.allCases) { feature in
                        HStack(spacing: 14) {
                            Text(feature.emoji).font(.title)
                            Text(feature.title).font(.headline)
                        }
                    }

                    Text("$1.99 a month, $9.99 a year with a 7-day free trial, or $14.99 once.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        // TODO: StoreKit 2 purchase.
                    } label: {
                        Text("Coming soon")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    PaywallView(reason: "Free includes 3 cities. EmojiWeather+ removes the limit.")
}
