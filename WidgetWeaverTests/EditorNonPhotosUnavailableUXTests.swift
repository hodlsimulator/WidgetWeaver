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
