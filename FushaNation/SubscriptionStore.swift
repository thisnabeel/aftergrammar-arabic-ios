import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var isSubscribed: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts: Bool = false
    @Published var purchaseError: String?
    @Published var isPurchasing: Bool = false

    private var transactionListenerTask: Task<Void, Never>?

    init() {
        // Previews launch a JIT app process (`XCODE_RUNNING_FOR_PLAYGROUNDS`); StoreKit
        // listeners here correlate with “Failed to launch / launchd job spawn failed” on some setups.
        guard !Self.isRunningInXcodePreview else { return }
        transactionListenerTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.process(transactionUpdate: update)
            }
        }
        Task { await refreshEntitlement() }
    }

    private static var isRunningInXcodePreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    private func process(transactionUpdate: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionUpdate else { return }
        await transaction.finish()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard SubscriptionProductIDs.all.contains(transaction.productID) else { continue }
            if transaction.revocationDate == nil {
                active = true
                break
            }
        }
        isSubscribed = active
    }

    func loadProducts() async {
        isLoadingProducts = true
        purchaseError = nil
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: SubscriptionProductIDs.all)
        } catch {
            purchaseError = error.localizedDescription
            products = []
        }
    }

    func purchasePrimarySubscription() async {
        guard let product = products.first else {
            purchaseError = "No subscription is available yet. Try again later."
            return
        }
        await purchase(product)
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlement()
                case .unverified(_, let error):
                    purchaseError = error.localizedDescription
                }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            purchaseError = error.localizedDescription
        }
    }
}
