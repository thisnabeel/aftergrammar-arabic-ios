//
//  FushaNationApp.swift
//  FushaNation
//
//  Created by Nabeel Khan on 3/23/26.
//

import SwiftUI
import UIKit

@main
struct FushaNationApp: App {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var subscriptionStore = SubscriptionStore()

    init() {
        ArabicTypography.ensureRegistered()

        let softRose = UIColor(red: 248 / 255, green: 230 / 255, blue: 235 / 255, alpha: 1)
        let titleColor = UIColor(white: 0.12, alpha: 1)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = softRose
        appearance.shadowColor = UIColor(white: 0, alpha: 0.06)
        appearance.titleTextAttributes = [.foregroundColor: titleColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: titleColor]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = appearance
        navBar.compactAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.tintColor = UIColor(white: 0.2, alpha: 1)

        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ContentView()
            }
            .tint(AppTheme.accentBlue)
            .environmentObject(appSettings)
            .environmentObject(subscriptionStore)
        }
    }
}
