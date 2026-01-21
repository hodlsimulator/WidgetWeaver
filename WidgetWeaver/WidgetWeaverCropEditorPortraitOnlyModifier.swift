//
//  WidgetWeaverCropEditorPortraitOnlyModifier.swift
//  WidgetWeaver
//
//  Created by . . on 1/21/26.
//

import SwiftUI
import UIKit

struct WidgetWeaverCropEditorPortraitOnlyModifier: ViewModifier {
    @State private var isLocked: Bool = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !isLocked else { return }
                isLocked = true

                Task { @MainActor in
                    WidgetWeaverInterfaceOrientationLock.lockToPortrait()
                }
            }
            .onDisappear {
                guard isLocked else { return }
                isLocked = false

                Task { @MainActor in
                    WidgetWeaverInterfaceOrientationLock.restoreDefault()
                }
            }
    }
}

@MainActor
enum WidgetWeaverInterfaceOrientationLock {
    static func lockToPortrait() {
        apply(.portrait)
    }

    static func restoreDefault() {
        apply(defaultSupportedMask())
    }

    private static func apply(_ mask: UIInterfaceOrientationMask) {
        guard let scene = activeWindowScene() else { return }

        if #available(iOS 16.0, *) {
            let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
            scene.requestGeometryUpdate(preferences) { _ in }
        }

        scene.windows.first(where: { $0.isKeyWindow })?
            .rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()

        if #unavailable(iOS 16.0) {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return active
        }

        return scenes.first
    }

    private static func defaultSupportedMask() -> UIInterfaceOrientationMask {
        let key: String = {
            if UIDevice.current.userInterfaceIdiom == .pad {
                return "UISupportedInterfaceOrientations~ipad"
            }
            return "UISupportedInterfaceOrientations"
        }()

        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? [String])
            ?? (Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations") as? [String])
            ?? []

        var mask: UIInterfaceOrientationMask = []

        for value in raw {
            switch value {
            case "UIInterfaceOrientationPortrait":
                mask.insert(.portrait)
            case "UIInterfaceOrientationPortraitUpsideDown":
                mask.insert(.portraitUpsideDown)
            case "UIInterfaceOrientationLandscapeLeft":
                mask.insert(.landscapeLeft)
            case "UIInterfaceOrientationLandscapeRight":
                mask.insert(.landscapeRight)
            default:
                break
            }
        }

        return mask.isEmpty ? .allButUpsideDown : mask
    }
}
