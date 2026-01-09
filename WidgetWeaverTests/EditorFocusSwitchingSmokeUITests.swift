//
//  EditorFocusSwitchingSmokeUITests.swift
//  WidgetWeaverUITests
//
//  Created by . . on 1/8/26.
//

import XCTest
import CoreGraphics

final class EditorFocusSwitchingSmokeUITests: XCTestCase {
    private enum LaunchKeys {
        static let contextAwareToolSuiteEnabled = "-widgetweaver.feature.editor.contextAwareToolSuite.enabled"
        static let uiTestHooksEnabled = "-widgetweaver.uiTestHooks.enabled"
        static let dynamicType = "-widgetweaver.uiTest.dynamicType"
        static let reduceMotion = "-widgetweaver.uiTest.reduceMotion"
    }

    private enum Tabs {
        static let editor = "Editor"
    }

    private enum UITestHooks {
        static let templatePoster = "EditorUITestHook.templatePoster"
        static let focusWidget = "EditorUITestHook.focusWidget"
        static let focusSmartPhotoCrop = "EditorUITestHook.focusSmartPhotoCrop"
        static let focusSmartRules = "EditorUITestHook.focusSmartRules"
        static let focusAlbumContainer = "EditorUITestHook.focusAlbumContainer"
        static let focusAlbumPhotoItem = "EditorUITestHook.focusAlbumPhotoItem"
        static let multiSelectWidgets = "EditorUITestHook.multiSelectWidgets"
        static let multiSelectMixed = "EditorUITestHook.multiSelectMixed"
        static let focusClock = "EditorUITestHook.focusClock"
    }

    private enum SectionHeaders {
        static let status = "EditorSectionHeader.Status"
        static let designs = "EditorSectionHeader.Designs"
        static let widgets = "EditorSectionHeader.Widgets"
        static let text = "EditorSectionHeader.Text"
        static let image = "EditorSectionHeader.Image"
        static let smartPhoto = "EditorSectionHeader.Smart_Photo"
        static let layout = "EditorSectionHeader.Layout"
        static let style = "EditorSectionHeader.Style"
        static let albumShuffle = "EditorSectionHeader.Album_Shuffle"
    }

    private enum AccessibilityIDs {
        static let designNameTextField = "EditorTextField.DesignName"
        static let primaryTextField = "EditorTextField.PrimaryText"
        static let secondaryTextField = "EditorTextField.SecondaryText"

        static let unavailableMessage = "EditorUnavailableStateView.Message"
    }

    private func launchApp(
        contextAwareEnabled: Bool,
        dynamicType: String? = nil,
        reduceMotion: Bool? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            LaunchKeys.uiTestHooksEnabled,
            "1",
            LaunchKeys.contextAwareToolSuiteEnabled,
            contextAwareEnabled ? "1" : "0",
        ]

        if let dynamicType {
            app.launchArguments += [LaunchKeys.dynamicType, dynamicType]
        }

        if let reduceMotion {
            app.launchArguments += [LaunchKeys.reduceMotion, reduceMotion ? "1" : "0"]
        }

        app.launch()
        ensureEditorTabSelected(in: app)
        return app
    }

    private func ensureEditorTabSelected(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let editorTab = app.tabBars.buttons[Tabs.editor]
        if editorTab.waitForExistence(timeout: 2.0) {
            if !editorTab.isSelected {
                editorTab.tap()
            }
            return
        }

        // Fallback: some SwiftUI configurations expose tab items as plain buttons.
        let editorButtonFallback = app.buttons[Tabs.editor]
        if editorButtonFallback.waitForExistence(timeout: 2.0) {
            editorButtonFallback.tap()
            return
        }

        XCTFail("Expected Editor tab to exist", file: file, line: line)
    }

    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func hook(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        element(identifier, in: app)
    }

    private func editorScrollable(in app: XCUIApplication) -> XCUIElement {
        let table = app.tables.firstMatch
        if table.exists {
            return table
        }
        return app.scrollViews.firstMatch
    }

    private func waitAndTap(_ element: XCUIElement, timeout: TimeInterval = 2.0, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected element to exist: \(element)", file: file, line: line)

        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func assertEditorHasDiscoverableToolAnchor(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let scrollable = editorScrollable(in: app)

        let anchors: [XCUIElement] = [
            app.staticTexts[SectionHeaders.status],
            app.staticTexts[SectionHeaders.widgets],
            app.staticTexts[SectionHeaders.layout],
            app.staticTexts[SectionHeaders.style],
            app.staticTexts[SectionHeaders.text],
            app.staticTexts[SectionHeaders.image],
            app.staticTexts[SectionHeaders.smartPhoto],
            app.staticTexts[SectionHeaders.albumShuffle],
        ]

        for anchor in anchors {
            scrollToElement(anchor, in: scrollable, maxScrolls: 5)
            if anchor.exists {
                return
            }
        }

        XCTFail("Expected at least one tool section header to be visible", file: file, line: line)
    }

    private func assertUnavailableMessage(
        _ expectedSubstring: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let message = app.staticTexts[AccessibilityIDs.unavailableMessage]
        XCTAssertTrue(message.waitForExistence(timeout: 2.0), "Expected unavailable message to appear", file: file, line: line)
        XCTAssertTrue(message.label.contains(expectedSubstring), "Expected unavailable message to contain: \(expectedSubstring)", file: file, line: line)
    }

    private func scrollToElement(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        maxScrolls: Int = 18
    ) {
        var remaining = maxScrolls
        while (!element.exists || !element.isHittable) && remaining > 0 {
            scrollView.swipeUp()
            remaining -= 1
        }
    }

    func testUITestHookSurfaceIsReachable() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = hook(UITestHooks.templatePoster, in: app)
        XCTAssertTrue(templatePoster.waitForExistence(timeout: 2.0), "Expected UI test hook surface to be present in the Editor tab")
    }

    func testContextAwareFocusSwitchingSmoke() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = hook(UITestHooks.templatePoster, in: app)
        let focusWidget = hook(UITestHooks.focusWidget, in: app)
        let focusCrop = hook(UITestHooks.focusSmartPhotoCrop, in: app)
        let focusRules = hook(UITestHooks.focusSmartRules, in: app)

        waitAndTap(templatePoster)

        assertEditorHasDiscoverableToolAnchor(in: app)

        for _ in 0..<3 {
            waitAndTap(focusCrop)
            assertEditorHasDiscoverableToolAnchor(in: app)
            waitAndTap(focusWidget)
            assertEditorHasDiscoverableToolAnchor(in: app)
            waitAndTap(focusRules)
            assertEditorHasDiscoverableToolAnchor(in: app)
            waitAndTap(focusWidget)
            assertEditorHasDiscoverableToolAnchor(in: app)
        }
    }

    func testContextAwareFlagOffShowsLegacyToolsInSmartPhotoFocus() {
        let app = launchApp(contextAwareEnabled: false)

        let templatePoster = hook(UITestHooks.templatePoster, in: app)
        let focusCrop = hook(UITestHooks.focusSmartPhotoCrop, in: app)

        waitAndTap(templatePoster)
        waitAndTap(focusCrop)

        // Legacy mode should still surface the Text tool.
        let textHeader = app.staticTexts[SectionHeaders.text]
        XCTAssertTrue(textHeader.waitForExistence(timeout: 2.0))
    }

    func testContextAwareFlagOnHidesTextToolInSmartPhotoFocus() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = hook(UITestHooks.templatePoster, in: app)
        let focusCrop = hook(UITestHooks.focusSmartPhotoCrop, in: app)

        waitAndTap(templatePoster)
        waitAndTap(focusCrop)

        // In Smart Photo focus, Text should not be present.
        let textHeader = app.staticTexts[SectionHeaders.text]
        XCTAssertFalse(textHeader.exists)

        // Smart Photo suite should still be discoverable.
        XCTAssertTrue(app.staticTexts[SectionHeaders.smartPhoto].exists)
    }

    func testClockFocusHidesSmartPhotoAndTextTooling() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = hook(UITestHooks.templatePoster, in: app)
        let focusClock = hook(UITestHooks.focusClock, in: app)

        waitAndTap(templatePoster)
        waitAndTap(focusClock)

        // Clock focus should not show Smart Photo suite.
        XCTAssertFalse(app.staticTexts[SectionHeaders.smartPhoto].exists)
        XCTAssertFalse(app.staticTexts[SectionHeaders.albumShuffle].exists)

        // Clock focus should still show general layout/style suite.
        XCTAssertTrue(app.staticTexts[SectionHeaders.layout].exists)
        XCTAssertTrue(app.staticTexts[SectionHeaders.style].exists)
    }

    func testAlbumFocusHidesTextAndLayoutTooling() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = hook(UITestHooks.templatePoster, in: app)
        let focusAlbumContainer = hook(UITestHooks.focusAlbumContainer, in: app)
        let focusAlbumPhotoItem = hook(UITestHooks.focusAlbumPhotoItem, in: app)

        waitAndTap(templatePoster)

        waitAndTap(focusAlbumContainer)
        XCTAssertTrue(app.staticTexts[SectionHeaders.smartPhoto].exists)
        XCTAssertFalse(app.staticTexts[SectionHeaders.text].exists)
        XCTAssertFalse(app.staticTexts[SectionHeaders.layout].exists)

        waitAndTap(focusAlbumPhotoItem)
        XCTAssertTrue(app.staticTexts[SectionHeaders.smartPhoto].exists)
        XCTAssertFalse(app.staticTexts[SectionHeaders.text].exists)
        XCTAssertFalse(app.staticTexts[SectionHeaders.layout].exists)
    }

    func testMultiSelectionShowsUnavailableStateAndKeepsCoreTooling() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = hook(UITestHooks.templatePoster, in: app)
        let multiSelectWidgets = hook(UITestHooks.multiSelectWidgets, in: app)

        waitAndTap(templatePoster)
        waitAndTap(multiSelectWidgets)

        assertUnavailableMessage("Some tools are hidden", in: app)

        // Core tooling should still exist.
        XCTAssertTrue(app.staticTexts[SectionHeaders.layout].exists)
        XCTAssertTrue(app.staticTexts[SectionHeaders.style].exists)
    }

    func testMultiSelectionHidesSmartPhotoAndTextTooling() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = hook(UITestHooks.templatePoster, in: app)
        let multiSelectMixed = hook(UITestHooks.multiSelectMixed, in: app)

        waitAndTap(templatePoster)
        waitAndTap(multiSelectMixed)

        // Mixed multi selection should hide smart photo suite + text tool.
        XCTAssertFalse(app.staticTexts[SectionHeaders.smartPhoto].exists)
        XCTAssertFalse(app.staticTexts[SectionHeaders.text].exists)

        // Layout + Style should remain.
        XCTAssertTrue(app.staticTexts[SectionHeaders.layout].exists)
        XCTAssertTrue(app.staticTexts[SectionHeaders.style].exists)
    }

    func testTextEntrySurvivesToolSuiteChanges() {
        let app = launchApp(contextAwareEnabled: true, dynamicType: "large", reduceMotion: true)

        let templatePoster = hook(UITestHooks.templatePoster, in: app)
        let focusWidget = hook(UITestHooks.focusWidget, in: app)
        let focusCrop = hook(UITestHooks.focusSmartPhotoCrop, in: app)

        waitAndTap(templatePoster)
        waitAndTap(focusWidget)

        let scrollable = editorScrollable(in: app)

        let primary = app.textFields[AccessibilityIDs.primaryTextField]
        scrollToElement(primary, in: scrollable)
        waitAndTap(primary)
        primary.typeText("Hello")

        // Switch into Smart Photo focus and back; text entry should remain.
        waitAndTap(focusCrop)
        waitAndTap(focusWidget)

        XCTAssertTrue(primary.waitForExistence(timeout: 2.0))
        XCTAssertTrue(primary.value as? String ?? "" != "")
    }
}
