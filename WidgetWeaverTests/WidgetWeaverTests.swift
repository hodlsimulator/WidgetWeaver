//
//  WidgetWeaverTests.swift
//  WidgetWeaverTests
//
//  Created by . . on 1/8/26.
//

import Foundation
import Testing
@testable import WidgetWeaver

struct WidgetWeaverTests {

    @Test func toolManifestCoversAllToolIDs() {
        let manifestIDs = Set(EditorToolRegistry.tools.map(\.id))
        let allToolIDs = Set(EditorToolID.allCases)

        let missingFromManifest = allToolIDs.subtracting(manifestIDs)
        let extraInManifest = manifestIDs.subtracting(allToolIDs)

        #expect(missingFromManifest.isEmpty)
        #expect(extraInManifest.isEmpty)
        #expect(manifestIDs.count == allToolIDs.count)
    }

    @Test func toolManifestOnlyUsesKnownCapabilities() {
        let knownToolCapabilities = Set(EditorCapabilities.allKnown)
        let knownNonPhotosCapabilities: Set<EditorNonPhotosCapability> = [.proUnlocked, .matchedSetAvailable]

        for tool in EditorToolRegistry.tools {
            #expect(tool.requiredCapabilities.isSubset(of: knownToolCapabilities))
            #expect(tool.requiredNonPhotosCapabilities.isSubset(of: knownNonPhotosCapabilities))
        }
    }

    @Test func toolManifestDeclaresMultiSelectionSupportPerTool() {
        let expectedMultiSelectionSafe: Set<EditorToolID> = [
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

        let actualMultiSelectionSafe = Set(
            EditorToolRegistry.tools
                .filter { $0.eligibility.supportsMultiSelection }
                .map(\.id)
        )

        #expect(actualMultiSelectionSafe == expectedMultiSelectionSafe)

        let expectedSingleTarget = Set(EditorToolID.allCases).subtracting(expectedMultiSelectionSafe)
        let actualSingleTarget = Set(
            EditorToolRegistry.tools
                .filter { !$0.eligibility.supportsMultiSelection }
                .map(\.id)
        )

        #expect(actualSingleTarget == expectedSingleTarget)
    }

    @Test func toolManifestMissingNonPhotosCapabilityPolicyMatchesRequirements() {
        for tool in EditorToolRegistry.tools {
            let policyIsHide: Bool = {
                switch tool.missingNonPhotosCapabilityPolicy {
                case .hide:
                    return true
                case .showAsUnavailable:
                    return false
                }
            }()

            // Contract:
            // - If a tool requires no non-Photos capabilities, it should hide (no unavailable surface).
            // - If a tool requires non-Photos capabilities, it must pick a "show unavailable" surface.
            #expect(tool.requiredNonPhotosCapabilities.isEmpty == policyIsHide)
        }
    }
}

struct WidgetWeaverStepsRenderClockTests {

    @Test func renderClockOverride_affectsDefaultNowInStores() {
        let cal = Calendar.autoupdatingCurrent

        let stepsStore = WidgetWeaverStepsStore.shared
        let activityStore = WidgetWeaverActivityStore.shared

        let originalGoalSchedule = stepsStore.loadGoalSchedule()
        let originalStepsSnapshot = stepsStore.loadSnapshot()
        let originalActivitySnapshot = activityStore.loadSnapshot()

        defer {
            stepsStore.saveGoalSchedule(originalGoalSchedule, writeLegacyKey: true)
            stepsStore.saveSnapshot(originalStepsSnapshot)
            activityStore.saveSnapshot(originalActivitySnapshot)
        }

        // Steps: snapshotForToday() should respect WidgetWeaverRenderClock.now when now isn't passed explicitly.
        let nowA = Date(timeIntervalSinceReferenceDate: 1_234_567)
        let stepsSnap = WidgetWeaverStepsSnapshot(
            fetchedAt: nowA,
            startOfDay: cal.startOfDay(for: nowA),
            steps: 1_234
        )
        stepsStore.saveSnapshot(stepsSnap)

        let resolvedSteps = WidgetWeaverRenderClock.withNow(nowA) {
            stepsStore.snapshotForToday()
        }

        #expect(resolvedSteps?.steps == 1_234)

        // Steps: variablesDictionary() should respect WidgetWeaverRenderClock.now when now isn't passed explicitly.
        let schedule = WidgetWeaverStepsGoalSchedule(weekdayGoalSteps: 111, weekendGoalSteps: 222)
        stepsStore.saveGoalSchedule(schedule, writeLegacyKey: true)

        let nowB = Date(timeIntervalSinceReferenceDate: 2_345_678)
        let expectedGoalToday = schedule.goalSteps(for: nowB, calendar: cal)

        let vars = WidgetWeaverRenderClock.withNow(nowB) {
            stepsStore.variablesDictionary()
        }

        #expect(vars["__steps_goal_today"] == String(expectedGoalToday))

        // Activity: snapshotForToday() should also respect WidgetWeaverRenderClock.now by default.
        let nowC = Date(timeIntervalSinceReferenceDate: 3_456_789)
        let activitySnap = WidgetWeaverActivitySnapshot(
            fetchedAt: nowC,
            startOfDay: cal.startOfDay(for: nowC),
            steps: 321,
            flightsClimbed: nil,
            distanceWalkingRunningMeters: nil,
            activeEnergyBurnedKilocalories: nil
        )
        activityStore.saveSnapshot(activitySnap)

        let resolvedActivity = WidgetWeaverRenderClock.withNow(nowC) {
            activityStore.snapshotForToday()
        }

        #expect(resolvedActivity?.steps == 321)
    }
}
//
//  WidgetWeaverTests.swift
//  WidgetWeaverTests
//
//  Created by . . on 1/8/26.
//

import Foundation
import Testing
@testable import WidgetWeaver

struct WidgetWeaverTests {

    @Test func toolManifestCoversAllToolIDs() {
        let manifestIDs = Set(EditorToolRegistry.tools.map(\.id))
        let allToolIDs = Set(EditorToolID.allCases)

        let missingFromManifest = allToolIDs.subtracting(manifestIDs)
        let extraInManifest = manifestIDs.subtracting(allToolIDs)

        #expect(missingFromManifest.isEmpty)
        #expect(extraInManifest.isEmpty)
        #expect(manifestIDs.count == allToolIDs.count)
    }

    @Test func toolManifestOnlyUsesKnownCapabilities() {
        let knownToolCapabilities = Set(EditorCapabilities.allKnown)
        let knownNonPhotosCapabilities: Set<EditorNonPhotosCapability> = [.proUnlocked, .matchedSetAvailable]

        for tool in EditorToolRegistry.tools {
            #expect(tool.requiredCapabilities.isSubset(of: knownToolCapabilities))
            #expect(tool.requiredNonPhotosCapabilities.isSubset(of: knownNonPhotosCapabilities))
        }
    }

    @Test func toolManifestDeclaresMultiSelectionSupportPerTool() {
        let expectedMultiSelectionSafe: Set<EditorToolID> = [
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

        let actualMultiSelectionSafe = Set(
            EditorToolRegistry.tools
                .filter { $0.eligibility.supportsMultiSelection }
                .map(\.id)
        )

        #expect(actualMultiSelectionSafe == expectedMultiSelectionSafe)

        let expectedSingleTarget = Set(EditorToolID.allCases).subtracting(expectedMultiSelectionSafe)
        let actualSingleTarget = Set(
            EditorToolRegistry.tools
                .filter { !$0.eligibility.supportsMultiSelection }
                .map(\.id)
        )

        #expect(actualSingleTarget == expectedSingleTarget)
    }

    @Test func toolManifestMissingNonPhotosCapabilityPolicyMatchesRequirements() {
        for tool in EditorToolRegistry.tools {
            let policyIsHide: Bool = {
                switch tool.missingNonPhotosCapabilityPolicy {
                case .hide:
                    return true
                case .showAsUnavailable:
                    return false
                }
            }()

            // Contract:
            // - If a tool requires no non-Photos capabilities, it should hide (no unavailable surface).
            // - If a tool requires non-Photos capabilities, it must pick a "show unavailable" surface.
            #expect(tool.requiredNonPhotosCapabilities.isEmpty == policyIsHide)
        }
    }
}

struct WidgetWeaverStepsRenderClockTests {

    @Test func renderClockOverride_affectsDefaultNowInStores() {
        let cal = Calendar.autoupdatingCurrent

        let stepsStore = WidgetWeaverStepsStore.shared
        let activityStore = WidgetWeaverActivityStore.shared

        let originalGoalSchedule = stepsStore.loadGoalSchedule()
        let originalStepsSnapshot = stepsStore.loadSnapshot()
        let originalActivitySnapshot = activityStore.loadSnapshot()

        defer {
            stepsStore.saveGoalSchedule(originalGoalSchedule, writeLegacyKey: true)
            stepsStore.saveSnapshot(originalStepsSnapshot)
            activityStore.saveSnapshot(originalActivitySnapshot)
        }

        // Steps: snapshotForToday() should respect WidgetWeaverRenderClock.now when now isn't passed explicitly.
        let nowA = Date(timeIntervalSinceReferenceDate: 1_234_567)
        let stepsSnap = WidgetWeaverStepsSnapshot(
            fetchedAt: nowA,
            startOfDay: cal.startOfDay(for: nowA),
            steps: 1_234
        )
        stepsStore.saveSnapshot(stepsSnap)

        let resolvedSteps = WidgetWeaverRenderClock.withNow(nowA) {
            stepsStore.snapshotForToday()
        }

        #expect(resolvedSteps?.steps == 1_234)

        // Steps: variablesDictionary() should respect WidgetWeaverRenderClock.now when now isn't passed explicitly.
        let schedule = WidgetWeaverStepsGoalSchedule(weekdayGoalSteps: 111, weekendGoalSteps: 222)
        stepsStore.saveGoalSchedule(schedule, writeLegacyKey: true)

        let nowB = Date(timeIntervalSinceReferenceDate: 2_345_678)
        let expectedGoalToday = schedule.goalSteps(for: nowB, calendar: cal)

        let vars = WidgetWeaverRenderClock.withNow(nowB) {
            stepsStore.variablesDictionary()
        }

        #expect(vars["__steps_goal_today"] == String(expectedGoalToday))

        // Activity: snapshotForToday() should also respect WidgetWeaverRenderClock.now by default.
        let nowC = Date(timeIntervalSinceReferenceDate: 3_456_789)
        let activitySnap = WidgetWeaverActivitySnapshot(
            fetchedAt: nowC,
            startOfDay: cal.startOfDay(for: nowC),
            steps: 321,
            flightsClimbed: nil,
            distanceWalkingRunningMeters: nil,
            activeEnergyBurnedKilocalories: nil
        )
        activityStore.saveSnapshot(activitySnap)

        let resolvedActivity = WidgetWeaverRenderClock.withNow(nowC) {
            activityStore.snapshotForToday()
        }

        #expect(resolvedActivity?.steps == 321)
    }
}

