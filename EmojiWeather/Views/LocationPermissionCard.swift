import SwiftUI
import UIKit

/// Explains why the app wants location before the system prompt appears, and points to Settings
/// if the user already said no.
struct LocationPermissionCard: View {
    @Environment(LocationService.self) private var location
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("📍 Weather where you are")
                .font(.headline)

            if location.isDenied {
                Text("Location access is off. Turn it on in Settings, or add a city from the list.")
                    .font(.subheadline)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Allow location access to see the weather right where you are. It's only used to get your forecast.")
                    .font(.subheadline)
                Button("Allow Location") {
                    location.requestPermission()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
    }
}
