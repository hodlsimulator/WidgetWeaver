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

    func testMixedDisallowedPresetDisallowsMixedSelectionDescriptor() {
        let eligibility = EditorToolEligibility.multiSafe(selectionDescriptor: .mixedDisallowed)

        let descriptor = EditorSelectionDescriptor.describe(
            selection: .multi,
            focus: .widget
        )

        XCTAssertFalse(eligibility.selectionDescriptor.allows(descriptor))
    }

    func testMixedAllowedPresetAllowsMixedSelectionDescriptor() {
        let eligibility = EditorToolEligibility.multiSafe(selectionDescriptor: .mixedAllowed)

        let descriptor = EditorSelectionDescriptor.describe(
            selection: .multi,
            focus: .widget
        )

        XCTAssertTrue(eligibility.selectionDescriptor.allows(descriptor))
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

        let rulesCtx = EditorToolContext(
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

        let cropTools = EditorToolRegistry.visibleTools(for: cropCtx)
            .filter { $0 != .smartRules }
        let rulesTools = EditorToolRegistry.visibleTools(for: rulesCtx)
            .filter { $0 != .smartRules }

        assertRelativeOrderStable(cropTools, rulesTools)
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

    func testToolOrderRemainsStableBetweenWidgetAndClockFocus() {
        let widgetCtx = EditorToolContext(
            template: .hero,
            isProUnlocked: true,
            matchedSetEnabled: false,
            selection: .none,
            focus: .widget,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: true,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let clockCtx = EditorToolContext(
            template: .hero,
            isProUnlocked: true,
            matchedSetEnabled: false,
            selection: .single,
            focus: .clock,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: true,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let widgetTools = EditorToolRegistry.visibleTools(for: widgetCtx)
        let clockTools = EditorToolRegistry.visibleTools(for: clockCtx)

        assertRelativeOrderStable(widgetTools, clockTools)
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

    func testLegacyVisibleToolsIgnoreAvailabilityRequirements() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .none,
            focus: .widget,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .notDetermined),
            hasSymbolConfigured: false,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let contextAware = EditorToolRegistry.visibleTools(for: ctx)
        let legacy = EditorToolRegistry.legacyVisibleTools(for: ctx)

        XCTAssertFalse(contextAware.contains(.smartPhotoCrop))
        XCTAssertFalse(contextAware.contains(.smartRules))
        XCTAssertFalse(contextAware.contains(.albumShuffle))

        XCTAssertTrue(legacy.contains(.smartPhotoCrop))
        XCTAssertTrue(legacy.contains(.smartRules))
        XCTAssertTrue(legacy.contains(.albumShuffle))
    }

    func testLegacyVisibleToolsIgnorePhotosPermissionRequirements() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .widget,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .denied),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let contextAware = EditorToolRegistry.visibleTools(for: ctx)
        let legacy = EditorToolRegistry.legacyVisibleTools(for: ctx)

        XCTAssertFalse(contextAware.contains(.albumShuffle))
        XCTAssertTrue(legacy.contains(.albumShuffle))
    }

    // MARK: - Selection origin coverage

    func testSmartAlbumContainerFocusUsesSmartPhotoAllowlist() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .albumContainer(id: "uiTest.albumContainer", subtype: .smart),
            selectionCount: 1,
            selectionComposition: .known([.albumContainer]),
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
    }

    func testSmartAlbumPhotoItemFocusHidesAlbumLevelTools() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .single,
            focus: .albumPhoto(albumID: "uiTest.album", itemID: "uiTest.photo", subtype: .smart),
            selectionCount: 1,
            selectionComposition: .known([.albumPhotoItem]),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertEqual(
            tools,
            [.smartPhotoCrop, .smartPhoto, .image, .style]
        )
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
            [.status, .designs, .widgets, .layout, .style, .matchedSet, .variables, .sharing, .pro]
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


    func testContextEvaluatorPrefersExplicitOriginSelectionCountOverFallback() {
        var draft = FamilyDraft.defaultDraft
        draft.template = .poster

        let originFocus = EditorFocusSnapshot(
            selection: .none,
            focus: .widget,
            selectionCount: 5,
            selectionComposition: .unknown
        )

        let fallbackFocus = EditorFocusSnapshot(
            selection: .none,
            focus: .widget,
            selectionCount: 1,
            selectionComposition: .unknown
        )

        let ctx = EditorContextEvaluator.evaluate(
            draft: draft,
            isProUnlocked: false,
            matchedSetEnabled: false,
            originFocus: originFocus,
            fallbackFocus: fallbackFocus,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised)
        )

        XCTAssertEqual(ctx.selection, .multi)
        XCTAssertEqual(ctx.selectionCount, 5)
    }

    func testContextEvaluatorUsesFallbackSelectionCountWhenOriginSelectionCountIsMissing() {
        var draft = FamilyDraft.defaultDraft
        draft.template = .poster

        let originFocus = EditorFocusSnapshot(
            selection: .multi,
            focus: .widget,
            selectionCount: nil,
            selectionComposition: .unknown
        )

        let fallbackFocus = EditorFocusSnapshot(
            selection: .multi,
            focus: .widget,
            selectionCount: 4,
            selectionComposition: .unknown
        )

        let ctx = EditorContextEvaluator.evaluate(
            draft: draft,
            isProUnlocked: false,
            matchedSetEnabled: false,
            originFocus: originFocus,
            fallbackFocus: fallbackFocus,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised)
        )

        XCTAssertEqual(ctx.selection, .multi)
        XCTAssertEqual(ctx.selectionCount, 4)
    }

    func testContextEvaluatorPrefersExplicitOriginCompositionOverFallback() {
        var draft = FamilyDraft.defaultDraft
        draft.template = .poster

        let originFocus = EditorFocusSnapshot(
            selection: .multi,
            focus: .widget,
            selectionCount: 3,
            selectionComposition: .known([.albumContainer, .nonAlbum])
        )

        let fallbackFocus = EditorFocusSnapshot(
            selection: .multi,
            focus: .widget,
            selectionCount: 3,
            selectionComposition: .known([.nonAlbum])
        )

        let ctx = EditorContextEvaluator.evaluate(
            draft: draft,
            isProUnlocked: false,
            matchedSetEnabled: false,
            originFocus: originFocus,
            fallbackFocus: fallbackFocus,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised)
        )

        XCTAssertEqual(ctx.selectionComposition, originFocus.selectionComposition)
    }

    func testContextEvaluatorUsesFallbackCompositionWhenOriginCompositionIsUnknown() {
        var draft = FamilyDraft.defaultDraft
        draft.template = .poster

        let originFocus = EditorFocusSnapshot(
            selection: .multi,
            focus: .widget,
            selectionCount: 3,
            selectionComposition: .unknown
        )

        let fallbackFocus = EditorFocusSnapshot(
            selection: .multi,
            focus: .widget,
            selectionCount: 3,
            selectionComposition: .known([.nonAlbum])
        )

        let ctx = EditorContextEvaluator.evaluate(
            draft: draft,
            isProUnlocked: false,
            matchedSetEnabled: false,
            originFocus: originFocus,
            fallbackFocus: fallbackFocus,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised)
        )

        XCTAssertEqual(ctx.selectionComposition, .known([.nonAlbum]))
    }

    // MARK: - Performance guard

    func testContextEvaluationAndToolFilteringPerformanceGuard() {
        var draft = FamilyDraft.defaultDraft
        draft.template = .poster
        draft.imageFileName = "unitTest.png"
        draft.imageSmartPhoto = SmartPhotoSpec(
            masterFileName: "unitTest-master.png",
            small: nil,
            medium: nil,
            large: nil,
            algorithmVersion: 1,
            preparedAt: Date(timeIntervalSince1970: 0)
        )

        let focus = EditorFocusSnapshot.singleNonAlbumElement(id: "smartPhotoCrop")
        let photoAccess = EditorPhotoLibraryAccess(status: .authorised)

        let iterations = 10_000
        let start = CFAbsoluteTimeGetCurrent()
        var lastTools: [EditorToolID] = []

        for _ in 0..<iterations {
            let ctx = EditorContextEvaluator.evaluate(
                draft: draft,
                isProUnlocked: false,
                matchedSetEnabled: false,
                focus: focus,
                photoLibraryAccess: photoAccess
            )
            lastTools = EditorToolRegistry.visibleTools(for: ctx)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertFalse(lastTools.isEmpty)
        XCTAssertLessThan(elapsed, 2.0, "Context evaluation + tool filtering took too long: \(elapsed)s for \(iterations) iterations")
    }

    // MARK: - Teardown

    func testTeardownActionsFireWhenRequiredToolDisappearsForAlbumPickerFocus() {
        let actions = editorToolTeardownActions(
            old: [.albumShuffle, .style],
            new: [.style],
            currentFocus: .albumContainer(id: "smartPhotoAlbumPicker", subtype: .smart)
        )

        XCTAssertEqual(
            Set(actions),
            Set([.dismissAlbumShufflePicker, .resetEditorFocusToWidgetDefault])
        )
    }

    func testTeardownActionsResetClockFocusIfWidgetsToolDisappears() {
        let actions = editorToolTeardownActions(
            old: [.widgets, .layout, .style],
            new: [.layout, .style],
            currentFocus: .clock
        )

        XCTAssertEqual(
            Set(actions),
            Set([.resetEditorFocusToWidgetDefault])
        )
    }

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
