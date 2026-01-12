//
//  WidgetWeaverTests.swift
//  WidgetWeaverTests
//
//  Created by . . on 1/8/26.
//

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
