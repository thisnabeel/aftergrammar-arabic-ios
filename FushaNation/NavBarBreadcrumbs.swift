import SwiftUI
import UIKit

// MARK: - Content font bar dismiss (tap chapter body to finish adjusting size)

private struct ContentFontBarDismissKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// When non-nil, chapter body may call this on tap to dismiss the top font-size bar.
    var contentFontBarDismiss: (() -> Void)? {
        get { self[ContentFontBarDismissKey.self] }
        set { self[ContentFontBarDismissKey.self] = newValue }
    }
}

/// Compact two-line nav bar title: optional ancestor trail + current title (RTL-friendly).
struct NavBarBreadcrumbTitle: View {
    let ancestors: [String]
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    private var trail: String {
        ancestors.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " › ")
    }

    var body: some View {
        VStack(spacing: 2) {
            // Keep a stable title stack height to avoid nav-bar jitter when moving
            // between levels with/without breadcrumbs.
            Text(trail.isEmpty ? " " : trail)
                .font(ArabicTypography.swiftUIFont(size: 13).weight(.semibold))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.7) : AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(trail.isEmpty ? 0 : 1)
            Text(title.isEmpty ? " " : title)
                .font(ArabicTypography.swiftUIFont(size: 28).weight(.bold))
                .foregroundStyle(colorScheme == .dark ? Color.white : AppTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
    }
}

private struct ConditionalBreadcrumbNavModifier: ViewModifier {
    let ancestors: [String]
    let title: String
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSettingsOpen = false
    @State private var isContentFontBarVisible = false

    func body(content: Content) -> some View {
        content
            // Keep a native title available so a label appears immediately
            // while the principal toolbar title view lays out.
            .navigationTitle(title.isEmpty ? " " : title)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.contentFontBarDismiss, contentFontBarDismissAction)
            .safeAreaInset(edge: .top, spacing: 0) {
                if isContentFontBarVisible {
                    ContentFontSizeTopBar(appSettings: appSettings, onDone: dismissContentFontBar)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.9), value: isContentFontBarVisible)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavBarBreadcrumbTitle(ancestors: ancestors, title: title)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                            isSettingsOpen = true
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? Color.white : AppTheme.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.85))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
            }
            .toolbarBackground(navBarBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .overlay(alignment: .top) {
                // Subtle bottom divider under the nav bar area (feels more “finished”).
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
            .overlay {
                if isSettingsOpen {
                    // TOC / books use RTL; without LTR here, `.trailing` becomes the physical left and the sheet opens on the wrong side.
                    ZStack(alignment: .trailing) {
                        Color.black.opacity(colorScheme == .dark ? 0.32 : 0.12)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
                                    isSettingsOpen = false
                                }
                            }

                        ReaderSettingsPanel(onClose: {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
                                isSettingsOpen = false
                            }
                        }, onOpenFontSize: {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
                                isSettingsOpen = false
                                isContentFontBarVisible = true
                            }
                        })
                        .frame(width: 320)
                        .frame(maxWidth: min(UIScreen.main.bounds.width * 0.86, 360), alignment: .trailing)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .animation(.spring(response: 0.26, dampingFraction: 0.9), value: isSettingsOpen)
                    .zIndex(1000)
                }
            }
    }

    private var contentFontBarDismissAction: (() -> Void)? {
        isContentFontBarVisible
            ? { dismissContentFontBar() }
            : nil
    }

    private func dismissContentFontBar() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
            isContentFontBarVisible = false
        }
    }

    private var navBarBackground: Color {
        colorScheme == .dark ? Color(white: 0.10) : AppTheme.bannerPink.opacity(0.92)
    }
}

private struct ReaderSettingsPanel: View {
    let onClose: () -> Void
    let onOpenFontSize: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? Color.white : AppTheme.textPrimary)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? Color.white : AppTheme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Button {
                onOpenFontSize()
            } label: {
                Text("Change font size…")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.white : AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(colorScheme == .dark ? Color(white: 0.14) : AppTheme.bannerPink.opacity(0.98))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                .frame(width: 1)
        }
        // Panel is anchored to the physical right (LTR overlay); shadow falls left onto the dimmed content.
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 10, x: -4, y: 0)
    }
}

private struct ContentFontSizeTopBar: View {
    @ObservedObject var appSettings: AppSettings
    let onDone: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// Slider uses local state so the thumb stays fluid; chapter text updates are throttled to avoid heavy HTML/layout churn.
    @State private var draftFontSize: CGFloat = 30
    @State private var throttleTask: Task<Void, Never>?
    @State private var lastCommittedAt: CFAbsoluteTime = 0

    /// Minimum time between applying size to `AppSettings` (limits attributed-text rebuilds per second).
    private static let applyThrottleSeconds: Double = 0.11

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text("A")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.85) : AppTheme.textSecondary)

                Slider(
                    value: $draftFontSize,
                    in: appSettings.contentFontRange,
                    step: 1
                )
                .tint(AppTheme.forestGreen)

                Text("A")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.85) : AppTheme.textSecondary)

                Button {
                    flushFontSizeToAppSettings()
                    onDone()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.forestGreen)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save and close font size")
            }

            Text("\(Int(draftFontSize)) pt")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.75) : AppTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Rectangle()
                    .fill(colorScheme == .dark ? Color(white: 0.11) : AppTheme.bannerPink.opacity(0.96))
                Rectangle()
                    .fill(colorScheme == .dark ? Color.black.opacity(0.2) : Color.white.opacity(0.08))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                .frame(height: 1)
        }
        // Books/TOC use RTL; chapter content uses RTL but this inset follows system LTR. Force LTR so the
        // slider (small A → large A, fill growing left-to-right) matches the chapter reader everywhere.
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            draftFontSize = appSettings.contentFontSize
            lastCommittedAt = CFAbsoluteTimeGetCurrent()
        }
        .onChange(of: draftFontSize) { _, _ in
            scheduleThrottledApplyToAppSettings()
        }
        .onDisappear {
            flushFontSizeToAppSettings()
        }
    }

    private func scheduleThrottledApplyToAppSettings() {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastCommittedAt >= Self.applyThrottleSeconds {
            lastCommittedAt = now
            appSettings.contentFontSize = draftFontSize
            throttleTask?.cancel()
            throttleTask = nil
            return
        }
        throttleTask?.cancel()
        throttleTask = Task { @MainActor in
            let elapsed = CFAbsoluteTimeGetCurrent() - lastCommittedAt
            let wait = max(0, Self.applyThrottleSeconds - elapsed)
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            lastCommittedAt = CFAbsoluteTimeGetCurrent()
            appSettings.contentFontSize = draftFontSize
        }
    }

    private func flushFontSizeToAppSettings() {
        throttleTask?.cancel()
        throttleTask = nil
        appSettings.contentFontSize = draftFontSize
    }
}

extension View {
    /// Standard inline nav title; when `ancestors` is non-empty, shows a breadcrumb trail above the title.
    func fushaNavigationTitle(ancestors: [String], title: String) -> some View {
        modifier(ConditionalBreadcrumbNavModifier(ancestors: ancestors, title: title))
    }
}
