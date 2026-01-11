//
//  EditorNonPhotosUnavailableUXTests.swift
//  WidgetWeaverTests
//
//  Created by . . on 1/11/26.
//

import XCTest
@testable import WidgetWeaver

final class EditorNonPhotosUnavailableUXTests: XCTestCase {
    func testAIToolIsVisibleButUnavailableWhenProLocked() {
        let ctx = EditorToolContext(
            template: .classic,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .clock,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertTrue(tools.contains(.ai))

        let unavailable = EditorToolRegistry.unavailableState(for: .ai, context: ctx)
        XCTAssertEqual(unavailable, EditorUnavailableState.proRequiredForAI())
        XCTAssertEqual(unavailable?.cta?.kind, .showPro)
    }

    func testAIToolIsAvailableWhenProUnlocked() {
        let ctx = EditorToolContext(
            template: .classic,
            isProUnlocked: true,
            matchedSetEnabled: false,
            selection: .single,
            focus: .clock,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertTrue(tools.contains(.ai))

        let unavailable = EditorToolRegistry.unavailableState(for: .ai, context: ctx)
        XCTAssertNil(unavailable)
    }

    func testToolOrderIsStableAcrossProUnlockForNonAlbumSelection() {
        let freeCtx = EditorToolContext(
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

        let proCtx = EditorToolContext(
            template: .poster,
            isProUnlocked: true,
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

        let freeTools = EditorToolRegistry.visibleTools(for: freeCtx)
        let proTools = EditorToolRegistry.visibleTools(for: proCtx)

        XCTAssertEqual(freeTools, proTools)
    }

    func testTeardownActionsAreEmptyWhenToolListDoesNotChangeAcrossProUnlock() {
        let freeCtx = EditorToolContext(
            template: .classic,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .clock,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let proCtx = EditorToolContext(
            template: .classic,
            isProUnlocked: true,
            matchedSetEnabled: false,
            selection: .single,
            focus: .clock,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let oldTools = EditorToolRegistry.visibleTools(for: freeCtx)
        let newTools = EditorToolRegistry.visibleTools(for: proCtx)

        let actions = editorToolTeardownActions(
            old: oldTools,
            new: newTools,
            currentFocus: .clock
        )

        XCTAssertTrue(actions.isEmpty)
    }
}
