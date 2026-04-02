import SwiftUI
import UIKit

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

    func body(content: Content) -> some View {
        content
            // Keep a native title available so a label appears immediately
            // while the principal toolbar title view lays out.
            .navigationTitle(title.isEmpty ? " " : title)
            .navigationBarTitleDisplayMode(.inline)
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
                    ZStack(alignment: .trailing) {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
                                    isSettingsOpen = false
                                }
                            }

                        ReaderSettingsPanel(appSettings: appSettings, onClose: {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
                                isSettingsOpen = false
                            }
                        })
                        .frame(width: 320)
                        .frame(maxWidth: min(UIScreen.main.bounds.width * 0.86, 360), alignment: .trailing)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    .animation(.spring(response: 0.26, dampingFraction: 0.9), value: isSettingsOpen)
                    .zIndex(1000)
                }
            }
    }

    private var navBarBackground: Color {
        colorScheme == .dark ? Color(white: 0.10) : AppTheme.bannerPink.opacity(0.92)
    }
}

private struct ReaderSettingsPanel: View {
    @ObservedObject var appSettings: AppSettings
    let onClose: () -> Void
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
                        .background(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Content Font Size")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.white : AppTheme.textPrimary)

                HStack(spacing: 12) {
                    Text("A")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : AppTheme.textSecondary)

                    Slider(
                        value: $appSettings.contentFontSize,
                        in: appSettings.contentFontRange,
                        step: 1
                    )

                    Text("A")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : AppTheme.textSecondary)
                }

                Text("\(Int(appSettings.contentFontSize)) pt")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : AppTheme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(colorScheme == .dark ? Color(white: 0.12) : AppTheme.bannerPink.opacity(0.98))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                .frame(width: 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 10, x: -2, y: 0)
    }
}

extension View {
    /// Standard inline nav title; when `ancestors` is non-empty, shows a breadcrumb trail above the title.
    func fushaNavigationTitle(ancestors: [String], title: String) -> some View {
        modifier(ConditionalBreadcrumbNavModifier(ancestors: ancestors, title: title))
    }
}
