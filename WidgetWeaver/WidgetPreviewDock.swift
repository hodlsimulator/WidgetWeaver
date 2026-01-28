//
//  WidgetPreviewDock.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit

// MARK: - Preview Dock (collapsible)

struct WidgetPreviewDock: View {
    enum Presentation {
        case dock
        case sidebar
    }

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

    @Environment(\.colorScheme) private var colorScheme

    @SceneStorage("widgetPreviewDock.isExpanded") private var isExpanded: Bool = false

    @AppStorage("preview.liveEnabled") private var liveEnabled: Bool = true

    @State private var displayedSpec: WidgetSpec? = nil
    @State private var frozenSpec: WidgetSpec? = nil
    @State private var pendingTask: Task<Void, Never>? = nil

    private var isDirty: Bool {
        guard let saved = WidgetSpecStore.shared.load(id: spec.id) else { return false }
        return comparableSpec(spec) != comparableSpec(saved)
    }

    private func comparableSpec(_ spec: WidgetSpec) -> WidgetSpec {
        var s = spec.normalised()
        s.updatedAt = Date(timeIntervalSince1970: 0)
        return s
    }


    private var restrictToSmallOnly: Bool {
        let familySpec = spec.resolved(for: family)
        return familySpec.layout.template == .clockIcon
    }

    private var allowedFamilies: [WidgetFamily] {
        if restrictToSmallOnly {
            return [.systemSmall]
        }
        return [.systemSmall, .systemMedium, .systemLarge]
    }

    var body: some View {
        Group {
            switch presentation {
            case .sidebar:
                expandedCard
            case .dock:
                dockCard
            }
        }
        .onAppear {
            ensureSpecStateInitialised()
            clampFamilyIfNeeded()
        }
        .onChange(of: spec) { _, newValue in
            handleIncomingSpecChange(newValue)
        }
        .onChange(of: family) { _, _ in
            clampFamilyIfNeeded()
        }
        .onChange(of: liveEnabled) { _, newValue in
            handleLiveToggleChange(newValue)
        }
        .onDisappear {
            pendingTask?.cancel()
            pendingTask = nil
        }
    }

    private var effectiveSpec: WidgetSpec {
        if liveEnabled {
            return displayedSpec ?? spec
        }
        return frozenSpec ?? displayedSpec ?? spec
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
            if newValue == .compact {
                setExpanded(false)
            }
        }
    }

    private var expandedCard: some View {
        expandedPreviewSurface(
            VStack(spacing: 12) {
                if presentation == .dock {
                    grabber
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                }

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if isDirty {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(isDirty ? "Preview, unsaved changes" : "Preview")

                    Spacer(minLength: 0)

                    Picker("Live", selection: $liveEnabled) {
                        Text("Off").tag(false)
                        Text("Live").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: presentation == .sidebar ? 140 : 120)
                    .accessibilityLabel("Live preview")

                    if !liveEnabled {
                        Button {
                            refreshFrozen()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Refresh preview")
                    }

                    Picker("Size", selection: $family) {
                        Text("Small").tag(WidgetFamily.systemSmall)
                        if !restrictToSmallOnly {
                            Text("Medium").tag(WidgetFamily.systemMedium)
                            Text("Large").tag(WidgetFamily.systemLarge)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: presentation == .sidebar ? 280 : 240)
                    .accessibilityLabel("Preview size")

                    if presentation == .dock {
                        Button {
                            setExpanded(false)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Collapse preview")
                    }
                }

                WidgetPreview(
                    spec: effectiveSpec,
                    family: family,
                    maxHeight: expandedPreviewMaxHeight,
                    isLive: liveEnabled
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Preview is approximate; final widget size is device-dependent.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Group {
                        if liveEnabled {
                            Text("Live updates are debounced; widget buttons run locally.")
                        } else {
                            Text("Live is off — preview is frozen. Tap Refresh to apply changes.")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        )
    }

    private var collapsedCard: some View {
        collapsedPreviewSurface(
            HStack(spacing: 12) {
                WidgetPreviewThumbnail(
                    spec: effectiveSpec,
                    family: family,
                    height: collapsedThumbnailHeight,
                    renderingStyle: .live
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    statusLineLabel
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
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
        )
        .contentShape(cardShape)
        .onTapGesture { setExpanded(true) }
    }

    private var statusLineText: String {
        var parts: [String] = [familyLabel]

        if isDirty {
            parts.append("Unsaved")
        }

        if liveEnabled {
            parts.append("Live")
        }

        return parts.joined(separator: " • ")
    }

    private var accessibilityStatusLineText: String {
        var parts: [String] = [familyLabel]

        if isDirty {
            parts.append("unsaved changes")
        }

        if liveEnabled {
            parts.append("live")
        }

        return parts.joined(separator: ", ")
    }

    private var statusLineLabel: some View {
        HStack(spacing: 6) {
            if isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }

            Text(statusLineText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityStatusLineText)
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
        let isSingleFamily = (allowedFamilies.count <= 1)

        return Menu {
            Button { family = .systemSmall } label: {
                Label("Small", systemImage: "square")
            }
            if !restrictToSmallOnly {
                Button { family = .systemMedium } label: {
                    Label("Medium", systemImage: "rectangle")
                }
                Button { family = .systemLarge } label: {
                    Label("Large", systemImage: "rectangle.portrait")
                }
            }
        } label: {
            let label = Text(familyAbbreviation)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            if colorScheme == .dark {
                label
                    .background(.ultraThinMaterial, in: Capsule())
            } else {
                label
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.96),
                                        Color(uiColor: .systemBackground)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isSingleFamily)
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

    private var lightCardFill: some View {
        cardShape.fill(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var lightCardOverlay: some View {
        ZStack {
            cardShape.strokeBorder(Color.black.opacity(0.08), lineWidth: 1)

            cardShape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color("AccentColor").opacity(0.22),
                        Color("AccentColor").opacity(0.06),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
    }

    private var lightCardNoiseOverlay: some View {
        Image("RainFuzzNoise_Sparse")
            .resizable(resizingMode: .tile)
            .scaleEffect(1.10)
            .rotationEffect(.degrees(6))
            .blendMode(.softLight)
            .opacity(0.10)
            .clipShape(cardShape)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func expandedPreviewSurface<Content: View>(_ content: Content) -> some View {
        if colorScheme == .dark {
            content
                .background(.regularMaterial, in: cardShape)
                .overlay(cardShape.strokeBorder(.primary.opacity(0.10)))
                .shadow(color: .black.opacity(presentation == .dock ? 0.10 : 0.06), radius: 18, y: 8)
        } else {
            content
                .background(lightCardFill)
                .overlay(lightCardOverlay)
                .overlay(lightCardNoiseOverlay)
                .shadow(color: Color.black.opacity(presentation == .dock ? 0.14 : 0.10), radius: presentation == .dock ? 22 : 18, x: 0, y: presentation == .dock ? 10 : 8)
                .shadow(color: Color("AccentColor").opacity(0.10), radius: presentation == .dock ? 30 : 26, x: 0, y: presentation == .dock ? 18 : 14)
        }
    }

    @ViewBuilder
    private func collapsedPreviewSurface<Content: View>(_ content: Content) -> some View {
        if colorScheme == .dark {
            content
                .background(.regularMaterial, in: cardShape)
                .overlay(cardShape.strokeBorder(.primary.opacity(0.10)))
        } else {
            content
                .background(lightCardFill)
                .overlay(lightCardOverlay)
                .overlay(lightCardNoiseOverlay)
                .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
                .shadow(color: Color("AccentColor").opacity(0.08), radius: 24, x: 0, y: 14)
        }
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
            if verticalSizeClass == .compact { return 150 }

            if family == .systemLarge { return 260 }
            return 200
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

    private func ensureSpecStateInitialised() {
        if displayedSpec == nil {
            displayedSpec = spec
        }
        if frozenSpec == nil {
            frozenSpec = spec
        }
    }

    private func clampFamilyIfNeeded() {
        guard allowedFamilies.contains(family) else {
            family = allowedFamilies.first ?? .systemSmall
            return
        }
        if restrictToSmallOnly, family != .systemSmall {
            family = .systemSmall
        }
    }

    private func handleIncomingSpecChange(_ newValue: WidgetSpec) {
        ensureSpecStateInitialised()
        clampFamilyIfNeeded()
        guard liveEnabled else { return }
        scheduleDebouncedUpdate(to: newValue)
    }

    private func handleLiveToggleChange(_ enabled: Bool) {
        ensureSpecStateInitialised()
        clampFamilyIfNeeded()

        pendingTask?.cancel()
        pendingTask = nil

        if enabled {
            displayedSpec = spec
            scheduleDebouncedUpdate(to: spec)
        } else {
            frozenSpec = displayedSpec ?? spec
        }
    }

    private func refreshFrozen() {
        frozenSpec = spec
    }

    private func scheduleDebouncedUpdate(to newSpec: WidgetSpec) {
        pendingTask?.cancel()
        pendingTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                displayedSpec = newSpec
            }
        }
    }
}
