import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Unlock premium")
                        .font(.title.bold())
                        .foregroundStyle(colorScheme == .dark ? .white : AppTheme.textPrimary)

                    Text("Subscribe for full access to every premium lesson and future releases.")
                        .font(.body)
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.75) : AppTheme.textSecondary)

                    VStack(alignment: .leading, spacing: 12) {
                        benefitRow("All premium chapters in every book")
                        benefitRow("New premium content as it ships")
                        benefitRow("Supports Fusha Nation on iPhone and iPad")
                    }
                    .padding(.vertical, 4)

                    if let product = subscriptionStore.products.first {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(product.displayName)
                                .font(.headline)
                                .foregroundStyle(colorScheme == .dark ? .white : AppTheme.textPrimary)
                            Text(product.description)
                                .font(.subheadline)
                                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : AppTheme.textSecondary)
                            Text(product.displayPrice)
                                .font(.title2.bold())
                                .foregroundStyle(AppTheme.forestGreen)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.9))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : AppTheme.readerCardStroke, lineWidth: 1)
                        )
                    } else if subscriptionStore.isLoadingProducts {
                        ProgressView("Loading plans…")
                            .tint(AppTheme.forestGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        Text("Subscriptions aren’t available right now. Check your connection or try again after products are configured in App Store Connect.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let message = subscriptionStore.purchaseError {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await subscriptionStore.purchasePrimarySubscription() }
                    } label: {
                        if subscriptionStore.isPurchasing {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Subscribe")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.forestGreen)
                    .disabled(subscriptionStore.products.isEmpty || subscriptionStore.isPurchasing)

                    Button("Restore purchases") {
                        Task { await subscriptionStore.restorePurchases() }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentBlue)
                    .disabled(subscriptionStore.isPurchasing)

                    Text("Payment is charged to your Apple ID. Subscriptions renew automatically until cancelled in Settings.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding(24)
            }
            .background(colorScheme == .dark ? Color(white: 0.1) : AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .task {
            await subscriptionStore.loadProducts()
        }
        .onChange(of: subscriptionStore.isSubscribed) { _, subscribed in
            if subscribed { dismiss() }
        }
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.forestGreen)
                .imageScale(.medium)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.88) : AppTheme.textPrimary)
        }
    }
}

#Preview {
    PaywallView()
        .environmentObject(SubscriptionStore())
}
