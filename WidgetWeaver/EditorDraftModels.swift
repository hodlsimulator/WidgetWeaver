//
//  EditorDraftModels.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import SwiftUI
import WidgetKit

struct EditorDraft: Hashable {
    var baseDraft: FamilyDraft
    var matchedEnabled: Bool
    var smallDraft: FamilyDraft
    var mediumDraft: FamilyDraft
    var largeDraft: FamilyDraft

    static func fromSpec(_ spec: WidgetSpec) -> EditorDraft {
        if let matched = spec.matchedSet {
            return EditorDraft(
                baseDraft: FamilyDraft(from: spec),
                matchedEnabled: true,
                smallDraft: FamilyDraft(from: matched.small ?? spec),
                mediumDraft: FamilyDraft(from: matched.medium ?? spec),
                largeDraft: FamilyDraft(from: matched.large ?? spec)
            )
        } else {
            let d = FamilyDraft(from: spec)
            return EditorDraft(
                baseDraft: d,
                matchedEnabled: false,
                smallDraft: d,
                mediumDraft: d,
                largeDraft: d
            )
        }
    }

    func toSpec(id: UUID) -> WidgetSpec {
        let base = baseDraft.toFlatSpec(id: id)

        if matchedEnabled {
            let matched = WidgetSpecMatchedSet(
                small: smallDraft.toVariantSpec(id: id),
                medium: mediumDraft.toVariantSpec(id: id),
                large: largeDraft.toVariantSpec(id: id)
            )
            var out = base
            out.matchedSet = matched
            return out.normalised()
        }

        return base.normalised()
    }

    mutating func applySpec(_ spec: WidgetSpec) {
        self = EditorDraft.fromSpec(spec)
    }

    static func defaultDraft() -> EditorDraft {
        fromSpec(WidgetSpec.defaultSpec())
    }
}

struct FamilyDraft: Hashable {
    // MARK: Layout
    var titleText: String
    var subtitleText: String
    var backgroundHex: String
    var titleHex: String
    var subtitleHex: String

    // MARK: Chips
    var chips: [ChipDraft]

    // MARK: Image (poster background)
    var imageFileName: String
    var imageContentMode: ImageContentModeToken
    var imageHeight: Double
    var imageCornerRadius: Double
    var imageSmartPhoto: WWSmartPhotoSpec?

    // MARK: Template & Layout
    var template: LayoutTemplate
    var padding: Double
    var titleFontSize: Double
    var subtitleFontSize: Double
    var titleMaxLines: Int
    var subtitleMaxLines: Int
    var chipsColumnsSmall: Int
    var chipsColumnsMedium: Int
    var chipsColumnsLarge: Int
    var chipFontSize: Double
    var chipIconSize: Double
    var chipCornerRadius: Double
    var chipHorizontalPadding: Double
    var chipVerticalPadding: Double
    var chipBackgroundOpacity: Double
    var hSpacing: Double
    var vSpacing: Double
    var posterTitleFontSize: Double
    var posterSubtitleFontSize: Double

    init(from spec: WidgetSpec) {
        let s = spec.normalised()

        self.titleText = s.title ?? ""
        self.subtitleText = s.subtitle ?? ""

        self.backgroundHex = s.backgroundColor ?? ""
        self.titleHex = s.titleColor ?? "#FFFFFF"
        self.subtitleHex = s.subtitleColor ?? "#BFBFBF"

        self.chips = (s.chips ?? []).map { ChipDraft(from: $0) }

        if let img = s.image {
            self.imageFileName = img.fileName
            self.imageContentMode = img.contentMode
            self.imageHeight = img.height
            self.imageCornerRadius = img.cornerRadius
            self.imageSmartPhoto = img.smartPhoto
        } else {
            self.imageFileName = ""
            self.imageContentMode = .fill
            self.imageHeight = 120
            self.imageCornerRadius = 16
            self.imageSmartPhoto = nil
        }

        let layout = s.layout
        self.template = layout.template
        self.padding = layout.padding
        self.titleFontSize = layout.titleFontSize
        self.subtitleFontSize = layout.subtitleFontSize
        self.titleMaxLines = layout.titleMaxLines
        self.subtitleMaxLines = layout.subtitleMaxLines
        self.chipsColumnsSmall = layout.chipsColumnsSmall
        self.chipsColumnsMedium = layout.chipsColumnsMedium
        self.chipsColumnsLarge = layout.chipsColumnsLarge
        self.chipFontSize = layout.chipFontSize
        self.chipIconSize = layout.chipIconSize
        self.chipCornerRadius = layout.chipCornerRadius
        self.chipHorizontalPadding = layout.chipHorizontalPadding
        self.chipVerticalPadding = layout.chipVerticalPadding
        self.chipBackgroundOpacity = layout.chipBackgroundOpacity
        self.hSpacing = layout.hSpacing
        self.vSpacing = layout.vSpacing
        self.posterTitleFontSize = layout.posterTitleFontSize
        self.posterSubtitleFontSize = layout.posterSubtitleFontSize
    }

    func toFlatSpec(id: UUID) -> WidgetSpec {
        let chipsSpec: [ChipSpec] = chips.map { $0.toSpec() }
        let imgName = imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)

        let image: ImageSpec? = imgName.isEmpty ? nil : ImageSpec(
            fileName: imgName,
            contentMode: imageContentMode,
            height: imageHeight,
            cornerRadius: imageCornerRadius,
            smartPhoto: imageSmartPhoto
        )

        let layout = LayoutSpec(
            template: template,
            padding: padding,
            titleFontSize: titleFontSize,
            subtitleFontSize: subtitleFontSize,
            titleMaxLines: titleMaxLines,
            subtitleMaxLines: subtitleMaxLines,
            chipsColumnsSmall: chipsColumnsSmall,
            chipsColumnsMedium: chipsColumnsMedium,
            chipsColumnsLarge: chipsColumnsLarge,
            chipFontSize: chipFontSize,
            chipIconSize: chipIconSize,
            chipCornerRadius: chipCornerRadius,
            chipHorizontalPadding: chipHorizontalPadding,
            chipVerticalPadding: chipVerticalPadding,
            chipBackgroundOpacity: chipBackgroundOpacity,
            hSpacing: hSpacing,
            vSpacing: vSpacing,
            posterTitleFontSize: posterTitleFontSize,
            posterSubtitleFontSize: posterSubtitleFontSize
        )

        return WidgetSpec(
            id: id,
            title: titleText,
            subtitle: subtitleText,
            backgroundColor: backgroundHex.isEmpty ? nil : backgroundHex,
            titleColor: titleHex,
            subtitleColor: subtitleHex,
            chips: chipsSpec.isEmpty ? nil : chipsSpec,
            image: image,
            layout: layout,
            matchedSet: nil,
            updatedAt: Date()
        ).normalised()
    }

    func toVariantSpec(id: UUID) -> WidgetSpecVariant {
        let chipsSpec: [ChipSpec] = chips.map { $0.toSpec() }
        let imgName = imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)

        let image: ImageSpec? = imgName.isEmpty ? nil : ImageSpec(
            fileName: imgName,
            contentMode: imageContentMode,
            height: imageHeight,
            cornerRadius: imageCornerRadius,
            smartPhoto: imageSmartPhoto
        )

        let layout = LayoutSpec(
            template: template,
            padding: padding,
            titleFontSize: titleFontSize,
            subtitleFontSize: subtitleFontSize,
            titleMaxLines: titleMaxLines,
            subtitleMaxLines: subtitleMaxLines,
            chipsColumnsSmall: chipsColumnsSmall,
            chipsColumnsMedium: chipsColumnsMedium,
            chipsColumnsLarge: chipsColumnsLarge,
            chipFontSize: chipFontSize,
            chipIconSize: chipIconSize,
            chipCornerRadius: chipCornerRadius,
            chipHorizontalPadding: chipHorizontalPadding,
            chipVerticalPadding: chipVerticalPadding,
            chipBackgroundOpacity: chipBackgroundOpacity,
            hSpacing: hSpacing,
            vSpacing: vSpacing,
            posterTitleFontSize: posterTitleFontSize,
            posterSubtitleFontSize: posterSubtitleFontSize
        )

        return WidgetSpecVariant(
            title: titleText,
            subtitle: subtitleText,
            backgroundColor: backgroundHex.isEmpty ? nil : backgroundHex,
            titleColor: titleHex,
            subtitleColor: subtitleHex,
            chips: chipsSpec.isEmpty ? nil : chipsSpec,
            image: image,
            layout: layout,
            updatedAt: Date()
        ).normalised()
    }

    mutating func apply(flatSpec: WidgetSpec) {
        let s = flatSpec.normalised()

        titleText = s.title ?? ""
        subtitleText = s.subtitle ?? ""

        backgroundHex = s.backgroundColor ?? ""
        titleHex = s.titleColor ?? "#FFFFFF"
        subtitleHex = s.subtitleColor ?? "#BFBFBF"

        chips = (s.chips ?? []).map { ChipDraft(from: $0) }

        if let img = s.image {
            imageFileName = img.fileName
            imageContentMode = img.contentMode
            imageHeight = img.height
            imageCornerRadius = img.cornerRadius
            imageSmartPhoto = img.smartPhoto
        } else {
            imageFileName = ""
            imageSmartPhoto = nil
        }

        let layout = s.layout
        template = layout.template
        padding = layout.padding
        titleFontSize = layout.titleFontSize
        subtitleFontSize = layout.subtitleFontSize
        titleMaxLines = layout.titleMaxLines
        subtitleMaxLines = layout.subtitleMaxLines
        chipsColumnsSmall = layout.chipsColumnsSmall
        chipsColumnsMedium = layout.chipsColumnsMedium
        chipsColumnsLarge = layout.chipsColumnsLarge
        chipFontSize = layout.chipFontSize
        chipIconSize = layout.chipIconSize
        chipCornerRadius = layout.chipCornerRadius
        chipHorizontalPadding = layout.chipHorizontalPadding
        chipVerticalPadding = layout.chipVerticalPadding
        chipBackgroundOpacity = layout.chipBackgroundOpacity
        hSpacing = layout.hSpacing
        vSpacing = layout.vSpacing
        posterTitleFontSize = layout.posterTitleFontSize
        posterSubtitleFontSize = layout.posterSubtitleFontSize
    }
}

struct ChipDraft: Hashable, Identifiable {
    var id: UUID
    var text: String
    var icon: String
    var backgroundHex: String
    var textHex: String
    var iconHex: String

    init(from spec: ChipSpec) {
        let s = spec.normalised()
        id = s.id
        text = s.text
        icon = s.icon ?? ""
        backgroundHex = s.backgroundColor ?? "#2A2A2E"
        textHex = s.textColor ?? "#FFFFFF"
        iconHex = s.iconColor ?? "#FFFFFF"
    }

    func toSpec() -> ChipSpec {
        ChipSpec(
            id: id,
            text: text,
            icon: icon.isEmpty ? nil : icon,
            backgroundColor: backgroundHex.isEmpty ? nil : backgroundHex,
            textColor: textHex.isEmpty ? nil : textHex,
            iconColor: iconHex.isEmpty ? nil : iconHex
        ).normalised()
    }
}
