//
//  EditorNonPhotosUnavailableUXTests.swift
//  WidgetWeaverTests
//
//  Created by . . on 1/11/26.
//

import XCTest
@testable import WidgetWeaver

/// Slice 10S-B3
///
/// Migrates one non-Photos tool to use manifest-driven “visible but unavailable” gating when
/// a required non-Photos capability is missing.
final class EditorToolingNonPhotosUnavailableUXB3Tests: XCTestCase {
    func testVariablesToolIsVisibleButUnavailableWhenProIsLockedInClockFocus() {
        let ctx = makeClassicClockFocusContext(isProUnlocked: false)

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertTrue(tools.contains(.variables))

        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .style, .matchedSet, .variables, .sharing, .ai, .pro]
        )

        let unavailable = EditorToolRegistry.unavailableState(for: .variables, context: ctx)
        XCTAssertEqual(unavailable, EditorUnavailableState.proRequiredForVariables())
        XCTAssertEqual(unavailable?.cta?.kind, .showPro)
    }

    func testVariablesToolIsVisibleAndAvailableWhenProIsUnlockedInClockFocus() {
        let ctx = makeClassicClockFocusContext(isProUnlocked: true)

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertTrue(tools.contains(.variables))

        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .style, .matchedSet, .variables, .sharing, .ai, .pro]
        )

        let unavailable = EditorToolRegistry.unavailableState(for: .variables, context: ctx)
        XCTAssertNil(unavailable)
    }

    func testToolOrderingIsStableAcrossProUnlockInClockFocus() {
        let freeCtx = makeClassicClockFocusContext(isProUnlocked: false)
        let proCtx = makeClassicClockFocusContext(isProUnlocked: true)

        let freeTools = EditorToolRegistry.visibleTools(for: freeCtx)
        let proTools = EditorToolRegistry.visibleTools(for: proCtx)

        XCTAssertEqual(freeTools, proTools)
    }

    func testTeardownActionsDoNotFireWhenProUnlockFlipsInClockFocus() {
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

    // MARK: - Helpers

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

/// Slice 10S-B4
///
/// Adds a second non-Photos capability and migrates Matched Set to use manifest-driven
/// “visible but unavailable” gating when the required non-Photos capability is missing.
final class EditorToolingNonPhotosUnavailableUXB4Tests: XCTestCase {
    func testMatchedSetToolIsVisibleButUnavailableWhenProIsLockedAndMatchedSetIsDisabledInClockFocus() {
        let ctx = makeClassicClockFocusContext(isProUnlocked: false, matchedSetEnabled: false)

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertTrue(tools.contains(.matchedSet))

        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .style, .matchedSet, .variables, .sharing, .ai, .pro]
        )

        let unavailable = EditorToolRegistry.unavailableState(for: .matchedSet, context: ctx)
        XCTAssertEqual(unavailable, EditorUnavailableState.proRequiredForMatchedSet())
        XCTAssertEqual(unavailable?.cta?.kind, .showPro)
    }

    func testMatchedSetToolIsVisibleAndAvailableWhenProIsLockedButMatchedSetIsEnabledInClockFocus() {
        let ctx = makeClassicClockFocusContext(isProUnlocked: false, matchedSetEnabled: true)

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertTrue(tools.contains(.matchedSet))

        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .style, .matchedSet, .variables, .sharing, .ai, .pro]
        )

        let unavailable = EditorToolRegistry.unavailableState(for: .matchedSet, context: ctx)
        XCTAssertNil(unavailable)
    }

    func testMatchedSetToolIsVisibleButUnavailableWhenProIsLockedAndMatchedSetIsDisabledInNonAlbumElementFocus() {
        let ctx = makePosterNonAlbumElementFocusContext(isProUnlocked: false, matchedSetEnabled: false)

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertTrue(tools.contains(.matchedSet))

        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .text, .style, .typography, .matchedSet, .variables, .sharing, .ai, .pro]
        )

        let unavailable = EditorToolRegistry.unavailableState(for: .matchedSet, context: ctx)
        XCTAssertEqual(unavailable, EditorUnavailableState.proRequiredForMatchedSet())
        XCTAssertEqual(unavailable?.cta?.kind, .showPro)
    }

    func testMatchedSetToolIsVisibleAndAvailableWhenProIsLockedButMatchedSetIsEnabledInNonAlbumElementFocus() {
        let ctx = makePosterNonAlbumElementFocusContext(isProUnlocked: false, matchedSetEnabled: true)

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertTrue(tools.contains(.matchedSet))

        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .text, .style, .typography, .matchedSet, .variables, .sharing, .ai, .pro]
        )

        let unavailable = EditorToolRegistry.unavailableState(for: .matchedSet, context: ctx)
        XCTAssertNil(unavailable)
    }

    func testToolOrderingIsStableAcrossMatchedSetToggleInClockFocusWhenProIsLocked() {
        let disabledCtx = makeClassicClockFocusContext(isProUnlocked: false, matchedSetEnabled: false)
        let enabledCtx = makeClassicClockFocusContext(isProUnlocked: false, matchedSetEnabled: true)

        let disabledTools = EditorToolRegistry.visibleTools(for: disabledCtx)
        let enabledTools = EditorToolRegistry.visibleTools(for: enabledCtx)

        XCTAssertEqual(disabledTools, enabledTools)
    }

    func testTeardownActionsDoNotFireWhenMatchedSetToggleFlipsInClockFocus() {
        let disabledCtx = makeClassicClockFocusContext(isProUnlocked: false, matchedSetEnabled: false)
        let enabledCtx = makeClassicClockFocusContext(isProUnlocked: false, matchedSetEnabled: true)

        let oldTools = EditorToolRegistry.visibleTools(for: disabledCtx)
        let newTools = EditorToolRegistry.visibleTools(for: enabledCtx)

        let actions = editorToolTeardownActions(
            old: oldTools,
            new: newTools,
            currentFocus: disabledCtx.focus
        )

        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: - Helpers

    private func makePosterNonAlbumElementFocusContext(isProUnlocked: Bool, matchedSetEnabled: Bool) -> EditorToolContext {
        EditorToolContext(
            template: .poster,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
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

    private func makeClassicClockFocusContext(isProUnlocked: Bool, matchedSetEnabled: Bool) -> EditorToolContext {
        EditorToolContext(
            template: .classic,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
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
