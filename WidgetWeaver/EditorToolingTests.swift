//
//  EditorToolingTests.swift
//  WidgetWeaverTests
//
//  Created by . . on 1/8/26.
//

import XCTest
@testable import WidgetWeaver

final class EditorToolingTests: XCTestCase {
    // MARK: - Capability derivation

    func testCapabilitiesPosterTemplateIncludesSmartPhotoAndAlbumShuffle() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .none,
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

        XCTAssertTrue(caps.contains(.canAccessPhotoLibrary))
        XCTAssertTrue(caps.contains(.hasImageConfigured))
        XCTAssertTrue(caps.contains(.hasSmartPhotoConfigured))

        XCTAssertFalse(caps.contains(.canEditActions))
        XCTAssertFalse(caps.contains(.canUseAI))
    }

    func testCapabilitiesClassicTemplateIncludesActionsButNoImage() {
        let ctx = EditorToolContext(
            template: .classic,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .none,
            focus: .widget,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .notDetermined),
            hasSymbolConfigured: false,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let caps = EditorToolRegistry.capabilities(for: ctx)

        XCTAssertTrue(caps.contains(.canEditSymbol))
        XCTAssertTrue(caps.contains(.canEditTypography))
        XCTAssertTrue(caps.contains(.canEditActions))

        XCTAssertFalse(caps.contains(.canEditImage))
        XCTAssertFalse(caps.contains(.canEditSmartPhoto))
        XCTAssertFalse(caps.contains(.canEditAlbumShuffle))

        XCTAssertFalse(caps.contains(.canAccessPhotoLibrary))
        XCTAssertFalse(caps.contains(.hasImageConfigured))
        XCTAssertFalse(caps.contains(.hasSmartPhotoConfigured))
    }

    // MARK: - Visible tool derivation

    func testVisibleToolsSmartPhotoCropFocusIsGatedToSmartPhotoSuite() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .element(id: "smartPhotoCrop"),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertEqual(
            tools,
            [.smartPhotoCrop, .smartPhoto, .smartRules, .albumShuffle, .image, .style]
        )

        XCTAssertFalse(tools.contains(.layout))
        XCTAssertFalse(tools.contains(.text))
        XCTAssertFalse(tools.contains(.typography))
    }

    func testVisibleToolsClockFocusDoesNotSurfaceSmartPhotoTools() {
        let ctx = EditorToolContext(
            template: .classic,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .clock,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertTrue(tools.contains(.widgets))
        XCTAssertTrue(tools.contains(.layout))
        XCTAssertTrue(tools.contains(.style))

        XCTAssertFalse(tools.contains(.smartPhoto))
        XCTAssertFalse(tools.contains(.smartPhotoCrop))
        XCTAssertFalse(tools.contains(.smartRules))
        XCTAssertFalse(tools.contains(.albumShuffle))

        XCTAssertFalse(tools.contains(.actions))
    }

    func testMultiSelectionIntersectionShrinksToolList() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .multi,
            focus: .widget,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertTrue(tools.contains(.layout))
        XCTAssertTrue(tools.contains(.style))
        XCTAssertTrue(tools.contains(.widgets))

        XCTAssertFalse(tools.contains(.text))
        XCTAssertFalse(tools.contains(.symbol))
        XCTAssertFalse(tools.contains(.image))
        XCTAssertFalse(tools.contains(.smartPhoto))
        XCTAssertFalse(tools.contains(.smartPhotoCrop))
        XCTAssertFalse(tools.contains(.smartRules))
        XCTAssertFalse(tools.contains(.albumShuffle))
        XCTAssertFalse(tools.contains(.typography))
        XCTAssertFalse(tools.contains(.actions))
    }
}
