//
//  EditorToolingTests.swift
//  WidgetWeaverTests
//
//  Created by . . on 1/8/26.
//

import Foundation
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
        XCTAssertTrue(caps.contains(.canUseAI))
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

    // MARK: - Selection descriptor

    func testSelectionDescriptorDerivesSingleFromFocusWhenSelectionIsNone() {
        let descriptor = EditorSelectionDescriptor.describe(
            selection: .none,
            focus: .clock
        )

        XCTAssertEqual(descriptor.kind, .single)
        XCTAssertEqual(descriptor.count, 1)
        XCTAssertEqual(descriptor.homogeneity, .homogeneous)
        XCTAssertEqual(descriptor.albumSpecificity, .nonAlbum)
    }

    func testSelectionDescriptorMarksMultiWidgetSelectionAsMixed() {
        let descriptor = EditorSelectionDescriptor.describe(
            selection: .multi,
            focus: .widget
        )

        XCTAssertEqual(descriptor.kind, .multi)
        XCTAssertEqual(descriptor.count, 2)
        XCTAssertEqual(descriptor.homogeneity, .mixed)
        XCTAssertEqual(descriptor.albumSpecificity, .mixed)
    }

    func testToolManifestHasUniqueIDs() {
        let ids = EditorToolRegistry.tools.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testToolManifestIsSortedByOrder() {
        let tools = EditorToolRegistry.toolsSortedByOrder.map(\.order)
        XCTAssertEqual(tools, tools.sorted())
    }

    func testToolManifestMixedSelectionPolicyIsExplicit() {
        let mixedDescriptor = EditorSelectionDescriptor.describe(
            selection: .multi,
            focus: .widget
        )

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

        let actualMixedAllowed = Set(
            EditorToolRegistry.tools
                .filter { $0.eligibility.selectionDescriptor.allows(mixedDescriptor) }
                .map(\.id)
        )

        XCTAssertEqual(actualMixedAllowed, expectedMixedAllowed)
    }

    func testSelectionDescriptorUsesExplicitCompositionAndCountWhenProvided() {
        let descriptor = EditorSelectionDescriptor.describe(
            selection: .multi,
            focus: .widget,
            selectionCount: 4,
            composition: .known([.albumContainer])
        )

        XCTAssertEqual(descriptor.kind, .multi)
        XCTAssertEqual(descriptor.count, 4)
        XCTAssertEqual(descriptor.homogeneity, .homogeneous)
        XCTAssertEqual(descriptor.albumSpecificity, .albumContainer)
    }

    func testSelectionDescriptorExplicitMixedCompositionWinsOverWidgetHeuristic() {
        let descriptor = EditorSelectionDescriptor.describe(
            selection: .multi,
            focus: .widget,
            selectionCount: 4,
            composition: .known([.albumContainer, .nonAlbum])
        )

        XCTAssertEqual(descriptor.kind, .multi)
        XCTAssertEqual(descriptor.count, 4)
        XCTAssertEqual(descriptor.homogeneity, .mixed)
        XCTAssertEqual(descriptor.albumSpecificity, .mixed)
    }

    func testSelectionDescriptorAlbumContainerFocusIsAlbumSpecific() {
        let descriptor = EditorSelectionDescriptor.describe(
            selection: .none,
            focus: .albumContainer(id: "smartPhotoAlbumPicker", subtype: .smart)
        )

        XCTAssertEqual(descriptor.kind, .single)
        XCTAssertEqual(descriptor.homogeneity, .homogeneous)
        XCTAssertEqual(descriptor.albumSpecificity, .albumContainer)
    }

    // MARK: - Visible tool derivation

    func testVisibleToolsSmartPhotoCropFocusIsPrioritisedSmartPhotoSuite() {
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
            [.albumShuffle, .smartPhotoCrop, .smartPhoto, .image, .smartRules, .style]
        )

        XCTAssertFalse(tools.contains(.layout))
        XCTAssertFalse(tools.contains(.text))
        XCTAssertFalse(tools.contains(.typography))
    }

    func testVisibleToolsSmartRuleEditorPinsSmartRulesFirst() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .smartRuleEditor(albumID: "album"),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertEqual(
            tools,
            [.smartRules, .albumShuffle, .smartPhotoCrop, .smartPhoto, .image, .style]
        )

        XCTAssertFalse(tools.contains(.layout))
        XCTAssertFalse(tools.contains(.actions))
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

    func testToolOrderRemainsStableAcrossSmartPhotoFocusSwitches() {
        let cropCtx = EditorToolContext(
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

        let elementCtx = EditorToolContext(
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

        let cropTools = EditorToolRegistry.visibleTools(for: cropCtx)
        let elementTools = EditorToolRegistry.visibleTools(for: elementCtx)

        assertRelativeOrderStable(cropTools, elementTools)
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
        XCTAssertFalse(tools.contains(.albumShuffle))
        XCTAssertFalse(tools.contains(.smartRules))

        XCTAssertFalse(tools.contains(.actions))
    }

    func testToolOrderRemainsStableBetweenWidgetAndClockFocus() {
        let widgetCtx = EditorToolContext(
            template: .classic,
            isProUnlocked: true,
            matchedSetEnabled: false,
            selection: .single,
            focus: .widget,
            selectionCount: 1,
            selectionComposition: .known([.nonAlbum]),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: true,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let clockCtx = EditorToolContext(
            template: .classic,
            isProUnlocked: true,
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

        let widgetTools = EditorToolRegistry.visibleTools(for: widgetCtx)
        let clockTools = EditorToolRegistry.visibleTools(for: clockCtx)

        assertRelativeOrderStable(widgetTools, clockTools)
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

    func testContextEvaluatorResolvesSelectionKindFromSelectionCount() {
        var draft = FamilyDraft.defaultDraft
        draft.template = .poster

        let focus = EditorFocusSnapshot(
            selection: .none,
            focus: .widget,
            selectionCount: 3,
            selectionComposition: .unknown
        )

        let ctx = EditorContextEvaluator.evaluate(
            draft: draft,
            isProUnlocked: false,
            matchedSetEnabled: false,
            focus: focus,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised)
        )

        XCTAssertEqual(ctx.selection, .multi)
        XCTAssertEqual(ctx.selectionCount, 3)
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

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<10_000 {
            _ = EditorToolRegistry.visibleTools(for: ctx)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 0.25)
    }

    // MARK: - Helpers

    private func assertRelativeOrderStable(
        _ a: [EditorToolID],
        _ b: [EditorToolID],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let common = a.filter { b.contains($0) }
        let commonInB = b.filter { common.contains($0) }
        XCTAssertEqual(common, commonInB, file: file, line: line)
    }
}
