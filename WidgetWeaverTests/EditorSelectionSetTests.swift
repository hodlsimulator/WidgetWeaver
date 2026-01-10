//
//  EditorSelectionSetTests.swift
//  WidgetWeaverTests
//
//  Created by . . on 1/9/26.
//

import XCTest
@testable import WidgetWeaver

final class EditorSelectionSetTests: XCTestCase {
    func testSelectionSetProducesOriginBackedNonAlbumMultiSelectionSnapshot() {
        let selection = EditorSelectionSet(items: [
            .nonAlbumElement(id: "unitTest.widgetA"),
            .nonAlbumElement(id: "unitTest.widgetB"),
        ])

        let focus = selection.toFocusSnapshot()

        XCTAssertEqual(focus.selection, .multi)
        XCTAssertEqual(focus.focus, .widget)
        XCTAssertEqual(focus.selectionCount, 2)
        XCTAssertEqual(focus.selectionComposition, .known([.nonAlbum]))

        let (normalised, diagnostics) = EditorFocusSnapshotNormaliser.normaliseWithDiagnostics(focus)
        XCTAssertEqual(normalised.selectionCount, 2)
        XCTAssertEqual(normalised.selectionComposition, .known([.nonAlbum]))
        XCTAssertFalse(diagnostics.didInferAnySelectionMetadata)
    }

    func testSelectionSetProducesOriginBackedMixedMultiSelectionSnapshotAndToolList() {
        let selection = EditorSelectionSet(items: [
            .albumContainer(id: "unitTest.albumContainer", subtype: .smart),
            .nonAlbumElement(id: "unitTest.widgetA"),
            .nonAlbumElement(id: "unitTest.widgetB"),
        ])

        let focus = selection.toFocusSnapshot()

        XCTAssertEqual(focus.selection, .multi)
        XCTAssertEqual(focus.focus, .widget)
        XCTAssertEqual(focus.selectionCount, 3)
        XCTAssertEqual(focus.selectionComposition, .known([.albumContainer, .nonAlbum]))

        var draft = FamilyDraft.defaultDraft
        draft.template = .poster

        let ctx = EditorContextEvaluator.evaluate(
            draft: draft,
            isProUnlocked: false,
            matchedSetEnabled: false,
            focus: focus,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised)
        )

        XCTAssertEqual(ctx.selection, .multi)
        XCTAssertEqual(ctx.selectionCount, 3)
        XCTAssertEqual(ctx.selectionComposition, .known([.albumContainer, .nonAlbum]))

        let tools = EditorToolRegistry.visibleTools(for: ctx)
        XCTAssertEqual(
            tools,
            [.status, .designs, .widgets, .layout, .style, .matchedSet, .variables, .sharing, .pro]
        )
    }
}

final class EditorFocusRestorationStackTests: XCTestCase {
    func testEnteringSmartRulesEditorPushesPreviousSnapshot() {
        var stack = EditorFocusRestorationStack()

        let old = EditorFocusSnapshot.widgetDefault
        let new = EditorFocusSnapshot.smartRuleEditor(albumID: "unitTest.album")

        stack.recordFocusChange(old: old, new: new)

        XCTAssertEqual(stack.entries.count, 1)
        XCTAssertEqual(stack.entries.first?.targetFocus, new.focus)
        XCTAssertEqual(stack.entries.first?.previousSnapshot, old)
    }

    func testLeavingTrackedFocusPopsStackEntry() {
        var stack = EditorFocusRestorationStack()

        let old = EditorFocusSnapshot.widgetDefault
        let tracked = EditorFocusSnapshot.smartRuleEditor(albumID: "unitTest.album")

        stack.recordFocusChange(old: old, new: tracked)
        XCTAssertEqual(stack.entries.count, 1)

        stack.recordFocusChange(old: tracked, new: old)
        XCTAssertTrue(stack.entries.isEmpty)
    }

    func testRestoreAfterTeardownRestoresPreviousSnapshotAndClearsEntry() {
        var stack = EditorFocusRestorationStack()

        let old = EditorFocusSnapshot.widgetDefault
        let tracked = EditorFocusSnapshot.smartRuleEditor(albumID: "unitTest.album")

        stack.recordFocusChange(old: old, new: tracked)
        XCTAssertEqual(stack.entries.count, 1)

        let restored = stack.restoreFocusAfterTeardown(currentFocusSnapshot: tracked)
        XCTAssertEqual(restored, old)
        XCTAssertTrue(stack.entries.isEmpty)
    }

    func testRestoreAfterTeardownReturnsNilForNonTrackedFocus() {
        var stack = EditorFocusRestorationStack()
        XCTAssertNil(stack.restoreFocusAfterTeardown(currentFocusSnapshot: .widgetDefault))
        XCTAssertTrue(stack.entries.isEmpty)
    }

    func testClockFocusIsTrackedAndRestoresPreviousSnapshot() {
        var stack = EditorFocusRestorationStack()

        let old = EditorFocusSnapshot.singleNonAlbumElement(id: "unitTest.element")
        let tracked = EditorFocusSnapshot.clockFocus()

        stack.recordFocusChange(old: old, new: tracked)
        XCTAssertEqual(stack.entries.count, 1)

        let restored = stack.restoreFocusAfterTeardown(currentFocusSnapshot: tracked)
        XCTAssertEqual(restored, old)
        XCTAssertTrue(stack.entries.isEmpty)
    }

    func testNestedTrackedFocusRestoresOneLevelAtATime() {
        var stack = EditorFocusRestorationStack()

        let root = EditorFocusSnapshot.widgetDefault
        let picker = EditorFocusSnapshot.smartAlbumContainer(id: "smartPhotoAlbumPicker")
        let crop = EditorFocusSnapshot.singleNonAlbumElement(id: "smartPhotoCrop")

        stack.recordFocusChange(old: root, new: picker)
        stack.recordFocusChange(old: picker, new: crop)

        XCTAssertEqual(stack.entries.count, 2)

        let restoredFromCrop = stack.restoreFocusAfterTeardown(currentFocusSnapshot: crop)
        XCTAssertEqual(restoredFromCrop, picker)
        XCTAssertEqual(stack.entries.count, 1)

        let restoredFromPicker = stack.restoreFocusAfterTeardown(currentFocusSnapshot: picker)
        XCTAssertEqual(restoredFromPicker, root)
        XCTAssertTrue(stack.entries.isEmpty)
    }
}
