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

    @SceneStorage("widgetPreviewDock.isExpanded") private var isExpanded: Bool = false

    @AppStorage("preview.liveEnabled") private var liveEnabled: Bool = true

    @State private var displayedSpec: WidgetSpec? = nil
    @State private var frozenSpec: WidgetSpec? = nil
    @State private var pendingTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            switch presentation {
            case .sidebar:
                expandedCard
            case .dock:
                dockCard
            }
        }
        .onAppear { ensureSpecStateInitialised() }
        .onChange(of: spec) { _, newValue in
            handleIncomingSpecChange(newValue)
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
                    Text("Medium").tag(WidgetFamily.systemMedium)
                    Text("Large").tag(WidgetFamily.systemLarge)
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
        .background(.regularMaterial, in: cardShape)
        .overlay(cardShape.strokeBorder(.primary.opacity(0.10)))
        .shadow(color: .black.opacity(presentation == .dock ? 0.10 : 0.06), radius: 18, y: 8)
    }

    private var collapsedCard: some View {
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

                Text(statusLine)
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

    private var statusLine: String {
        if liveEnabled {
            return "\(familyLabel) • Live"
        }
        return "\(familyLabel)"
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
            Button { family = .systemSmall } label: {
                Label("Small", systemImage: "square")
            }
            Button { family = .systemMedium } label: {
                Label("Medium", systemImage: "rectangle")
            }
            Button { family = .systemLarge } label: {
                Label("Large", systemImage: "rectangle.portrait")
            }
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
            if verticalSizeClass == .compact { return 150 }

            // Small and Medium occupy the same Home Screen row height.
            // Using the same preview height avoids the preview changing depth between S/M.
            if family == .systemLarge { return 260 }

            // Medium is typically width-limited in the dock. Lowering this height reduces
            // wasted vertical space without making the widget itself smaller.
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

    private func handleIncomingSpecChange(_ newValue: WidgetSpec) {
        ensureSpecStateInitialised()
        guard liveEnabled else { return }
        scheduleDebouncedUpdate(to: newValue)
    }

    private func handleLiveToggleChange(_ enabled: Bool) {
        ensureSpecStateInitialised()

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
