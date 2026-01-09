//
//  EditorFocusSwitchingSmokeUITests.swift
//  WidgetWeaverUITests
//
//  Created by . . on 1/8/26.
//

import XCTest
import CoreGraphics
import Foundation

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
        static let prefix = "EditorSectionHeader."
        static let status = "EditorSectionHeader.Status"
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

    private func editorScrollable(
        in app: XCUIApplication,
        timeout: TimeInterval = 2.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let table = app.tables.firstMatch
        let collectionView = app.collectionViews.firstMatch
        let scrollView = app.scrollViews.firstMatch

        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if table.exists || collectionView.exists || scrollView.exists {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if table.exists {
            return table
        }

        if collectionView.exists {
            return collectionView
        }

        if scrollView.exists {
            return scrollView
        }

        XCTFail(
            "Expected editor to expose a scroll container (Table → CollectionView → ScrollView).",
            file: file,
            line: line
        )

        // Safe-ish fallback: allow downstream calls to fail with a more specific message.
        return scrollView
    }

    private func waitAndTap(
        _ element: XCUIElement,
        timeout: TimeInterval = 2.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Expected element to exist: \(element)",
            file: file,
            line: line
        )

        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func scrollToTop(
        in scrollView: XCUIElement,
        maxScrolls: Int = 6
    ) {
        guard scrollView.exists else {
            return
        }

        for _ in 0..<maxScrolls {
            scrollView.swipeDown()
        }
    }

    private func scrollToElement(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        maxScrolls: Int = 18
    ) {
        guard scrollView.exists else {
            return
        }

        var remaining = maxScrolls
        while (!element.exists || !element.isHittable) && remaining > 0 {
            scrollView.swipeUp()
            remaining -= 1
        }
    }

    private func currentSectionHeaderIdentifiers(in app: XCUIApplication) -> [String] {
        let all = app.descendants(matching: .any).allElementsBoundByIndex
        var ids: Set<String> = []
        ids.reserveCapacity(16)

        for element in all {
            let identifier = element.identifier
            if identifier.hasPrefix(SectionHeaders.prefix) {
                ids.insert(identifier)
            }
        }

        return ids.sorted()
    }

    private func assertStatusHeaderIsDiscoverable(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let scrollable = editorScrollable(in: app, file: file, line: line)
        let statusHeader = element(SectionHeaders.status, in: app)

        // SwiftUI can lazily realise sections; always scroll to establish a stable anchor.
        scrollToTop(in: scrollable)
        scrollToElement(statusHeader, in: scrollable, maxScrolls: 10)

        if statusHeader.exists {
            return
        }

        // If the list started mid-scroll, attempt to recover by scrolling back up and trying again.
        scrollToTop(in: scrollable)
        scrollToElement(statusHeader, in: scrollable, maxScrolls: 10)

        if statusHeader.exists {
            return
        }

        let discoveredHeaders = currentSectionHeaderIdentifiers(in: app)
        XCTFail(
            "Expected a stable Status header anchor to exist (\(SectionHeaders.status)). Discovered headers: \(discoveredHeaders)",
            file: file,
            line: line
        )
    }

    func testUITestHookSurfaceIsReachable() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = hook(UITestHooks.templatePoster, in: app)
        XCTAssertTrue(
            templatePoster.waitForExistence(timeout: 2.0),
            "Expected UI test hook surface to be present in the Editor tab"
        )
    }

    func testContextAwareFocusSwitchingSmoke() {
        let app = launchApp(contextAwareEnabled: true)

        let templatePoster = hook(UITestHooks.templatePoster, in: app)
        let focusWidget = hook(UITestHooks.focusWidget, in: app)
        let focusCrop = hook(UITestHooks.focusSmartPhotoCrop, in: app)
        let focusRules = hook(UITestHooks.focusSmartRules, in: app)
        let focusAlbumContainer = hook(UITestHooks.focusAlbumContainer, in: app)
        let focusAlbumPhotoItem = hook(UITestHooks.focusAlbumPhotoItem, in: app)
        let focusClock = hook(UITestHooks.focusClock, in: app)
        let multiSelectWidgets = hook(UITestHooks.multiSelectWidgets, in: app)
        let multiSelectMixed = hook(UITestHooks.multiSelectMixed, in: app)

        waitAndTap(templatePoster)
        assertStatusHeaderIsDiscoverable(in: app)

        let steps: [(String, XCUIElement)] = [
            ("Focus Smart Photo crop", focusCrop),
            ("Focus widget", focusWidget),
            ("Focus Smart Rules", focusRules),
            ("Focus widget", focusWidget),
            ("Focus album container", focusAlbumContainer),
            ("Focus album photo item", focusAlbumPhotoItem),
            ("Focus widget", focusWidget),
            ("Focus clock", focusClock),
            ("Focus widget", focusWidget),
            ("Multi-select widgets", multiSelectWidgets),
            ("Focus widget", focusWidget),
            ("Multi-select mixed", multiSelectMixed),
            ("Focus widget", focusWidget),
        ]

        for _ in 0..<2 {
            for (label, stepHook) in steps {
                XCTContext.runActivity(named: label) { _ in
                    waitAndTap(stepHook)
                    assertStatusHeaderIsDiscoverable(in: app)
                }
            }
        }
    }

    func testLegacyModeFocusSwitchingSmoke() {
        let app = launchApp(contextAwareEnabled: false)

        let templatePoster = hook(UITestHooks.templatePoster, in: app)
        let focusWidget = hook(UITestHooks.focusWidget, in: app)
        let focusCrop = hook(UITestHooks.focusSmartPhotoCrop, in: app)

        waitAndTap(templatePoster)
        assertStatusHeaderIsDiscoverable(in: app)

        XCTContext.runActivity(named: "Legacy: focus Smart Photo crop") { _ in
            waitAndTap(focusCrop)
            assertStatusHeaderIsDiscoverable(in: app)
        }

        XCTContext.runActivity(named: "Legacy: return to widget focus") { _ in
            waitAndTap(focusWidget)
            assertStatusHeaderIsDiscoverable(in: app)
        }
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
        scrollToTop(in: scrollable)
        scrollToElement(primary, in: scrollable, maxScrolls: 18)
        waitAndTap(primary)

        let input = "Hello"
        primary.typeText(input)

        // Switch into Smart Photo focus and back; text entry should remain and the editor should still be navigable.
        waitAndTap(focusCrop)
        assertStatusHeaderIsDiscoverable(in: app)

        waitAndTap(focusWidget)
        assertStatusHeaderIsDiscoverable(in: app)

        let primaryAfter = app.textFields[AccessibilityIDs.primaryTextField]
        scrollToTop(in: scrollable)
        scrollToElement(primaryAfter, in: scrollable, maxScrolls: 18)
        XCTAssertTrue(primaryAfter.waitForExistence(timeout: 2.0))

        let value = (primaryAfter.value as? String) ?? ""
        XCTAssertTrue(
            value.contains(input),
            "Expected primary text field value to contain '\(input)'. Actual value: '\(value)'"
        )
    }
}
