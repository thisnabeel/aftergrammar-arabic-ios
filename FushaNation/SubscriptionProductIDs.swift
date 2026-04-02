import Foundation

enum SubscriptionProductIDs {
    /// Auto-renewable subscription — create this ID in App Store Connect (Subscriptions) and attach to the app.
    static let premium = "com.nabeel.FushaNation.premium"

    static let all: [String] = [premium]
}
