//
//  EditorToolingNonPhotosCapabilityB2Tests.swift
//  WidgetWeaverTests
//
//  Created by . . on 1/10/26.
//

import XCTest
@testable import WidgetWeaver

final class EditorToolingNonPhotosCapabilityB2Tests: XCTestCase {
    func testAIToolIsVisibleButUnavailableWhenProIsLockedInNonAlbumElementFocus() {
        let ctx = makePosterNonAlbumElementFocusContext(isProUnlocked: false)

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertTrue(tools.contains(.ai))

        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .text, .style, .typography, .matchedSet, .variables, .sharing, .ai, .pro]
        )

        let unavailable = EditorToolRegistry.unavailableState(for: .ai, context: ctx)
        XCTAssertEqual(unavailable, EditorUnavailableState.proRequiredForAI())
        XCTAssertEqual(unavailable?.cta?.kind, .showPro)
    }

    func testAIToolIsVisibleAndAvailableWhenProIsUnlockedInNonAlbumElementFocus() {
        let ctx = makePosterNonAlbumElementFocusContext(isProUnlocked: true)

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertTrue(tools.contains(.ai))

        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .text, .style, .typography, .matchedSet, .variables, .sharing, .ai, .pro]
        )

        let unavailable = EditorToolRegistry.unavailableState(for: .ai, context: ctx)
        XCTAssertNil(unavailable)
    }

    func testAIToolIsVisibleButUnavailableWhenProIsLockedInClockFocus() {
        let ctx = makeClassicClockFocusContext(isProUnlocked: false)

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertTrue(tools.contains(.ai))

        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .style, .matchedSet, .variables, .sharing, .ai, .pro]
        )

        let unavailable = EditorToolRegistry.unavailableState(for: .ai, context: ctx)
        XCTAssertEqual(unavailable, EditorUnavailableState.proRequiredForAI())
        XCTAssertEqual(unavailable?.cta?.kind, .showPro)
    }

    func testAIToolIsVisibleAndAvailableWhenProIsUnlockedInClockFocus() {
        let ctx = makeClassicClockFocusContext(isProUnlocked: true)

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertTrue(tools.contains(.ai))

        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .style, .matchedSet, .variables, .sharing, .ai, .pro]
        )

        let unavailable = EditorToolRegistry.unavailableState(for: .ai, context: ctx)
        XCTAssertNil(unavailable)
    }

    func testToolOrderingIsStableAcrossProUnlockInNonAlbumElementFocus() {
        let freeCtx = makePosterNonAlbumElementFocusContext(isProUnlocked: false)
        let proCtx = makePosterNonAlbumElementFocusContext(isProUnlocked: true)

        let freeTools = EditorToolRegistry.visibleTools(for: freeCtx)
        let proTools = EditorToolRegistry.visibleTools(for: proCtx)

        XCTAssertEqual(freeTools, proTools)
    }

    func testTeardownActionsDoNotFireWhenProUnlockFlips() {
        let freeCtx = makeClassicClockFocusContext(isProUnlocked: false)
        let proCtx = makeClassicClockFocusContext(isProUnlocked: true)

        let oldTools = EditorToolRegistry.visibleTools(for: freeCtx)
        let newTools = EditorToolRegistry.visibleTools(for: proCtx)

        let actions = editorToolTeardownActions(
            old: oldTools,
            new: newTools,
            currentFocus: freeCtx.focus
        )

        XCTAssertTrue(actions.isEmpty)
    }

    func testLegacyVisibleToolsIncludeAIToolEvenWhenProIsLocked() {
        let freeCtx = makePosterNonAlbumElementFocusContext(isProUnlocked: false)
        let proCtx = makePosterNonAlbumElementFocusContext(isProUnlocked: true)

        let freeTools = EditorToolRegistry.legacyVisibleTools(for: freeCtx)
        let proTools = EditorToolRegistry.legacyVisibleTools(for: proCtx)

        XCTAssertTrue(freeTools.contains(.ai))
        XCTAssertTrue(proTools.contains(.ai))
    }

    // MARK: - Helpers

    private func makePosterNonAlbumElementFocusContext(isProUnlocked: Bool) -> EditorToolContext {
        EditorToolContext(
            template: .poster,
            isProUnlocked: isProUnlocked,
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
    }

    private func makeClassicClockFocusContext(isProUnlocked: Bool) -> EditorToolContext {
        EditorToolContext(
            template: .classic,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: false,
            selection: .single,
            focus: .clock,
            selectionCount: 1,
            selectionComposition: .known([.nonAlbum]),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: true,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )
    }
}
