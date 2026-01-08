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
    }

    private enum UITestHooks {
        static let templatePoster = "EditorUITestHook.templatePoster"
        static let focusWidget = "EditorUITestHook.focusWidget"
        static let focusSmartPhotoCrop = "EditorUITestHook.focusSmartPhotoCrop"
        static let focusSmartRules = "EditorUITestHook.focusSmartRules"
        static let focusClock = "EditorUITestHook.focusClock"
    }

    private enum SectionHeaders {
        static let text = "EditorSectionHeader.Text"
        static let smartPhoto = "EditorSectionHeader.Smart_Photo"
        static let layout = "EditorSectionHeader.Layout"
    }

    private func launchApp(contextAwareEnabled: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            LaunchKeys.uiTestHooksEnabled,
            "1",
            LaunchKeys.contextAwareToolSuiteEnabled,
            contextAwareEnabled ? "1" : "0",
        ]
        app.launch()
        return app
    }

    private func editorScrollView(in app: XCUIApplication) -> XCUIElement {
        app.scrollViews.firstMatch
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
        while !element.exists && remaining > 0 {
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

    func testContextAwareFlagOffShowsLegacyToolsInSmartPhotoFocus() {
        let app = launchApp(contextAwareEnabled: false)

        let templatePoster = app.buttons[UITestHooks.templatePoster]
        let focusCrop = app.buttons[UITestHooks.focusSmartPhotoCrop]

        waitAndTap(templatePoster)
        waitAndTap(focusCrop)

        let scrollView = editorScrollView(in: app)
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
}
