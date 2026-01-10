//
//  EditorToolingNonPhotosCapabilityB2Tests.swift
//  WidgetWeaverTests
//
//  Created by . . on 1/10/26.
//

import XCTest
@testable import WidgetWeaver

final class EditorToolingNonPhotosCapabilityB2Tests: XCTestCase {
    func testAIToolIsHiddenWhenProIsLockedInNonAlbumElementFocus() {
        let ctx = makePosterNonAlbumElementFocusContext(isProUnlocked: false)

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertFalse(tools.contains(.ai))
        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .text, .style, .typography, .matchedSet, .variables, .sharing, .pro]
        )
    }

    func testAIToolIsVisibleWhenProIsUnlockedInNonAlbumElementFocus() {
        let ctx = makePosterNonAlbumElementFocusContext(isProUnlocked: true)

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertTrue(tools.contains(.ai))
        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .text, .style, .typography, .matchedSet, .variables, .sharing, .ai, .pro]
        )
    }

    func testAIToolIsHiddenWhenProIsLockedInClockFocus() {
        let ctx = makeHeroClockFocusContext(isProUnlocked: false)

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertFalse(tools.contains(.ai))
        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .style, .matchedSet, .variables, .sharing, .pro]
        )
    }

    func testAIToolIsVisibleWhenProIsUnlockedInClockFocus() {
        let ctx = makeHeroClockFocusContext(isProUnlocked: true)

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertTrue(tools.contains(.ai))
        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .style, .matchedSet, .variables, .sharing, .ai, .pro]
        )
    }

    func testToolOrderingIsStableWhenAIToolAppearsOrDisappears() {
        let freeCtx = makePosterNonAlbumElementFocusContext(isProUnlocked: false)
        let proCtx = makePosterNonAlbumElementFocusContext(isProUnlocked: true)

        let freeTools = EditorToolRegistry.visibleTools(for: freeCtx)
        let proTools = EditorToolRegistry.visibleTools(for: proCtx)

        XCTAssertFalse(freeTools.contains(.ai))
        XCTAssertTrue(proTools.contains(.ai))

        let proWithoutAI = proTools.filter { $0 != .ai }
        XCTAssertEqual(proWithoutAI, freeTools)
    }

    func testTeardownActionsDoNotFireWhenAIToolDisappears() {
        let proCtx = makeHeroClockFocusContext(isProUnlocked: true)
        let freeCtx = makeHeroClockFocusContext(isProUnlocked: false)

        let oldTools = EditorToolRegistry.visibleTools(for: proCtx)
        let newTools = EditorToolRegistry.visibleTools(for: freeCtx)

        let actions = editorToolTeardownActions(
            old: oldTools,
            new: newTools,
            currentFocus: proCtx.focus
        )

        XCTAssertTrue(actions.isEmpty)
    }

    func testLegacyVisibleToolsRespectNonPhotosRequirementsForAITool() {
        let freeCtx = makePosterNonAlbumElementFocusContext(isProUnlocked: false)
        let proCtx = makePosterNonAlbumElementFocusContext(isProUnlocked: true)

        let freeTools = EditorToolRegistry.legacyVisibleTools(for: freeCtx)
        let proTools = EditorToolRegistry.legacyVisibleTools(for: proCtx)

        XCTAssertFalse(freeTools.contains(.ai))
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

    private func makeHeroClockFocusContext(isProUnlocked: Bool) -> EditorToolContext {
        EditorToolContext(
            template: .hero,
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
