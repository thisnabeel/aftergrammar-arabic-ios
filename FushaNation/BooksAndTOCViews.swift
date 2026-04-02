import SwiftUI
import UIKit

/// Secondary line under TOC titles; scales with content font but stays readable.
private func tocSubtitleFontSize(for contentPt: CGFloat) -> CGFloat {
    max(14, min(38, contentPt * 0.78))
}

struct BooksRootView: View {
    @State private var books: [ChapterNode] = []
    @State private var loadState: LoadState = .idle
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings

    private enum LoadState {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView("Loading…")
                    .tint(AppTheme.forestGreen)
            case .failed(let message):
                ContentUnavailableView(
                    "Couldn’t load books",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .loaded:
                if books.isEmpty {
                    ContentUnavailableView("No books", systemImage: "book.closed")
                } else {
                    List(books) { book in
                        NavigationLink {
                            ChapterTOCView(node: book)
                        } label: {
                            selectionRow(
                                title: book.title,
                                description: book.description,
                                tier: book.tier,
                                colorScheme: colorScheme,
                                titleFontSize: appSettings.contentFontSize,
                                subtitleFontSize: tocSubtitleFontSize(for: appSettings.contentFontSize)
                            )
                        }
                        .listRowBackground(listRowBackground)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .fushaBooksListSeparatorAppearance()
                }
            }
        }
        .fushaNavigationTitle(ancestors: [], title: "Fusha Nation")
        .environment(\.layoutDirection, .rightToLeft)
        .background(screenBackground)
        .task {
            await load()
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? Color.black : AppTheme.background
    }

    private var listRowBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : AppTheme.listRow
    }

    private func load() async {
        loadState = .loading
        do {
            let tree = try await ChapterAPI.fetchChapterTree()
            books = tree
                .filter { $0.chapterId == nil }
                .sorted { $0.position < $1.position }
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

struct ChapterTOCView: View {
    let node: ChapterNode
    /// Titles from the root book down through each nested TOC parent (excludes `node`).
    var ancestorTitles: [String] = []
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var paywallPresented = false

    private var children: [ChapterNode] {
        node.children.sorted { $0.position < $1.position }
    }

    var body: some View {
        Group {
            if children.isEmpty {
                ContentUnavailableView(
                    "No sections",
                    systemImage: "list.bullet",
                    description: Text("This book has no chapters yet.")
                )
            } else {
                List(children) { child in
                    Group {
                        if child.children.isEmpty {
                            if child.isPremiumTier && !subscriptionStore.isSubscribed {
                                Button {
                                    paywallPresented = true
                                } label: {
                                    selectionRow(
                                        title: child.title,
                                        description: child.description,
                                        tier: child.tier,
                                        colorScheme: colorScheme,
                                        titleFontSize: appSettings.contentFontSize,
                                        subtitleFontSize: tocSubtitleFontSize(for: appSettings.contentFontSize)
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    ChapterReaderView(
                                        chapterId: child.id,
                                        breadcrumbTitles: ancestorTitles + [node.title],
                                        listContextTitle: child.title
                                    )
                                } label: {
                                    selectionRow(
                                        title: child.title,
                                        description: child.description,
                                        tier: child.tier,
                                        colorScheme: colorScheme,
                                        titleFontSize: appSettings.contentFontSize,
                                        subtitleFontSize: tocSubtitleFontSize(for: appSettings.contentFontSize)
                                    )
                                }
                            }
                        } else {
                            NavigationLink {
                                ChapterTOCView(node: child, ancestorTitles: ancestorTitles + [node.title])
                            } label: {
                                selectionRow(
                                    title: child.title,
                                    description: child.description,
                                    tier: child.tier,
                                    colorScheme: colorScheme,
                                    titleFontSize: appSettings.contentFontSize,
                                    subtitleFontSize: tocSubtitleFontSize(for: appSettings.contentFontSize)
                                )
                            }
                        }
                    }
                    .listRowBackground(listRowBackground)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .fushaBooksListSeparatorAppearance()
            }
        }
        .fushaNavigationTitle(ancestors: ancestorTitles, title: node.title)
        .environment(\.layoutDirection, .rightToLeft)
        .background(screenBackground)
        .sheet(isPresented: $paywallPresented) {
            PaywallView()
                .environmentObject(subscriptionStore)
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? Color.black : AppTheme.background
    }

    private var listRowBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : AppTheme.listRow
    }
}

// Shared row for books list and every TOC level.
private func selectionRow(
    title: String,
    description: String?,
    tier: String?,
    colorScheme: ColorScheme,
    titleFontSize: CGFloat,
    subtitleFontSize: CGFloat
) -> some View {
    ZStack(alignment: .trailing) {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Spacer(minLength: 0)
                TierPill(tier: tier, colorScheme: colorScheme)
                Text(title)
                    .font(ArabicTypography.swiftUIFont(size: titleFontSize))
                    .foregroundStyle(colorScheme == .dark ? Color.white : AppTheme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
            }
            if let d = description, !d.isEmpty {
                Text(d)
                    .font(ArabicTypography.swiftUIFont(size: subtitleFontSize))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : AppTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .trailing)
    // NavigationLink/List can mirror container stacks under RTL; force physical-right pinning.
    .environment(\.layoutDirection, .leftToRight)
    // Default List separators align to label bounds; stretch to the row’s full width.
    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    .alignmentGuide(.listRowSeparatorTrailing) { d in d.width }
}

/// `List` + `NavigationLink` under RTL often shortens the system separator; pin separators to the full cell width.
private struct BooksListSeparatorAppearanceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                UITableView.appearance().separatorInset = .zero
                UITableView.appearance().separatorInsetReference = .fromCellEdges
            }
    }
}

private extension View {
    func fushaBooksListSeparatorAppearance() -> some View {
        modifier(BooksListSeparatorAppearanceModifier())
    }
}

private struct TierPill: View {
    let tier: String?
    let colorScheme: ColorScheme

    var body: some View {
        Group {
            if let style = TierStyle(rawTier: tier) {
                Text(style.label)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.3)
                    .textCase(.uppercase)
                    .foregroundStyle(style.foreground(colorScheme: colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(style.background(colorScheme: colorScheme))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(style.border(colorScheme: colorScheme), lineWidth: 1)
                    )
                    .clipShape(Capsule(style: .continuous))
            }
        }
    }

    private enum TierStyle {
        case premium
        case free

        init?(rawTier: String?) {
            guard let t = rawTier?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            switch t.lowercased() {
            case "premium": self = .premium
            case "free": self = .free
            default: return nil
            }
        }

        var label: String {
            switch self {
            case .premium: return "Premium"
            case .free: return "Free"
            }
        }

        func background(colorScheme: ColorScheme) -> Color {
            switch self {
            case .premium:
                return colorScheme == .dark
                    ? Color(red: 0.42, green: 0.32, blue: 0.12).opacity(0.55)
                    : Color(red: 0.98, green: 0.93, blue: 0.78)
            case .free:
                return colorScheme == .dark
                    ? Color(red: 0.15, green: 0.32, blue: 0.22).opacity(0.65)
                    : Color(red: 0.88, green: 0.96, blue: 0.91)
            }
        }

        func foreground(colorScheme: ColorScheme) -> Color {
            switch self {
            case .premium:
                return colorScheme == .dark ? Color(red: 1, green: 0.92, blue: 0.55) : Color(red: 0.45, green: 0.32, blue: 0.08)
            case .free:
                return colorScheme == .dark ? Color(red: 0.75, green: 0.92, blue: 0.78) : Color(red: 0.05, green: 0.38, blue: 0.22)
            }
        }

        func border(colorScheme: ColorScheme) -> Color {
            switch self {
            case .premium:
                return colorScheme == .dark ? Color.white.opacity(0.14) : Color(red: 0.75, green: 0.58, blue: 0.2).opacity(0.35)
            case .free:
                return colorScheme == .dark ? Color.white.opacity(0.12) : Color(red: 0.2, green: 0.55, blue: 0.35).opacity(0.25)
            }
        }
    }
}
