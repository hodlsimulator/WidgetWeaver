//
//  WidgetWeaverWeatherEngineThrottleTests.swift
//  WidgetWeaver
//
//  Created by . . on 1/24/26.
//

import Foundation
import Testing
@testable import WidgetWeaver

struct WidgetWeaverWeatherEngineThrottleTests {

    @Test func shouldAttemptRefresh_allowsWhenForced() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let lastAttempt = Date(timeIntervalSinceReferenceDate: 9999)

        let allowed = WidgetWeaverWeatherEngine.shouldAttemptRefresh(
            force: true,
            now: now,
            lastAttemptAt: lastAttempt,
            minimumUpdateInterval: 600
        )

        #expect(allowed == true)
    }

    @Test func shouldAttemptRefresh_allowsWhenNoLastAttempt() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)

        let allowed = WidgetWeaverWeatherEngine.shouldAttemptRefresh(
            force: false,
            now: now,
            lastAttemptAt: nil,
            minimumUpdateInterval: 600
        )

        #expect(allowed == true)
    }

    @Test func shouldAttemptRefresh_blocksWithinMinimumInterval() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let lastAttempt = Date(timeIntervalSinceReferenceDate: 1000 - 60)

        let allowed = WidgetWeaverWeatherEngine.shouldAttemptRefresh(
            force: false,
            now: now,
            lastAttemptAt: lastAttempt,
            minimumUpdateInterval: 600
        )

        #expect(allowed == false)
    }

    @Test func shouldAttemptRefresh_allowsAfterMinimumInterval() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let lastAttempt = Date(timeIntervalSinceReferenceDate: 1000 - 601)

        let allowed = WidgetWeaverWeatherEngine.shouldAttemptRefresh(
            force: false,
            now: now,
            lastAttemptAt: lastAttempt,
            minimumUpdateInterval: 600
        )

        #expect(allowed == true)
    }

    @Test func shouldAttemptRefresh_allowsWhenMinimumIntervalDisabled() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let lastAttempt = Date(timeIntervalSinceReferenceDate: 1000 - 60)

        let allowed = WidgetWeaverWeatherEngine.shouldAttemptRefresh(
            force: false,
            now: now,
            lastAttemptAt: lastAttempt,
            minimumUpdateInterval: 0
        )

        #expect(allowed == true)
    }

    @Test func shouldAttemptRefresh_allowsWhenLastAttemptIsInFuture() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let lastAttempt = Date(timeIntervalSinceReferenceDate: 1100)

        let allowed = WidgetWeaverWeatherEngine.shouldAttemptRefresh(
            force: false,
            now: now,
            lastAttemptAt: lastAttempt,
            minimumUpdateInterval: 600
        )

        #expect(allowed == true)
    }
}
