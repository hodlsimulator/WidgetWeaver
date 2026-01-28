//
//  WidgetWeaverAIReviewSheet.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import SwiftUI
import WidgetKit

struct WidgetWeaverAIReviewSheet: View {

    enum Mode: Hashable {
        case generate
        case patch

        var title: String {
            switch self {
            case .generate:
                return "Review generated design"
            case .patch:
                return "Review patch"
            }
        }

        var applyButtonTitle: String {
            "Apply"
        }
    }

    let candidate: WidgetSpecAICandidate
    let mode: Mode

    let onApply: () -> Void
    let onCancel: () -> Void

    @State private var previewFamily: WidgetFamily = .systemSmall

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    previewCard

                    summaryCard

                    warningsCard

                    if candidate.isFallback {
                        fallbackCard
                    }
                }
                .padding(16)
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(mode.applyButtonTitle) {
                        onApply()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(candidate.candidateSpec.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text("Candidate")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }

            Text(candidate.sourceAvailability)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !candidate.candidateSpec.primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(candidate.candidateSpec.primaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Picker("Size", selection: $previewFamily) {
                    Text("Small").tag(WidgetFamily.systemSmall)
                    Text("Medium").tag(WidgetFamily.systemMedium)
                    Text("Large").tag(WidgetFamily.systemLarge)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }

            WidgetPreview(
                spec: candidate.candidateSpec,
                family: previewFamily,
                maxHeight: previewMaxHeight(for: previewFamily),
                isLive: false
            )
            .frame(maxWidth: .infinity)
            .frame(height: previewMaxHeight(for: previewFamily))
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Change summary")
                .font(.caption)
                .foregroundStyle(.secondary)

            let lines = normalisedLines(candidate.changeSummary)
            if lines.isEmpty {
                Text("No summary available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text("• \(line)")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Warnings")
                .font(.caption)
                .foregroundStyle(.secondary)

            let lines = normalisedLines(candidate.warnings)
            if lines.isEmpty {
                Text("None.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text("• \(line)")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var fallbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Used deterministic rules", systemImage: "gearshape.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("This candidate was generated without the on-device model.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func previewMaxHeight(for family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemLarge:
            return 320
        case .systemMedium, .systemSmall:
            return 180
        default:
            return 180
        }
    }

    private func normalisedLines(_ lines: [String]) -> [String] {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
