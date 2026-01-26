//
//  WidgetWeaverClockIconSecondHandColourPicker.swift
//  WidgetWeaver
//
//  Created by . . on 1/26/26.
//

import SwiftUI

/// Editor control for selecting a curated seconds-hand colour for the Clock "Icon" face.
///
/// The swatches must resolve through the shared clock appearance resolver to avoid
/// preview↔Home Screen drift.
struct WidgetWeaverClockIconSecondHandColourPicker: View {
    let clockThemeRaw: String
    let clockFaceRaw: String
    let clockIconDialColourTokenRaw: String?

    @Binding var clockIconSecondHandColourTokenRaw: String?

    @Environment(\.colorScheme) private var colorScheme

    private var selectedFaceToken: WidgetWeaverClockFaceToken {
        WidgetWeaverClockFaceToken.canonical(from: clockFaceRaw)
    }

    private var selectedToken: WidgetWeaverClockSecondHandColourToken? {
        WidgetWeaverClockSecondHandColourToken.canonical(from: clockIconSecondHandColourTokenRaw)
    }

    private struct Option: Identifiable {
        let id: String
        let title: String
        let tokenRaw: String?
    }

    private var options: [Option] {
        var out: [Option] = [
            Option(id: "default", title: "Default", tokenRaw: nil)
        ]

        out.append(contentsOf: WidgetWeaverClockSecondHandColourToken.orderedForPicker
            .filter { $0 != .red }
            .map { token in
                Option(id: token.rawValue, title: token.displayName, tokenRaw: token.rawValue)
            }
        )

        return out
    }

    var body: some View {
        if selectedFaceToken != .icon {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Seconds hand colour")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

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
                                    iconDialColourToken: clockIconDialColourTokenRaw,
                                    iconSecondHandColourToken: option.tokenRaw
                                ),
                                mode: colorScheme
                            )
                            .palette

                        SecondHandSwatchChip(
                            title: option.title,
                            colour: palette.iconSecondHand,
                            isSelected: isSelected,
                            accessibilityID: "Editor.Clock.IconSecondHandColour.\(option.id)",
                            action: {
                                clockIconSecondHandColourTokenRaw = option.tokenRaw
                            }
                        )
                    }
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)
        }
    }
}

private struct SecondHandSwatchChip: View {
    let title: String
    let colour: Color
    let isSelected: Bool
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 28, height: 28)
                    .overlay(
                        ZStack {
                            Capsule(style: .continuous)
                                .fill(colour)
                                .frame(width: 4, height: 18)
                        }
                    )
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
