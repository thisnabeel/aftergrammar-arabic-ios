import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    @Published var contentFontSize: CGFloat = 30

    let contentFontRange: ClosedRange<CGFloat> = 24 ... 72
}
