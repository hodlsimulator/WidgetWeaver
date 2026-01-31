//
//  WidgetWeaverThemeApplierTests.swift
//  WidgetWeaver
//
//  Created by . . on 1/31/26.
//

import Foundation
import Testing
@testable import WidgetWeaver

struct WidgetWeaverThemeApplierTests {

    @Test func apply_overwritesStyle_withoutCreatingClockConfig_forNonClockTemplates() {
        let base = WidgetSpec(
            version: WidgetSpec.currentVersion,
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Test",
            primaryText: "Hello",
            secondaryText: "World",
            updatedAt: Date(timeIntervalSince1970: 0),
            symbol: nil,
            image: nil,
            layout: LayoutSpec.defaultLayout,
            style: StyleSpec.defaultStyle,
            actionBar: nil,
            remindersConfig: nil,
            clockConfig: nil,
            matchedSet: nil
        )

        for preset in WidgetWeaverThemeCatalog.ordered {
            let applied = WidgetWeaverThemeApplier.apply(preset: preset, to: base)

            #expect(applied.layout.template == base.layout.template)
            #expect(applied.style == preset.style.normalised())
            #expect(applied.clockConfig == nil)
            #expect(applied == applied.normalised())
        }
    }

    @Test func apply_appliesClockTheme_andEnsuresClockConfig_forClockTemplates() {
        var clockSpec = WidgetSpec(
            version: WidgetSpec.currentVersion,
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Clock",
            primaryText: "",
            secondaryText: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            symbol: nil,
            image: nil,
            layout: LayoutSpec(
                template: .clockIcon,
                posterOverlayMode: .caption,
                showsAccentBar: true,
                axis: .vertical,
                alignment: .leading,
                spacing: 8,
                primaryLineLimitSmall: 1,
                primaryLineLimit: 2,
                secondaryLineLimitSmall: 1,
                secondaryLineLimit: 2
            ),
            style: StyleSpec.defaultStyle,
            actionBar: nil,
            remindersConfig: nil,
            clockConfig: nil,
            matchedSet: nil
        )

        // Explicitly keep it un-normalised here to exercise the "ensure config exists" behaviour.
        clockSpec.version = WidgetSpec.currentVersion

        for preset in WidgetWeaverThemeCatalog.ordered {
            let applied = WidgetWeaverThemeApplier.apply(preset: preset, to: clockSpec)

            #expect(applied.layout.template == .clockIcon)
            #expect(applied.clockConfig != nil)
            #expect(applied.style == preset.style.normalised())

            if let expectedTheme = preset.clockThemeRaw {
                #expect(applied.clockConfig?.theme == expectedTheme)
            }

            #expect(applied.clockConfig?.face == WidgetWeaverClockDesignConfig.defaultFace)
            #expect(applied == applied.normalised())
        }
    }
}
