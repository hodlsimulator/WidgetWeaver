//
//  EditorFocusSwitchingSmokeUITests.swift
//  WidgetWeaverUITests
//
//  Created by . . on 1/8/26.
//

import Foundation
import XCTest

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
        static let overlayRoot = "EditorUITestHook.overlayRoot"
        static let templatePoster = "EditorUITestHook.templatePoster"
        static let focusWidget = "EditorUITestHook.focusWidget"
        static let focusSmartPhotoCrop = "EditorUITestHook.focusSmartPhotoCrop"
        static let focusSmartRules = "EditorUITestHook.focusSmartRules"
        static let focusAlbumContainer = "EditorUITestHook.focusAlbumContainer"
        static let focusAlbumPhotoItem = "EditorUITestHook.focusAlbumPhotoItem"
        static let multiSelectWidgets = "EditorUITestHook.multiSelectWidgets"
        static let focusClock = "EditorUITestHook.focusClock"
    }

    private enum WidgetListSelection {
        static let root = "EditorWidgetListSelection.Root"
        static let clear = "EditorWidgetListSelection.Clear"
        static let itemText = "EditorWidgetListSelection.Item.text"
        static let itemLayout = "EditorWidgetListSelection.Item.layout"
        static let itemSmartAlbumContainer = "EditorWidgetListSelection.Item.smartAlbumContainer"
    }

    private enum IDs {
        static let editorForm = "Editor.Form"
        static let sectionHeaderPrefix = "EditorSectionHeader."
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(
        contextAwareEnabled: Bool,
        dynamicType: String? = nil,
        reduceMotion: Bool? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            LaunchKeys.uiTestHooksEnabled, "1",
            LaunchKeys.contextAwareToolSuiteEnabled, contextAwareEnabled ? "1" : "0",
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
            if !editorTab.isSelected { editorTab.tap() }
            return
        }

        let editorButtonFallback = app.buttons[Tabs.editor]
        if editorButtonFallback.waitForExistence(timeout: 2.0) {
            editorButtonFallback.tap()
            return
        }

        XCTFail("Expected Editor tab to exist", file: file, line: line)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func firstElement(withIdentifierPrefix prefix: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func waitAndTap(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 4.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let target = element(identifier, in: app)
        let predicate = NSPredicate(format: "exists == true && hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: target)

        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        guard result == .completed else {
            XCTFail(
                "Expected element to become tappable: \(identifier) (result: \(result))\n\n\(target.debugDescription)",
                file: file,
                line: line
            )
            return
        }

        target.tap()
    }

    private func assertHookSurfacePresent(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let root = element(UITestHooks.overlayRoot, in: app)
        XCTAssertTrue(
            root.waitForExistence(timeout: 2.0),
            "Expected UI test hook overlay root to exist",
            file: file,
            line: line
        )

        let hookAny = element(UITestHooks.templatePoster, in: app)
        XCTAssertTrue(
            hookAny.waitForExistence(timeout: 2.0),
            "Expected at least one UI test hook button to exist",
            file: file,
            line: line
        )
    }

    private func assertEditorStillRenders(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let editorForm = element(IDs.editorForm, in: app)
        if editorForm.waitForExistence(timeout: 2.0) {
            return
        }

        let anyHeader = firstElement(withIdentifierPrefix: IDs.sectionHeaderPrefix, in: app)
        XCTAssertTrue(
            anyHeader.waitForExistence(timeout: 2.0),
            "Expected editor to render after focus change (form or at least one section header).",
            file: file,
            line: line
        )
    }

    func testUITestHookSurfaceIsReachable() {
        let app = launchApp(contextAwareEnabled: true)

        assertHookSurfacePresent(in: app)
        waitAndTap(UITestHooks.templatePoster, in: app)
        assertEditorStillRenders(in: app)
    }

    func testContextAwareFocusSwitchingSmoke() {
        let app = launchApp(contextAwareEnabled: true, reduceMotion: true)

        assertHookSurfacePresent(in: app)

        waitAndTap(UITestHooks.templatePoster, in: app)
        assertEditorStillRenders(in: app)

        let steps: [(String, String)] = [
            ("Focus Smart Photo crop", UITestHooks.focusSmartPhotoCrop),
            ("Focus widget", UITestHooks.focusWidget),
            ("Focus Smart Rules", UITestHooks.focusSmartRules),
            ("Focus widget", UITestHooks.focusWidget),
            ("Focus album container", UITestHooks.focusAlbumContainer),
            ("Focus album photo item", UITestHooks.focusAlbumPhotoItem),
            ("Focus widget", UITestHooks.focusWidget),
            ("Focus clock", UITestHooks.focusClock),
            ("Focus widget", UITestHooks.focusWidget),
            ("Multi-select widgets", UITestHooks.multiSelectWidgets),
            ("Focus widget", UITestHooks.focusWidget),
        ]

        for (label, hookID) in steps {
            XCTContext.runActivity(named: label) { _ in
                waitAndTap(hookID, in: app)
                assertEditorStillRenders(in: app)
            }
        }

        XCTContext.runActivity(named: "Multi-select mixed via widget list") { _ in
            waitAndTap(UITestHooks.focusWidget, in: app)

            waitAndTap(WidgetListSelection.clear, in: app)
            waitAndTap(WidgetListSelection.itemText, in: app)
            waitAndTap(WidgetListSelection.itemSmartAlbumContainer, in: app)
            assertEditorStillRenders(in: app)

            waitAndTap(WidgetListSelection.clear, in: app)
            assertEditorStillRenders(in: app)
        }
    }

    func testLegacyModeFocusSwitchingSmoke() {
        let app = launchApp(contextAwareEnabled: false, reduceMotion: true)

        assertHookSurfacePresent(in: app)

        waitAndTap(UITestHooks.templatePoster, in: app)
        assertEditorStillRenders(in: app)

        let steps: [(String, String)] = [
            ("Focus Smart Photo crop", UITestHooks.focusSmartPhotoCrop),
            ("Focus widget", UITestHooks.focusWidget),
        ]

        for (label, hookID) in steps {
            XCTContext.runActivity(named: label) { _ in
                waitAndTap(hookID, in: app)
                assertEditorStillRenders(in: app)
            }
        }
    }
}
