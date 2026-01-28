//
//  WidgetSpecAICandidate.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import Foundation

/// Candidate AI output that can be previewed and (optionally) applied.
///
/// This model is intentionally non-persistent. It is designed to support:
/// - Review-before-apply UI (preview + summary + warnings)
/// - An “apply immediately” path when review UI is disabled
public struct WidgetSpecAICandidate: Hashable {
    /// The proposed spec after generation/patching and AI normalisation.
    public var candidateSpec: WidgetSpec

    /// Human-readable summary of the changes or key design attributes.
    ///
    /// For patch operations this should usually be a before/after diff.
    public var changeSummary: [String]

    /// Warnings worth surfacing in the review UI.
    public var warnings: [String]

    /// True when the candidate was produced by deterministic rules (fallback), not the on-device model.
    public var isFallback: Bool

    /// Human-readable availability of the underlying AI source.
    ///
    /// Typical values:
    /// - "Apple Intelligence: Ready"
    /// - "Apple Intelligence: Not supported on this device"
    /// - "AI disabled"
    public var sourceAvailability: String

    public init(
        candidateSpec: WidgetSpec,
        changeSummary: [String],
        warnings: [String],
        isFallback: Bool,
        sourceAvailability: String
    ) {
        self.candidateSpec = candidateSpec
        self.changeSummary = changeSummary
        self.warnings = warnings
        self.isFallback = isFallback
        self.sourceAvailability = sourceAvailability
    }
}
