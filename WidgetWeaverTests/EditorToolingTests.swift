//
//  EditorToolingTests.swift
//  WidgetWeaverTests
//
//  Created by . . on 1/8/26.
//

import XCTest
@testable import WidgetWeaver

final class EditorToolingTests: XCTestCase {
    func testToolManifestIsSortedByOrder() {
        let tools = EditorToolRegistry.toolsSortedByOrder.map(\.order)
        XCTAssertEqual(tools, tools.sorted())
    }

    func testToolManifestHasUniqueIDs() {
        let ids = EditorToolRegistry.tools.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testToolManifestMixedSelectionPolicyIsExplicit() {
        let expectedMixedAllowed: Set<EditorToolID> = [
            .status,
            .designs,
            .widgets,
            .layout,
            .style,
            .matchedSet,
            .variables,
            .sharing,
            .ai,
            .pro,
        ]

        for tool in EditorToolRegistry.tools {
            if tool.eligibility.selectionDescriptorPolicy == .mixedAllowed {
                XCTAssertTrue(expectedMixedAllowed.contains(tool.id), "Unexpected mixed-allowed tool: \(tool.id)")
            }
        }
    }

    func testCapabilitiesPosterTemplateIncludesSmartPhotoAndAlbumShuffle() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .widget,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let caps = EditorToolRegistry.capabilities(for: ctx)

        XCTAssertTrue(caps.contains(.canEditLayout))
        XCTAssertTrue(caps.contains(.canEditTextContent))
        XCTAssertTrue(caps.contains(.canEditStyle))
        XCTAssertTrue(caps.contains(.canEditImage))
        XCTAssertTrue(caps.contains(.canEditSmartPhoto))
        XCTAssertTrue(caps.contains(.canEditAlbumShuffle))
        XCTAssertTrue(caps.contains(.canEditTypography))

        XCTAssertFalse(caps.contains(.canEditSymbol))
        XCTAssertFalse(caps.contains(.canEditActions))

        XCTAssertTrue(caps.contains(.canUseAI))
    }

    func testCapabilitiesClassicTemplateIncludesActionsButNoImage() {
        let ctx = EditorToolContext(
            template: .classic,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .widget,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: true,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let caps = EditorToolRegistry.capabilities(for: ctx)

        XCTAssertTrue(caps.contains(.canEditLayout))
        XCTAssertTrue(caps.contains(.canEditTextContent))
        XCTAssertTrue(caps.contains(.canEditStyle))
        XCTAssertTrue(caps.contains(.canEditSymbol))
        XCTAssertTrue(caps.contains(.canEditTypography))
        XCTAssertTrue(caps.contains(.canEditActions))

        XCTAssertFalse(caps.contains(.canEditImage))
        XCTAssertFalse(caps.contains(.canEditSmartPhoto))
    }

    func testVisibleToolsNonAlbumWidgetSelectionIncludesLayoutAndStyleInOrder() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .element(id: "widgetweaver.element.text"),
            selectionCount: 1,
            selectionComposition: .known([.nonAlbum]),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertEqual(tools, [.status, .designs, .widgets, .layout, .text, .style, .typography, .matchedSet, .variables, .sharing, .ai, .pro])
    }

    func testSmartPhotoCropFocusShowsSmartPhotosSuiteOnly() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .albumPhoto(albumID: "smartPhotoAlbum", itemID: "itemA", subtype: .smart),
            selectionCount: 1,
            selectionComposition: .known([.albumPhotoItem]),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertTrue(tools.contains(.smartPhoto))
        XCTAssertTrue(tools.contains(.smartPhotoCrop))
        XCTAssertTrue(tools.contains(.image))
        XCTAssertTrue(tools.contains(.albumShuffle))
        XCTAssertTrue(tools.contains(.smartRules))

        XCTAssertFalse(tools.contains(.layout))
        XCTAssertFalse(tools.contains(.text))
        XCTAssertFalse(tools.contains(.style))
        XCTAssertFalse(tools.contains(.typography))
    }

    func testSmartRulesEditorFocusPinsSmartRulesToolToFront() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .smartRuleEditor(albumID: "smartPhotoAlbum"),
            selectionCount: 1,
            selectionComposition: .known([.albumContainer]),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertEqual(tools.first, .smartRules)
    }

    func testVisibleToolsClockFocusDoesNotSurfaceSmartPhotoTools() {
        let ctx = EditorToolContext(
            template: .classic,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .clock,
            selectionCount: 1,
            selectionComposition: .known([.nonAlbum]),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertTrue(tools.contains(.widgets))
        XCTAssertTrue(tools.contains(.layout))
        XCTAssertTrue(tools.contains(.style))

        XCTAssertFalse(tools.contains(.smartPhoto))
        XCTAssertFalse(tools.contains(.smartPhotoCrop))
        XCTAssertFalse(tools.contains(.albumShuffle))
        XCTAssertFalse(tools.contains(.smartRules))

        XCTAssertFalse(tools.contains(.actions))
    }

    func testMultiSelectionWithExplicitCompositionUsesMultiSafeToolList() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .multi,
            focus: .widget,
            selectionCount: 3,
            selectionComposition: .known([.albumContainer, .nonAlbum]),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .style, .matchedSet, .variables, .sharing, .ai, .pro]
        )
    }

    func testMultiSelectionIntersectionShrinksToolList() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .multi,
            focus: .widget,
            selectionCount: 2,
            selectionComposition: .known([.albumContainer, .nonAlbum]),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertTrue(tools.contains(.widgets))
        XCTAssertTrue(tools.contains(.layout))
        XCTAssertTrue(tools.contains(.style))

        XCTAssertFalse(tools.contains(.text))
        XCTAssertFalse(tools.contains(.image))
        XCTAssertFalse(tools.contains(.smartPhoto))
        XCTAssertFalse(tools.contains(.smartPhotoCrop))
        XCTAssertFalse(tools.contains(.albumShuffle))
        XCTAssertFalse(tools.contains(.smartRules))
        XCTAssertFalse(tools.contains(.typography))
    }

    func testLegacyVisibleToolsIgnoreAvailabilityRequirements() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .widget,
            selectionCount: 1,
            selectionComposition: .known([.nonAlbum]),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .denied),
            hasSymbolConfigured: false,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let legacy = EditorToolRegistry.legacyVisibleTools(for: ctx)

        XCTAssertTrue(legacy.contains(.albumShuffle))
        XCTAssertTrue(legacy.contains(.smartRules))
        XCTAssertTrue(legacy.contains(.smartPhotoCrop))
    }

    func testSelectionDescriptorPolicyIsExplicitForAllTools() {
        for tool in EditorToolRegistry.tools {
            XCTAssertNotNil(tool.eligibility.selectionDescriptorPolicy)
        }
    }

    func testPerformanceVisibleToolsComputationIsFastEnough() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .widget,
            selectionCount: 1,
            selectionComposition: .known([.nonAlbum]),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        measure {
            for _ in 0..<10_000 {
                _ = EditorToolRegistry.visibleTools(for: ctx)
            }
        }
    }
}

// MARK: - Helpers (local)

extension Font.Weight {
    static var supportedRange: ClosedRange<Int> { 1...9 }
}

private extension Int {
    var clampedToWeight: Font.Weight {
        switch self {
        case 1: return .ultraLight
        case 2: return .thin
        case 3: return .light
        case 4: return .regular
        case 5: return .medium
        case 6: return .semibold
        case 7: return .bold
        case 8: return .heavy
        default: return .black
        }
    }
}
