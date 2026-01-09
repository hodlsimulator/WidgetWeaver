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
