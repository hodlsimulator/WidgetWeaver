//
//  WidgetPreviewDock.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI
import WidgetKit
import UIKit

// MARK: - Preview Dock (collapsible)

struct WidgetPreviewDock: View {
    enum Presentation { case dock, sidebar }

    static func reservedInsetHeight(verticalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        collapsedCardHeight(verticalSizeClass: verticalSizeClass) + outerBottomPadding
    }

    private static let outerBottomPadding: CGFloat = 10

    private static func collapsedCardHeight(verticalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        (verticalSizeClass == .compact) ? 62 : 72
    }

    let spec: WidgetSpec
    @Binding var family: WidgetFamily
    let presentation: Presentation

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @SceneStorage("widgetPreviewDock.isExpanded") private var isExpanded: Bool = false

    var body: some View {
        switch presentation {
        case .sidebar: expandedCard
        case .dock: dockCard
        }
    }

    private var dockCard: some View {
        ZStack {
            if isExpanded {
                expandedCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                collapsedCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: isExpanded)
        .gesture(dragGesture)
        .onChange(of: verticalSizeClass) { _, newValue in
            guard presentation == .dock else { return }
            if newValue == .compact { setExpanded(false) }
        }
    }

    private var expandedCard: some View {
        VStack(spacing: 12) {

            if presentation == .dock {
                grabber
                    .padding(.top, 2)
                    .padding(.bottom, 2)
            }

            HStack(spacing: 10) {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Picker("Size", selection: $family) {
                    Text("Small").tag(WidgetFamily.systemSmall)
                    Text("Medium").tag(WidgetFamily.systemMedium)
                    Text("Large").tag(WidgetFamily.systemLarge)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: presentation == .sidebar ? 280 : 240)

                if presentation == .dock {
                    Button { setExpanded(false) } label: {
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Collapse preview")
                }
            }

            WidgetPreview(spec: spec, family: family, maxHeight: expandedPreviewMaxHeight)

            Text("Preview is approximate; final widget size is device-dependent.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.regularMaterial, in: cardShape)
        .overlay(cardShape.strokeBorder(.primary.opacity(0.10)))
        .shadow(color: .black.opacity(presentation == .dock ? 0.10 : 0.06), radius: 18, y: 8)
    }

    private var collapsedCard: some View {
        HStack(spacing: 12) {
            WidgetPreviewThumbnail(spec: spec, family: family, height: collapsedThumbnailHeight)

            VStack(alignment: .leading, spacing: 2) {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(familyLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            familyMenu

            Image(systemName: "chevron.up")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: collapsedHeight)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: cardShape)
        .overlay(cardShape.strokeBorder(.primary.opacity(0.10)))
        .contentShape(cardShape)
        .onTapGesture { setExpanded(true) }
    }

    private var grabber: some View {
        Capsule()
            .fill(.secondary.opacity(0.35))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { toggleExpanded() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isExpanded ? "Collapse preview" : "Expand preview")
    }

    private var familyMenu: some View {
        Menu {
            Button { family = .systemSmall } label: { Label("Small", systemImage: "square") }
            Button { family = .systemMedium } label: { Label("Medium", systemImage: "rectangle") }
            Button { family = .systemLarge } label: { Label("Large", systemImage: "rectangle.portrait") }
        } label: {
            Text(familyAbbreviation)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onEnded { value in
                let dy = value.translation.height
                if dy > 24 {
                    setExpanded(false)
                } else if dy < -24 {
                    setExpanded(true)
                }
            }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var collapsedHeight: CGFloat {
        Self.collapsedCardHeight(verticalSizeClass: verticalSizeClass)
    }

    private var collapsedThumbnailHeight: CGFloat {
        (verticalSizeClass == .compact) ? 30 : 38
    }

    private var expandedPreviewMaxHeight: CGFloat {
        switch presentation {
        case .sidebar:
            return 420
        case .dock:
            return (verticalSizeClass == .compact) ? 150 : 260
        }
    }

    private var familyLabel: String {
        switch family {
        case .systemSmall: return "Small"
        case .systemMedium: return "Medium"
        case .systemLarge: return "Large"
        default: return "Small"
        }
    }

    private var familyAbbreviation: String {
        switch family {
        case .systemSmall: return "S"
        case .systemMedium: return "M"
        case .systemLarge: return "L"
        default: return "S"
        }
    }

    private func toggleExpanded() {
        setExpanded(!isExpanded)
    }

    private func setExpanded(_ expanded: Bool) {
        guard presentation == .dock else { return }
        withAnimation(.snappy(duration: 0.25)) {
            isExpanded = expanded
        }
    }
}

@MainActor
struct WidgetPreview: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    var maxHeight: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let base = Self.widgetSize(for: family)
            let scaleX = proxy.size.width / base.width
            let scaleY = proxy.size.height / base.height
            let scale = min(scaleX, scaleY)

            WidgetWeaverSpecView(spec: spec, family: family, context: .preview)
                .frame(width: base.width, height: base.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(height: maxHeight)
        .clipped()
    }

    static func widgetSize(for family: WidgetFamily) -> CGSize {
        let sizes = WidgetPreviewSizing.sizesForCurrentDevice()
        switch family {
        case .systemSmall: return sizes.small
        case .systemMedium: return sizes.medium
        case .systemLarge: return sizes.large
        default: return sizes.small
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
                .first(where: { $0.activationState == .foregroundActive }) {
                return activeScene.screen
            }

            if let anyScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first {
                return anyScene.screen
            }

            return UIScreen()
        }

        private static let knownSizesByNativeResolution: [String: Sizes] = [
            // MARK: - iPhone
            "1170x2532": Sizes(small: CGSize(width: 158, height: 158), medium: CGSize(width: 338, height: 158), large: CGSize(width: 338, height: 354)), // 12/13/14/15 (non‑Pro 6.1")
            "1179x2556": Sizes(small: CGSize(width: 158, height: 158), medium: CGSize(width: 338, height: 158), large: CGSize(width: 338, height: 354)), // 14/15 Pro (6.1")
            "1080x2340": Sizes(small: CGSize(width: 155, height: 155), medium: CGSize(width: 329, height: 155), large: CGSize(width: 329, height: 345)), // 12/13 mini
            "1284x2778": Sizes(small: CGSize(width: 170, height: 170), medium: CGSize(width: 364, height: 170), large: CGSize(width: 364, height: 382)), // 12/13 Pro Max
            "1290x2796": Sizes(small: CGSize(width: 170, height: 170), medium: CGSize(width: 364, height: 170), large: CGSize(width: 364, height: 382)), // 14/15 Pro Max
            "828x1792": Sizes(small: CGSize(width: 169, height: 169), medium: CGSize(width: 360, height: 169), large: CGSize(width: 360, height: 379)), // XR / 11
            "1125x2436": Sizes(small: CGSize(width: 155, height: 155), medium: CGSize(width: 329, height: 155), large: CGSize(width: 329, height: 345)), // X / XS / 11 Pro
            "1242x2688": Sizes(small: CGSize(width: 169, height: 169), medium: CGSize(width: 360, height: 169), large: CGSize(width: 360, height: 379)), // XS Max / 11 Pro Max
            "750x1334": Sizes(small: CGSize(width: 148, height: 148), medium: CGSize(width: 321, height: 148), large: CGSize(width: 321, height: 324)), // 6/7/8/SE2/SE3
            "1080x1920": Sizes(small: CGSize(width: 157, height: 157), medium: CGSize(width: 348, height: 157), large: CGSize(width: 348, height: 351)), // Plus
            "640x1136": Sizes(small: CGSize(width: 141, height: 141), medium: CGSize(width: 292, height: 141), large: CGSize(width: 292, height: 311)), // SE 1st gen

            // MARK: - iPad
            "2732x2048": Sizes(small: CGSize(width: 170, height: 170), medium: CGSize(width: 379, height: 170), large: CGSize(width: 379, height: 379)), // 12.9" iPad Pro
            "2388x1668": Sizes(small: CGSize(width: 155, height: 155), medium: CGSize(width: 342, height: 155), large: CGSize(width: 342, height: 342)), // 11" iPad Pro
            "2360x1640": Sizes(small: CGSize(width: 155, height: 155), medium: CGSize(width: 342, height: 155), large: CGSize(width: 342, height: 342)), // iPad Air 4/5
            "2266x1488": Sizes(small: CGSize(width: 141, height: 141), medium: CGSize(width: 306, height: 141), large: CGSize(width: 306, height: 306)), // iPad mini 6
            "2224x1668": Sizes(small: CGSize(width: 150, height: 150), medium: CGSize(width: 328, height: 150), large: CGSize(width: 328, height: 328)), // iPad Pro 10.5"
            "2160x1620": Sizes(small: CGSize(width: 146, height: 146), medium: CGSize(width: 321, height: 146), large: CGSize(width: 321, height: 321)), // iPad 7/8/9
            "2048x1536": Sizes(small: CGSize(width: 141, height: 141), medium: CGSize(width: 306, height: 141), large: CGSize(width: 306, height: 306))  // older iPads bucket
        ]
    }
}

@MainActor
struct WidgetPreviewThumbnail: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    var height: CGFloat

    var body: some View {
        let base = WidgetPreview.widgetSize(for: family)
        let scale = height / base.height
        let scaledWidth = base.width * scale

        WidgetWeaverSpecView(spec: spec, family: family, context: .preview)
            .frame(width: base.width, height: base.height)
            .scaleEffect(scale, anchor: .center)
            .frame(width: scaledWidth, height: height, alignment: .center)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10))
            )
            .clipped()
    }
}
