//
//  ContentView+AICandidateActions.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import Foundation
import SwiftUI

extension ContentView {

    // MARK: - AI (review mode; candidate generation)

    @MainActor
    func generateNewDesignCandidateFromPrompt() async {
        aiStatusMessage = ""

        guard aiHasCapacityToSaveAnotherDesign else {
            aiStatusMessage = "Free tier allows up to \(WidgetWeaverEntitlements.maxFreeDesigns) designs.\nUnlock Pro for unlimited designs."
            activeSheet = .pro
            return
        }

        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let candidate = await WidgetSpecAIService.shared.generateCandidate(from: prompt)
        aiStatusMessage = formatCandidateStatusMessage(
            candidate,
            title: "Review mode is enabled. Candidate generated (not saved)."
        )

        activeSheet = .aiReview(candidate: candidate, mode: .generate)
    }

    @MainActor
    func applyPatchCandidateToCurrentDesign() async {
        aiStatusMessage = ""

        let instruction = aiPatchInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }

        let style = styleDraft.toStyleSpec()

        let current = currentFamilyDraft().toFlatSpec(
            id: selectedSpecID,
            name: designName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "WidgetWeaver"
                : designName.trimmingCharacters(in: .whitespacesAndNewlines),
            style: style,
            updatedAt: Date()
        )

        let candidate = await WidgetSpecAIService.shared.patchCandidate(baseSpec: current, instruction: instruction)
        aiStatusMessage = formatCandidateStatusMessage(
            candidate,
            title: "Review mode is enabled. Candidate patch generated (not saved)."
        )

        activeSheet = .aiReview(candidate: candidate, mode: .patch)
    }

    // MARK: - AI (review mode; apply)

    /// Applies a generated candidate spec using the same persistence steps as the legacy auto-apply Generate path.
    ///
    /// Returns `true` when the candidate was saved (and the review sheet can be dismissed).
    /// Returns `false` when the save was blocked (e.g. free-tier limit).
    @MainActor
    func applyGeneratedDesignCandidateFromReviewSheet(_ candidate: WidgetSpecAICandidate) -> Bool {
        aiStatusMessage = ""

        guard aiHasCapacityToSaveAnotherDesign else {
            aiStatusMessage = "Free tier allows up to \(WidgetWeaverEntitlements.maxFreeDesigns) designs.\nUnlock Pro for unlimited designs."
            activeSheet = .pro
            return false
        }

        var spec = candidate.candidateSpec.normalised()
        spec.updatedAt = Date()

        store.save(spec, makeDefault: aiMakeGeneratedDefault)
        defaultSpecID = store.defaultSpecID()
        lastWidgetRefreshAt = Date()

        aiStatusMessage = formatCandidateStatusMessage(
            candidate,
            title: "Review mode is enabled. Applied and saved."
        )

        aiPrompt = ""

        refreshSavedSpecs(preservingSelection: false)
        selectedSpecID = spec.id
        applySpec(spec)
        saveStatusMessage = "Generated design saved.\nWidgets refreshed."

        return true
    }

    // MARK: - Helpers

    private var aiHasCapacityToSaveAnotherDesign: Bool {
        if proManager.isProUnlocked { return true }
        return savedSpecs.count < WidgetWeaverEntitlements.maxFreeDesigns
    }

    private func formatCandidateStatusMessage(_ candidate: WidgetSpecAICandidate, title: String) -> String {
        var lines: [String] = []
        lines.reserveCapacity(18)

        lines.append(title)

        let availability = String(describing: candidate.sourceAvailability)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !availability.isEmpty {
            lines.append(availability)
        }

        if candidate.isFallback {
            lines.append("Used deterministic rules.")
        }

        let summaryLines = normaliseLines(candidate.changeSummary)
        if !summaryLines.isEmpty {
            lines.append("")
            lines.append(contentsOf: summaryLines)
        }

        let warningLines = normaliseLines(candidate.warnings)
        if !warningLines.isEmpty {
            lines.append("")
            lines.append("Warnings:")
            lines.append(contentsOf: warningLines.map { "• \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private func normaliseLines(_ value: Any) -> [String] {
        if let lines = value as? [String] {
            return lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return [] }
            return trimmed
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let fallback = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? [] : [fallback]
    }
}
