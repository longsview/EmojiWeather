import StoreKit
import SwiftUI

/// The Skymoji+ upsell: a little sunny scene, what Plus includes, and the two plans.
struct PaywallView: View {
    var reason: String?

    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: Plan = .yearly
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    enum Plan: CaseIterable, Identifiable {
        case monthly, yearly

        var id: Self { self }

        var productID: String {
            switch self {
            case .monthly: PurchaseManager.ProductID.monthly
            case .yearly: PurchaseManager.ProductID.yearly
            }
        }

        var emoji: String {
            switch self {
            case .monthly: "🌙"
            case .yearly: "☀️"
            }
        }

        var title: String {
            switch self {
            case .monthly: String(localized: "Monthly")
            case .yearly: String(localized: "Yearly")
            }
        }

        /// Shown until the App Store prices load (and in previews).
        var fallbackPrice: String {
            switch self {
            case .monthly: "$1.99"
            case .yearly: "$14.99"
            }
        }

        var period: String {
            switch self {
            case .monthly: String(localized: "a month")
            case .yearly: String(localized: "a year")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                features
                plans
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { footer }
        .onAppear { AppAnalytics.log(.paywallViewed) }
        .overlay(alignment: .topTrailing) { closeButton }
        .background(.white)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
        .presentationDetents([.large])
        .presentationCornerRadius(36)
        .alert("Purchase didn't go through", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: purchases.hasPlus) { _, hasPlus in
            if hasPlus { dismiss() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        ZStack(alignment: .bottom) {
            EmojiSceneView(
                conditions: SceneConditions(scene: .sunny, intensity: 0.7, windDrift: 0.2, sky: .day),
                paused: false
            )
            .frame(height: 230)
            .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))

            VStack(spacing: 6) {
                Text("Skymoji+")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                Text(reason ?? String(localized: "No ads, more cities, more emoji."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .shadow(color: .white, radius: 8)
            .shadow(color: .white, radius: 8)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(PlusFeature.allCases) { feature in
                HStack(spacing: 14) {
                    Text(feature.emoji)
                        .font(.system(size: 28))
                        .frame(width: 36)
                        .accessibilityHidden(true)
                    Text(feature.title)
                        .font(.system(.headline, design: .rounded))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
    }

    private var plans: some View {
        VStack(spacing: 10) {
            ForEach(Plan.allCases) { plan in
                PlanCard(
                    plan: plan,
                    product: purchases.product(plan.productID),
                    isSelected: plan == selectedPlan
                )
                .onTapGesture {
                    withAnimation(.snappy) { selectedPlan = plan }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                Task { await buy() }
            } label: {
                ZStack {
                    Text(callToAction).opacity(isPurchasing ? 0 : 1)
                    if isPurchasing { ProgressView().tint(.white) }
                }
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(.black, in: Capsule())
            }
            .disabled(isPurchasing)

            HStack(spacing: 20) {
                Button("Restore Purchases") {
                    Task { await purchases.restore() }
                }
                Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)

            Text(finePrint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .background(.white)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.black)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.06), in: Circle())
        }
        .padding(16)
        .accessibilityLabel("Close")
    }

    // MARK: - Purchase

    private var hasTrial: Bool {
        selectedPlan == .yearly
            && (purchases.product(PurchaseManager.ProductID.yearly)?.subscription?.introductoryOffer != nil
                || purchases.products.isEmpty)
    }

    private var callToAction: String {
        switch selectedPlan {
        case .yearly where hasTrial: String(localized: "Try 7 days free")
        default: String(localized: "Continue")
        }
    }

    private var finePrint: String {
        switch selectedPlan {
        case .yearly where hasTrial:
            String(localized: "Free for 7 days, then \(yearlyPrice) a year. Cancel anytime in Settings.")
        default:
            String(localized: "Renews automatically. Cancel anytime in Settings.")
        }
    }

    private var yearlyPrice: String { price(for: .yearly) }

    private func price(for plan: Plan) -> String {
        purchases.product(plan.productID)?.displayPrice ?? plan.fallbackPrice
    }

    private func buy() async {
        guard let product = purchases.product(selectedPlan.productID) else {
            errorMessage = String(localized: "The App Store isn't available right now. Try again in a moment.")
            await purchases.loadProducts()
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            if try await purchases.purchase(product) { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One plan: emoji, name, price, and a badge for the best value.
private struct PlanCard: View {
    let plan: PaywallView.Plan
    let product: Product?
    let isSelected: Bool

    private var price: String { product?.displayPrice ?? plan.fallbackPrice }

    /// "Just $0.83 a month" for the yearly plan.
    private var subtitle: String? {
        switch plan {
        case .yearly:
            if let product {
                let monthly = (product.price / 12).formatted(product.priceFormatStyle)
                return String(localized: "Just \(monthly) a month")
            }
            return String(localized: "Just \("$1.25") a month")
        case .monthly: return nil
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(plan.emoji).font(.system(size: 30)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(plan.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    if plan == .yearly {
                        Text("Best value")
                            .font(.system(.caption2, design: .rounded, weight: .heavy))
                            .textCase(.uppercase)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: 0xFFD54F), in: Capsule())
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(price)
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                Text(plan.period)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.black.opacity(isSelected ? 0.0 : 0.04), in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.black, lineWidth: isSelected ? 2.5 : 0)
        }
        .contentShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    PaywallView(reason: "Free includes 3 cities. Skymoji+ removes the limit.")
        .environment(PurchaseManager())
}
