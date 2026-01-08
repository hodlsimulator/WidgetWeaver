//
//  EditorFocusSwitchingSmokeUITests.swift
//  WidgetWeaverUITests
//
//  Created by . . on 1/8/26.
//

import XCTest

final class EditorFocusSwitchingSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testContextAwareFocusSwitchingSmoke() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-widgetweaver.feature.editor.contextAwareToolSuite.enabled", "1"
        ]
        app.launch()

        let editorScroll = app.scrollViews.firstMatch
        XCTAssertTrue(editorScroll.waitForExistence(timeout: 8))

        func scrollToElement(_ element: XCUIElement, maxScrolls: Int = 18) {
            var remaining = maxScrolls
            while !element.exists && remaining > 0 {
                editorScroll.swipeUp()
                remaining -= 1
            }
        }

        // Smart Rules (push editor -> back)
        let editRulesButton = app.buttons["Edit Smart Rules"]
        scrollToElement(editRulesButton)

        if editRulesButton.exists {
            editRulesButton.tap()
            XCTAssertTrue(app.navigationBars["Smart Rules"].waitForExistence(timeout: 5))
            app.navigationBars["Smart Rules"].buttons.firstMatch.tap()
        }

        // Smart Photo Crop (push editor -> back)
        //
        // Depending on how SwiftUI renders the NavigationLink, this may appear as a button or text.
        let editCropButton = app.buttons["Edit Crop"]
        let editCropText = app.staticTexts["Edit Crop"]

        if !editCropButton.exists {
            scrollToElement(editCropText)
        } else {
            scrollToElement(editCropButton)
        }

        if editCropButton.exists {
            editCropButton.tap()
            XCTAssertTrue(app.navigationBars["Fix framing"].waitForExistence(timeout: 5))
            app.navigationBars["Fix framing"].buttons.firstMatch.tap()
        } else if editCropText.exists {
            editCropText.tap()
            XCTAssertTrue(app.navigationBars["Fix framing"].waitForExistence(timeout: 5))
            app.navigationBars["Fix framing"].buttons.firstMatch.tap()
        }
    }
}
