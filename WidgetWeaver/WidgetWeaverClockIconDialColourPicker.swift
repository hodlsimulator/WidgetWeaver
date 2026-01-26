//
//  WidgetWeaverClockIconDialColourPicker.swift
//  WidgetWeaver
//
//  Created by . . on 1/26/26.
//

import SwiftUI

/// Editor control for selecting a curated dial-fill colour for the Clock "Icon" face.
///
/// When `showsTitle` is true, the swatches are presented inside a persisted, collapsible section.
/// The collapse state is shared with the seconds-hand picker so only one palette is expanded at a time.
struct WidgetWeaverClockIconDialColourPicker: View {
    let clockThemeRaw: String
    let clockFaceRaw: String

    @Binding var clockIconDialColourTokenRaw: String?

    let showsTitle: Bool

    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(StorageKeys.expandedSection) private var expandedSectionRaw: String = ExpandedSection.dial.rawValue

    private enum StorageKeys {
        static let expandedSection = "widgetweaver.editor.clock.iconPalette.expandedSection"
    }

    private enum ExpandedSection: String {
        case dial
        case secondsHand
        case none
    }

    init(
        clockThemeRaw: String,
        clockFaceRaw: String,
        clockIconDialColourTokenRaw: Binding<String?>,
        showsTitle: Bool = true
    ) {
        self.clockThemeRaw = clockThemeRaw
        self.clockFaceRaw = clockFaceRaw
        _clockIconDialColourTokenRaw = clockIconDialColourTokenRaw
        self.showsTitle = showsTitle
    }

    private var selectedFaceToken: WidgetWeaverClockFaceToken {
        WidgetWeaverClockFaceToken.canonical(from: clockFaceRaw)
    }

    private var selectedToken: WidgetWeaverClockIconDialColourToken? {
        WidgetWeaverClockIconDialColourToken.canonical(from: clockIconDialColourTokenRaw)
    }

    private var selectedSummary: String {
        selectedToken?.displayName ?? "Scheme"
    }

    private var expandedSection: ExpandedSection {
        ExpandedSection(rawValue: expandedSectionRaw) ?? .dial
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedSection == .dial },
            set: { newValue in
                expandedSectionRaw = newValue ? ExpandedSection.dial.rawValue : ExpandedSection.none.rawValue
            }
        )
    }

    private struct Option: Identifiable {
        let id: String
        let title: String
        let tokenRaw: String?
    }

    private var options: [Option] {
        var out: [Option] = [
            Option(id: "scheme", title: "Scheme", tokenRaw: nil)
        ]

        out.append(contentsOf: WidgetWeaverClockIconDialColourToken.orderedForPicker.map { token in
            Option(id: token.rawValue, title: token.displayName, tokenRaw: token.rawValue)
        })

        return out
    }

    var body: some View {
        if selectedFaceToken != .icon {
            EmptyView()
        } else if showsTitle {
            DisclosureGroup(isExpanded: isExpanded) {
                swatchGrid
                    .padding(.top, 8)
            } label: {
                PaletteDisclosureLabel(
                    title: "Face colour",
                    summary: selectedSummary
                )
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("Editor.Clock.IconDialColourDisclosure")
            .accessibilityElement(children: .contain)
        } else {
            swatchGrid
                .padding(.vertical, 6)
                .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var swatchGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 120), spacing: 10)
            ],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(options) { option in
                let isSelected = (selectedToken?.rawValue == option.tokenRaw)
                    || (selectedToken == nil && option.tokenRaw == nil)

                let palette = WidgetWeaverClockAppearanceResolver
                    .resolve(
                        config: WidgetWeaverClockDesignConfig(
                            theme: clockThemeRaw,
                            face: clockFaceRaw,
                            iconDialColourToken: option.tokenRaw
                        ),
                        mode: colorScheme
                    )
                    .palette

                DialSwatchChip(
                    title: option.title,
                    fill: palette.iconDialFill,
                    isSelected: isSelected,
                    accessibilityID: "Editor.Clock.IconDialColour.\(option.id)",
                    action: {
                        clockIconDialColourTokenRaw = option.tokenRaw
                    }
                )
            }
        }
    }
}

private struct PaletteDisclosureLabel: View {
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
    }
}

private struct DialSwatchChip: View {
    let title: String
    let fill: Color
    let isSelected: Bool
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.25),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
