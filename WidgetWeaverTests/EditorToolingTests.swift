//
//  EditorToolingTests.swift
//  WidgetWeaverEditorTooling
//
//  Created by . . on 1/7/26.
//

import XCTest
@testable import WidgetWeaverEditorTooling

final class EditorToolingTests: XCTestCase {

    // MARK: - Capabilities

    func testCapabilities_classicTemplate() {
        let ctx = EditorToolContext(
            template: .classic,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .none,
            focus: .widget,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .denied),
            hasSymbolConfigured: false,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let caps = EditorToolRegistry.capabilities(for: ctx)

        XCTAssertTrue(caps.contains(.canEditLayout))
        XCTAssertTrue(caps.contains(.canEditTextContent))
        XCTAssertTrue(caps.contains(.canEditSymbol))
        XCTAssertTrue(caps.contains(.canEditTypography))
        XCTAssertTrue(caps.contains(.canEditActions))

        XCTAssertFalse(caps.contains(.canEditImage))
        XCTAssertFalse(caps.contains(.canEditSmartPhoto))
        XCTAssertFalse(caps.contains(.canEditAlbumShuffle))
        XCTAssertFalse(caps.contains(.canAccessPhotoLibrary))
        XCTAssertFalse(caps.contains(.hasImageConfigured))
        XCTAssertFalse(caps.contains(.hasSmartPhotoConfigured))
        XCTAssertFalse(caps.contains(.canUseAI))
    }

    func testCapabilities_posterTemplate_withPhotosAccessAndSmartPhoto() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: true,
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
        XCTAssertTrue(caps.contains(.canEditSymbol))
        XCTAssertTrue(caps.contains(.canEditImage))
        XCTAssertTrue(caps.contains(.canEditSmartPhoto))
        XCTAssertTrue(caps.contains(.canEditAlbumShuffle))
        XCTAssertTrue(caps.contains(.canAccessPhotoLibrary))
        XCTAssertTrue(caps.contains(.hasImageConfigured))
        XCTAssertTrue(caps.contains(.hasSmartPhotoConfigured))
        XCTAssertTrue(caps.contains(.canEditTypography))
        XCTAssertTrue(caps.contains(.canUseAI))
    }

    // MARK: - Visible tools

    func testVisibleTools_classic_widgetFocus_noSelection() {
        let ctx = EditorToolContext(
            template: .classic,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .none,
            focus: .widget,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .denied),
            hasSymbolConfigured: false,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertEqual(
            tools,
            [
                .status,
                .designs,
                .widgets,
                .layout,
                .text,
                .symbol,
                .style,
                .typography,
                .actions,
                .matchedSet,
                .variables,
                .sharing,
                .pro
            ]
        )
    }

    func testVisibleTools_multiSelection_reducesSingleTargetTools() {
        let ctx = EditorToolContext(
            template: .classic,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .multi,
            focus: .widget,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .denied),
            hasSymbolConfigured: false,
            hasImageConfigured: false,
            hasSmartPhotoConfigured: false
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertEqual(
            tools,
            [
                .status,
                .designs,
                .widgets,
                .layout,
                .style,
                .matchedSet,
                .variables,
                .sharing,
                .pro
            ]
        )
    }

    func testVisibleTools_smartPhotosFocus_prioritisesSmartPhotoSuite() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .none,
            focus: .albumContainer(id: "album1", subtype: .smart),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertEqual(
            tools,
            [
                .albumShuffle,
                .smartPhotoCrop,
                .smartPhoto,
                .image,
                .smartRules,
                .style
            ]
        )
    }

    func testVisibleTools_smartPhotosFocus_hidesAlbumShuffleWithoutPhotosAccess() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: false,
            matchedSetEnabled: false,
            selection: .none,
            focus: .albumContainer(id: "album1", subtype: .smart),
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .denied),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertEqual(
            tools,
            [
                .smartPhotoCrop,
                .smartPhoto,
                .image,
                .smartRules,
                .style
            ]
        )
    }

    func testVisibleTools_clockFocus_isAllowlisted() {
        let ctx = EditorToolContext(
            template: .poster,
            isProUnlocked: true,
            matchedSetEnabled: false,
            selection: .none,
            focus: .clock,
            photoLibraryAccess: EditorPhotoLibraryAccess(status: .authorised),
            hasSymbolConfigured: false,
            hasImageConfigured: true,
            hasSmartPhotoConfigured: true
        )

        let tools = EditorToolRegistry.visibleTools(for: ctx)

        XCTAssertEqual(
            tools,
            [
                .status,
                .designs,
                .widgets,
                .layout,
                .style,
                .matchedSet,
                .variables,
                .sharing,
                .ai,
                .pro
            ]
        )
    }

    // MARK: - Teardown hooks

    func testTeardown_dismissesAlbumShufflePickerWhenToolDisappears() {
        let oldTools: [EditorToolID] = [.albumShuffle, .smartPhoto, .style]
        let newTools: [EditorToolID] = [.smartPhoto, .style]

        let actions = editorToolTeardownActions(
            old: oldTools,
            new: newTools,
            currentFocus: .albumContainer(id: "smartPhotoAlbumPicker", subtype: .smart)
        )

        XCTAssertEqual(actions, [.dismissAlbumShufflePicker, .resetEditorFocusToWidgetDefault])
    }

    func testTeardown_resetsSmartRulesEditorFocusWhenToolDisappears() {
        let oldTools: [EditorToolID] = [.smartRules, .smartPhoto, .style]
        let newTools: [EditorToolID] = [.smartPhoto, .style]

        let actions = editorToolTeardownActions(
            old: oldTools,
            new: newTools,
            currentFocus: .smartRuleEditor(albumID: "album1")
        )

        XCTAssertEqual(actions, [.resetEditorFocusToWidgetDefault])
    }

    func testTeardown_resetsSmartPhotoCropFocusWhenToolDisappears() {
        let oldTools: [EditorToolID] = [.smartPhotoCrop, .smartPhoto, .style]
        let newTools: [EditorToolID] = [.smartPhoto, .style]

        let actions = editorToolTeardownActions(
            old: oldTools,
            new: newTools,
            currentFocus: .element(id: "smartPhotoCrop")
        )

        XCTAssertEqual(actions, [.resetEditorFocusToWidgetDefault])
    }

    func testTeardown_resetsSmartPhotosFocusGroupWhenNoPrimaryToolsRemain() {
        let oldTools: [EditorToolID] = [.smartPhoto, .style]
        let newTools: [EditorToolID] = [.style]

        let actions = editorToolTeardownActions(
            old: oldTools,
            new: newTools,
            currentFocus: .albumContainer(id: "album1", subtype: .smart)
        )

        XCTAssertEqual(actions, [.resetEditorFocusToWidgetDefault])
    }

    func testTeardown_resetsClockFocusWhenNoPrimaryToolsRemain() {
        let oldTools: [EditorToolID] = [.layout, .style]
        let newTools: [EditorToolID] = [.status]

        let actions = editorToolTeardownActions(
            old: oldTools,
            new: newTools,
            currentFocus: .clock
        )

        XCTAssertEqual(actions, [.resetEditorFocusToWidgetDefault])
    }
}
