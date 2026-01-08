//
//  EditorFocusSwitchingSmokeUITests.swift
//  WidgetWeaverUITests
//
//  Created by . . on 1/8/26.
//

import XCTest

final class EditorFocusSwitchingSmokeUITests: XCTestCase {
    private enum LaunchKeys {
        static let contextAwareToolSuiteEnabled = "-widgetweaver.feature.editor.contextAwareToolSuite.enabled"
        static let uiTestHooksEnabled = "-widgetweaver.uiTestHooks.enabled"
        static let dynamicType = "-widgetweaver.uiTest.dynamicType"
        static let reduceMotion = "-widgetweaver.uiTest.reduceMotion"
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
        static let text = "EditorSectionHeader.Text"
        static let smartPhoto = "EditorSectionHeader.Smart_Photo"
        static let layout = "EditorSectionHeader.Layout"
    }

    private enum AccessibilityIDs {
        static let designNameTextField = "EditorTextField.DesignName"
        static let primaryTextField = "EditorTextField.PrimaryText"
        static let secondaryTextField = "EditorTextField.SecondaryText"
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
        return app
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
        element.tap()
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

    func testContextAwareFocusSwitchingSmoke() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = app.buttons[UITestHooks.templatePoster]
        let focusWidget = app.buttons[UITestHooks.focusWidget]
        let focusCrop = app.buttons[UITestHooks.focusSmartPhotoCrop]
        let focusRules = app.buttons[UITestHooks.focusSmartRules]

        waitAndTap(templatePoster)

        for _ in 0..<3 {
            waitAndTap(focusCrop)
            waitAndTap(focusWidget)
            waitAndTap(focusRules)
            waitAndTap(focusWidget)
        }
    }

    func testContextAwareFocusSwitchingSmokeUnderLargeDynamicTypeAndReduceMotion() {
        let app = launchApp(
            contextAwareEnabled: true,
            dynamicType: "accessibility3",
            reduceMotion: true
        )

        let templatePoster = app.buttons[UITestHooks.templatePoster]
        let focusWidget = app.buttons[UITestHooks.focusWidget]
        let focusCrop = app.buttons[UITestHooks.focusSmartPhotoCrop]

        waitAndTap(templatePoster)

        // Minimal smoke: ensure tool switches do not destabilise under test overrides.
        waitAndTap(focusWidget)
        waitAndTap(focusCrop)
        waitAndTap(focusWidget)

        XCTAssertTrue(app.staticTexts[SectionHeaders.layout].waitForExistence(timeout: 2.0), "Expected Layout to remain discoverable")
    }

    func testContextAwareFlagOffShowsLegacyToolsInSmartPhotoFocus() {
        let app = launchApp(contextAwareEnabled: false)

        let templatePoster = app.buttons[UITestHooks.templatePoster]
        let focusCrop = app.buttons[UITestHooks.focusSmartPhotoCrop]

        waitAndTap(templatePoster)
        waitAndTap(focusCrop)

        let scrollView = editorScrollable(in: app)
        let textHeader = app.staticTexts[SectionHeaders.text]
        scrollToElement(textHeader, in: scrollView)

        XCTAssertTrue(textHeader.exists, "Legacy tool suite should still expose Text in Smart Photo focus")
    }

    func testContextAwareFlagOnHidesTextToolInSmartPhotoFocus() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = app.buttons[UITestHooks.templatePoster]
        let focusCrop = app.buttons[UITestHooks.focusSmartPhotoCrop]

        waitAndTap(templatePoster)
        waitAndTap(focusCrop)

        let smartPhotoHeader = app.staticTexts[SectionHeaders.smartPhoto]
        XCTAssertTrue(smartPhotoHeader.waitForExistence(timeout: 2.0), "Expected Smart Photo section to be visible")

        let textHeader = app.staticTexts[SectionHeaders.text]
        XCTAssertFalse(textHeader.exists, "Context-aware tool suite should hide Text in Smart Photo focus")
    }

    func testClockFocusSwitchingHidesSmartPhotoAndRestores() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = app.buttons[UITestHooks.templatePoster]
        let focusWidget = app.buttons[UITestHooks.focusWidget]
        let focusClock = app.buttons[UITestHooks.focusClock]

        waitAndTap(templatePoster)

        // Ensure Smart Photo is visible in normal widget focus.
        waitAndTap(focusWidget)
        let smartPhotoHeader = app.staticTexts[SectionHeaders.smartPhoto]
        XCTAssertTrue(smartPhotoHeader.waitForExistence(timeout: 2.0), "Expected Smart Photo to be visible in widget focus")

        // Switch to clock focus: Smart Photo should be removed from the accessibility tree.
        waitAndTap(focusClock)
        XCTAssertFalse(app.staticTexts[SectionHeaders.smartPhoto].exists, "Clock focus should hide Smart Photo tooling")

        // A core clock-safe tool should still exist.
        XCTAssertTrue(app.staticTexts[SectionHeaders.layout].waitForExistence(timeout: 2.0), "Expected Layout to remain visible in clock focus")

        // Restore to widget focus: Smart Photo should re-appear.
        waitAndTap(focusWidget)
        XCTAssertTrue(app.staticTexts[SectionHeaders.smartPhoto].waitForExistence(timeout: 2.0), "Expected Smart Photo to be restored after leaving clock focus")
    }

    func testAlbumFocusHidesTextAndLayoutTooling() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = app.buttons[UITestHooks.templatePoster]
        let focusAlbumContainer = app.buttons[UITestHooks.focusAlbumContainer]
        let focusAlbumPhotoItem = app.buttons[UITestHooks.focusAlbumPhotoItem]

        waitAndTap(templatePoster)

        // Album container focus.
        waitAndTap(focusAlbumContainer)
        XCTAssertTrue(app.staticTexts[SectionHeaders.smartPhoto].waitForExistence(timeout: 2.0), "Expected Smart Photo tooling in album container focus")
        XCTAssertFalse(app.staticTexts[SectionHeaders.text].exists, "Album focus should hide Text tooling")
        XCTAssertFalse(app.staticTexts[SectionHeaders.layout].exists, "Album focus should hide Layout tooling")

        // Album photo item focus.
        waitAndTap(focusAlbumPhotoItem)
        XCTAssertTrue(app.staticTexts[SectionHeaders.smartPhoto].waitForExistence(timeout: 2.0), "Expected Smart Photo tooling in album photo-item focus")
        XCTAssertFalse(app.staticTexts[SectionHeaders.text].exists, "Album focus should hide Text tooling")
        XCTAssertFalse(app.staticTexts[SectionHeaders.layout].exists, "Album focus should hide Layout tooling")
    }

    func testMultiSelectionHidesSmartPhotoAndTextTooling() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = app.buttons[UITestHooks.templatePoster]
        let multiSelectWidgets = app.buttons[UITestHooks.multiSelectWidgets]
        let multiSelectMixed = app.buttons[UITestHooks.multiSelectMixed]

        waitAndTap(templatePoster)

        // Non-album multi-selection.
        waitAndTap(multiSelectWidgets)
        XCTAssertTrue(app.staticTexts[SectionHeaders.layout].waitForExistence(timeout: 2.0), "Expected Layout tooling for multi-selection")
        XCTAssertFalse(app.staticTexts[SectionHeaders.text].exists, "Multi-selection should hide Text tooling")
        XCTAssertFalse(app.staticTexts[SectionHeaders.smartPhoto].exists, "Multi-selection should hide Smart Photo tooling")

        // Mixed multi-selection (album + non-album).
        waitAndTap(multiSelectMixed)
        XCTAssertTrue(app.staticTexts[SectionHeaders.layout].waitForExistence(timeout: 2.0), "Expected Layout tooling for mixed multi-selection")
        XCTAssertFalse(app.staticTexts[SectionHeaders.text].exists, "Mixed multi-selection should hide Text tooling")
        XCTAssertFalse(app.staticTexts[SectionHeaders.smartPhoto].exists, "Mixed multi-selection should hide Smart Photo tooling")
    }

    func testTextEntrySurvivesToolSuiteChanges() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = app.buttons[UITestHooks.templatePoster]
        let focusWidget = app.buttons[UITestHooks.focusWidget]
        let focusCrop = app.buttons[UITestHooks.focusSmartPhotoCrop]
        let focusClock = app.buttons[UITestHooks.focusClock]
        let focusAlbumContainer = app.buttons[UITestHooks.focusAlbumContainer]

        waitAndTap(templatePoster)
        waitAndTap(focusWidget)

        let scrollView = editorScrollable(in: app)

        let sentinel = " WWUITestSentinel"

        let designNameField = app.textFields[AccessibilityIDs.designNameTextField]
        scrollToElement(designNameField, in: scrollView)
        waitAndTap(designNameField)
        designNameField.typeText(sentinel)

        let primaryTextField = app.textFields[AccessibilityIDs.primaryTextField]
        scrollToElement(primaryTextField, in: scrollView)
        waitAndTap(primaryTextField)
        primaryTextField.typeText(sentinel)

        let secondaryTextField = app.textFields[AccessibilityIDs.secondaryTextField]
        scrollToElement(secondaryTextField, in: scrollView)
        waitAndTap(secondaryTextField)
        secondaryTextField.typeText(sentinel)

        // Switching to Smart Photo focus removes Text tooling; ensure the app remains stable.
        waitAndTap(focusCrop)
        XCTAssertFalse(app.textFields[AccessibilityIDs.primaryTextField].exists, "Text fields should be removed from the accessibility tree in Smart Photo focus")

        // Restoring should keep the entered text.
        waitAndTap(focusWidget)

        let restoredDesignName = app.textFields[AccessibilityIDs.designNameTextField]
        scrollToElement(restoredDesignName, in: scrollView)
        XCTAssertTrue(restoredDesignName.waitForExistence(timeout: 2.0), "Expected Design name field after restoring widget focus")
        let designNameValue = String(describing: restoredDesignName.value ?? "")
        XCTAssertTrue(designNameValue.contains("WWUITestSentinel"), "Expected Design name to preserve user input across tool suite changes")

        let restoredPrimary = app.textFields[AccessibilityIDs.primaryTextField]
        scrollToElement(restoredPrimary, in: scrollView)
        XCTAssertTrue(restoredPrimary.waitForExistence(timeout: 2.0), "Expected Primary text field after restoring widget focus")
        let primaryValue = String(describing: restoredPrimary.value ?? "")
        XCTAssertTrue(primaryValue.contains("WWUITestSentinel"), "Expected Primary text to preserve user input across tool suite changes")

        let restoredSecondary = app.textFields[AccessibilityIDs.secondaryTextField]
        scrollToElement(restoredSecondary, in: scrollView)
        XCTAssertTrue(restoredSecondary.waitForExistence(timeout: 2.0), "Expected Secondary text field after restoring widget focus")
        let secondaryValue = String(describing: restoredSecondary.value ?? "")
        XCTAssertTrue(secondaryValue.contains("WWUITestSentinel"), "Expected Secondary text to preserve user input across tool suite changes")

        // Additional continuity checks across other focus groups.
        waitAndTap(focusClock)
        XCTAssertFalse(app.textFields[AccessibilityIDs.primaryTextField].exists, "Clock focus should remove Text fields")

        waitAndTap(focusWidget)
        XCTAssertTrue(app.textFields[AccessibilityIDs.primaryTextField].waitForExistence(timeout: 2.0), "Expected Primary text field after leaving clock focus")

        waitAndTap(focusAlbumContainer)
        XCTAssertFalse(app.textFields[AccessibilityIDs.primaryTextField].exists, "Album focus should remove Text fields")

        waitAndTap(focusWidget)
        let restoredPrimaryAfterAlbum = app.textFields[AccessibilityIDs.primaryTextField]
        scrollToElement(restoredPrimaryAfterAlbum, in: scrollView)
        XCTAssertTrue(restoredPrimaryAfterAlbum.waitForExistence(timeout: 2.0), "Expected Primary text field after leaving album focus")
        let primaryAfterAlbumValue = String(describing: restoredPrimaryAfterAlbum.value ?? "")
        XCTAssertTrue(primaryAfterAlbumValue.contains("WWUITestSentinel"), "Expected Primary text to remain after leaving album focus")
    }
}
