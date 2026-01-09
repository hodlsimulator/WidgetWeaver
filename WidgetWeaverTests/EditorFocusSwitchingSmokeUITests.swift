//
//  EditorFocusSwitchingSmokeUITests.swift
//  WidgetWeaverUITests
//
//  Created by . . on 1/8/26.
//

import XCTest
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

    private enum IDs {
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

        XCTAssertTrue(
            element.isHittable,
            "Expected element to be hittable: \(element)",
            file: file,
            line: line
        )

        element.tap()
    }

    private func assertHookSurfacePresent(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let hookAny = element(UITestHooks.templatePoster, in: app)
        XCTAssertTrue(
            hookAny.waitForExistence(timeout: 2.0),
            "Expected UI test hook surface to exist",
            file: file,
            line: line
        )
    }

    private func assertEditorStillRenders(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let anyHeader = firstElement(withIdentifierPrefix: IDs.sectionHeaderPrefix, in: app)
        XCTAssertTrue(
            anyHeader.waitForExistence(timeout: 2.0),
            "Expected at least one editor section header to exist after focus change",
            file: file,
            line: line
        )
    }

    func testUITestHookSurfaceIsReachable() {
        let app = launchApp(contextAwareEnabled: true)

        assertHookSurfacePresent(in: app)
        waitAndTap(element(UITestHooks.templatePoster, in: app))
        assertEditorStillRenders(in: app)
    }

    func testContextAwareFocusSwitchingSmoke() {
        let app = launchApp(contextAwareEnabled: true, reduceMotion: true)

        let templatePoster = element(UITestHooks.templatePoster, in: app)
        let focusWidget = element(UITestHooks.focusWidget, in: app)
        let focusCrop = element(UITestHooks.focusSmartPhotoCrop, in: app)
        let focusRules = element(UITestHooks.focusSmartRules, in: app)
        let focusAlbumContainer = element(UITestHooks.focusAlbumContainer, in: app)
        let focusAlbumPhotoItem = element(UITestHooks.focusAlbumPhotoItem, in: app)
        let focusClock = element(UITestHooks.focusClock, in: app)
        let multiSelectWidgets = element(UITestHooks.multiSelectWidgets, in: app)
        let multiSelectMixed = element(UITestHooks.multiSelectMixed, in: app)

        assertHookSurfacePresent(in: app)

        waitAndTap(templatePoster)
        assertEditorStillRenders(in: app)

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

        for (label, hook) in steps {
            XCTContext.runActivity(named: label) { _ in
                waitAndTap(hook)
                assertEditorStillRenders(in: app)
            }
        }
    }

    func testLegacyModeFocusSwitchingSmoke() {
        let app = launchApp(contextAwareEnabled: false, reduceMotion: true)

        let templatePoster = element(UITestHooks.templatePoster, in: app)
        let focusWidget = element(UITestHooks.focusWidget, in: app)
        let focusCrop = element(UITestHooks.focusSmartPhotoCrop, in: app)

        assertHookSurfacePresent(in: app)

        waitAndTap(templatePoster)
        assertEditorStillRenders(in: app)

        waitAndTap(focusCrop)
        assertEditorStillRenders(in: app)

        waitAndTap(focusWidget)
        assertEditorStillRenders(in: app)
    }
}
