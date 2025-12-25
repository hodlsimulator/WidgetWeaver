//
//  WidgetPreview.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Split out of WidgetPreviewDock.swift on 12/23/25.
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit

// MARK: - Live Preview
@MainActor
struct WidgetPreview: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    var maxHeight: CGFloat?
    var isLive: Bool = false

    // Forces a re-render when variables change in-app (including via AppIntent buttons).
    @AppStorage("widgetweaver.variables.v1", store: AppGroup.userDefaults)
    private var variablesData: Data = Data()

    var body: some View {
        let _ = variablesData

        let isTimeDependent = spec.normalised().usesTimeDependentRendering()

        Group {
            if isTimeDependent {
                // Preview mode should still advance time so Medium/Large never drift apart.
                let interval: TimeInterval = isLive ? 1 : 60
                TimelineView(.periodic(from: Date(), by: interval)) { _ in
                    previewBody
                }
            } else {
                previewBody
            }
        }
        .frame(height: maxHeight)
        .contentShape(Rectangle())
        .clipped()
    }

    private static func sizingReferenceFamily(for family: WidgetFamily) -> WidgetFamily {
        switch family {
        case .systemSmall, .systemMedium:
            return .systemMedium
        case .systemLarge:
            return .systemLarge
        default:
            return .systemMedium
        }
    }

    private var previewBody: some View {
        GeometryReader { proxy in
            let base = Self.widgetSize(for: family)

            // Small and Medium occupy the same Home Screen row height.
            // Scaling both against the Medium base keeps the preview height stable between S/M.
            let sizingBase = Self.widgetSize(for: Self.sizingReferenceFamily(for: family))

            let scaleX = proxy.size.width / sizingBase.width
            let scaleY = proxy.size.height / sizingBase.height
            let scale = min(scaleX, scaleY)

            WidgetWeaverSpecView(
                spec: spec,
                family: family,
                context: isLive ? .simulator : .preview
            )
            .frame(width: base.width, height: base.height)
            .scaleEffect(scale, anchor: .center)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }

    static func widgetSize(for family: WidgetFamily) -> CGSize {
        let sizes = WidgetPreviewSizing.sizesForCurrentDevice()
        switch family {
        case .systemSmall:
            return sizes.small
        case .systemMedium:
            return sizes.medium
        case .systemLarge:
            return sizes.large
        default:
            return sizes.small
        }
    }

    private struct WidgetPreviewSizing {
        struct Sizes {
            let small: CGSize
            let medium: CGSize
            let large: CGSize
        }

        @MainActor
        static func sizesForCurrentDevice() -> Sizes {
            let screen = currentScreen()
            let native = screen.nativeBounds.size

            let w = Int(min(native.width, native.height))
            let h = Int(max(native.width, native.height))
            let key = "\(w)x\(h)"

            if let sizes = knownSizesByNativeResolution[key] {
                return sizes
            }

            let points = screen.bounds.size
            let maxSide = max(points.width, points.height)
            let minSide = min(points.width, points.height)

            if UIDevice.current.userInterfaceIdiom == .pad {
                if minSide >= 1024 || maxSide >= 1366 {
                    return Sizes(
                        small: CGSize(width: 170, height: 170),
                        medium: CGSize(width: 379, height: 170),
                        large: CGSize(width: 379, height: 379)
                    )
                } else {
                    return Sizes(
                        small: CGSize(width: 155, height: 155),
                        medium: CGSize(width: 342, height: 155),
                        large: CGSize(width: 342, height: 342)
                    )
                }
            }

            if maxSide >= 926 {
                return Sizes(
                    small: CGSize(width: 170, height: 170),
                    medium: CGSize(width: 364, height: 170),
                    large: CGSize(width: 364, height: 382)
                )
            } else if maxSide >= 844 {
                return Sizes(
                    small: CGSize(width: 158, height: 158),
                    medium: CGSize(width: 338, height: 158),
                    large: CGSize(width: 338, height: 354)
                )
            } else if maxSide >= 812 {
                return Sizes(
                    small: CGSize(width: 155, height: 155),
                    medium: CGSize(width: 329, height: 155),
                    large: CGSize(width: 329, height: 345)
                )
            } else if maxSide >= 736 {
                return Sizes(
                    small: CGSize(width: 157, height: 157),
                    medium: CGSize(width: 348, height: 157),
                    large: CGSize(width: 348, height: 351)
                )
            } else if maxSide >= 667 {
                return Sizes(
                    small: CGSize(width: 148, height: 148),
                    medium: CGSize(width: 321, height: 148),
                    large: CGSize(width: 321, height: 324)
                )
            } else {
                return Sizes(
                    small: CGSize(width: 141, height: 141),
                    medium: CGSize(width: 292, height: 141),
                    large: CGSize(width: 292, height: 311)
                )
            }
        }

        @MainActor
        private static func currentScreen() -> UIScreen {
            if let activeScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
            {
                return activeScene.screen
            }

            if let anyScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
            {
                return anyScene.screen
            }

            return UIScreen()
        }

        private static let knownSizesByNativeResolution: [String: Sizes] = [
            // MARK: - iPhone
            "1170x2532": Sizes( // 12/13/14/15 (non-Pro 6.1")
                small: CGSize(width: 158, height: 158),
                medium: CGSize(width: 338, height: 158),
                large: CGSize(width: 338, height: 354)
            ),
            "1179x2556": Sizes( // 14/15 Pro (6.1")
                small: CGSize(width: 158, height: 158),
                medium: CGSize(width: 338, height: 158),
                large: CGSize(width: 338, height: 354)
            ),
            "1080x2340": Sizes( // 12/13 mini
                small: CGSize(width: 155, height: 155),
                medium: CGSize(width: 329, height: 155),
                large: CGSize(width: 329, height: 345)
            ),
            "1284x2778": Sizes( // 12/13 Pro Max
                small: CGSize(width: 170, height: 170),
                medium: CGSize(width: 364, height: 170),
                large: CGSize(width: 364, height: 382)
            ),
            "1290x2796": Sizes( // 14/15 Pro Max
                small: CGSize(width: 170, height: 170),
                medium: CGSize(width: 364, height: 170),
                large: CGSize(width: 364, height: 382)
            ),
            "828x1792": Sizes( // XR / 11
                small: CGSize(width: 169, height: 169),
                medium: CGSize(width: 360, height: 169),
                large: CGSize(width: 360, height: 379)
            ),
            "1125x2436": Sizes( // X / XS / 11 Pro
                small: CGSize(width: 155, height: 155),
                medium: CGSize(width: 329, height: 155),
                large: CGSize(width: 329, height: 345)
            ),
            "1242x2688": Sizes( // XS Max / 11 Pro Max
                small: CGSize(width: 169, height: 169),
                medium: CGSize(width: 360, height: 169),
                large: CGSize(width: 360, height: 379)
            ),
            "750x1334": Sizes( // 6/7/8/SE2/SE3
                small: CGSize(width: 148, height: 148),
                medium: CGSize(width: 321, height: 148),
                large: CGSize(width: 321, height: 324)
            ),
            "1080x1920": Sizes( // Plus
                small: CGSize(width: 157, height: 157),
                medium: CGSize(width: 348, height: 157),
                large: CGSize(width: 348, height: 351)
            ),
            "640x1136": Sizes( // SE 1st gen
                small: CGSize(width: 141, height: 141),
                medium: CGSize(width: 292, height: 141),
                large: CGSize(width: 292, height: 311)
            ),

            // MARK: - iPad
            "2732x2048": Sizes( // 12.9" iPad Pro
                small: CGSize(width: 170, height: 170),
                medium: CGSize(width: 379, height: 170),
                large: CGSize(width: 379, height: 379)
            ),
            "2388x1668": Sizes( // 11" iPad Pro
                small: CGSize(width: 155, height: 155),
                medium: CGSize(width: 342, height: 155),
                large: CGSize(width: 342, height: 342)
            ),
            "2360x1640": Sizes( // iPad Air 4/5
                small: CGSize(width: 155, height: 155),
                medium: CGSize(width: 342, height: 155),
                large: CGSize(width: 342, height: 342)
            ),
            "2266x1488": Sizes( // iPad mini 6
                small: CGSize(width: 141, height: 141),
                medium: CGSize(width: 306, height: 141),
                large: CGSize(width: 306, height: 306)
            ),
            "2224x1668": Sizes( // older iPad bucket
                small: CGSize(width: 150, height: 150),
                medium: CGSize(width: 328, height: 150),
                large: CGSize(width: 328, height: 328)
            ),
            "2160x1620": Sizes( // iPad Pro 10.5"
                small: CGSize(width: 146, height: 146),
                medium: CGSize(width: 321, height: 146),
                large: CGSize(width: 321, height: 321)
            ),
            "2048x1536": Sizes( // iPad 7/8/9
                small: CGSize(width: 141, height: 141),
                medium: CGSize(width: 306, height: 141),
                large: CGSize(width: 306, height: 306)
            )
        ]
    }
}
