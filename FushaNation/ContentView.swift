//
//  ContentView.swift
//  FushaNation
//
//  Created by Nabeel Khan on 3/23/26.
//

import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        NavigationStack {
            BooksRootView()
                .background(NavigationInteractivePopDisabler())
        }
    }
}

/// Disables edge swipe-to-go-back app-wide. `NavigationStack` must host this inside the stack so UIKit can find the nav controller; also walks the key window to re-apply after pushes.
private struct NavigationInteractivePopDisabler: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        context.coordinator.apply()
        context.coordinator.startObservingNavShow()
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.apply()
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopObserving()
        coordinator.restore()
    }

    final class Coordinator: NSObject {
        private var observer: NSObjectProtocol?
        private let trackedNavControllers = NSHashTable<UINavigationController>.weakObjects()
        private let trackedEdgePans = NSHashTable<UIScreenEdgePanGestureRecognizer>.weakObjects()
        private var originalEdgePanEnabledState: [ObjectIdentifier: Bool] = [:]

        func startObservingNavShow() {
            guard observer == nil else { return }
            let name = Notification.Name("UINavigationControllerDidShowViewControllerNotification")
            observer = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.apply()
            }
        }

        func stopObserving() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
        }

        func apply() {
            let navControllers = Self.resolveNavigationControllers()
            for nav in navControllers {
                nav.interactivePopGestureRecognizer?.isEnabled = false
                if nav.interactivePopGestureRecognizer?.delegate !== self {
                    nav.interactivePopGestureRecognizer?.delegate = self
                }
                trackedNavControllers.add(nav)

                // Extra hard block: disable all left-edge pans attached to this nav stack.
                for edgePan in Self.leftEdgePans(in: nav) {
                    let oid = ObjectIdentifier(edgePan)
                    if originalEdgePanEnabledState[oid] == nil {
                        originalEdgePanEnabledState[oid] = edgePan.isEnabled
                    }
                    edgePan.isEnabled = false
                    trackedEdgePans.add(edgePan)
                }
            }
        }

        func restore() {
            for nav in trackedNavControllers.allObjects {
                if nav.interactivePopGestureRecognizer?.delegate === self {
                    nav.interactivePopGestureRecognizer?.delegate = nil
                }
                nav.interactivePopGestureRecognizer?.isEnabled = true
            }
            for edgePan in trackedEdgePans.allObjects {
                let oid = ObjectIdentifier(edgePan)
                edgePan.isEnabled = originalEdgePanEnabledState[oid] ?? true
            }
            originalEdgePanEnabledState.removeAll()
            trackedEdgePans.removeAllObjects()
            trackedNavControllers.removeAllObjects()
        }

        private static func resolveNavigationControllers() -> [UINavigationController] {
            var collected: [UINavigationController] = []
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    guard let root = window.rootViewController else { continue }
                    collectNavigationControllers(in: root, into: &collected)
                }
            }
            // Remove duplicates while preserving order.
            var seen = Set<ObjectIdentifier>()
            return collected.filter { nav in
                let oid = ObjectIdentifier(nav)
                let inserted = seen.insert(oid).inserted
                return inserted
            }
        }

        private static func collectNavigationControllers(in vc: UIViewController, into out: inout [UINavigationController]) {
            if let nav = vc as? UINavigationController {
                out.append(nav)
            }
            for child in vc.children {
                collectNavigationControllers(in: child, into: &out)
            }
            if let presented = vc.presentedViewController {
                collectNavigationControllers(in: presented, into: &out)
            }
            var parent = vc.parent
            while let p = parent {
                if let nav = p as? UINavigationController {
                    out.append(nav)
                }
                if let nav = p.navigationController {
                    out.append(nav)
                }
                parent = p.parent
            }
        }

        private static func leftEdgePans(in nav: UINavigationController) -> [UIScreenEdgePanGestureRecognizer] {
            let candidates = (nav.view.gestureRecognizers ?? []) + (nav.interactivePopGestureRecognizer.map { [$0] } ?? [])
            return candidates.compactMap { $0 as? UIScreenEdgePanGestureRecognizer }
                .filter { $0.edges.contains(.left) }
        }
    }
}

extension NavigationInteractivePopDisabler.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .environmentObject(SubscriptionStore())
}
