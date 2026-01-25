//
//  WidgetWeaverEditorTextToolSection.swift
//  WidgetWeaver
//
//  Created by . . on 1/25/26.
//

import SwiftUI
import UIKit

struct WidgetWeaverEditorTextToolSection: View {
    @Binding var designName: String
    @Binding var primaryText: String
    @Binding var secondaryText: String

    let matchedSetEnabled: Bool
    let editingFamilyLabel: String
    let isProUnlocked: Bool

    @FocusState private var focusedField: FocusedField?
    @State private var showInsertPicker: Bool = false
    @State private var insertTarget: InsertTarget = .primary

    private enum FocusedField: Hashable {
        case designName
        case primaryText
        case secondaryText
    }

    private enum InsertTarget: Hashable {
        case primary
        case secondary
    }

    var body: some View {
        Section {
            TextField("Design name", text: $designName)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("EditorTextField.DesignName")
                .focused($focusedField, equals: .designName)

            variableTextFieldRow(
                title: "Primary text",
                text: $primaryText,
                focusedFieldValue: .primaryText,
                insertTarget: .primary,
                accessibilityID: "EditorTextField.PrimaryText"
            )

            templateFeedbackRows(for: primaryText, fieldID: "PrimaryText")

            variableTextFieldRow(
                title: "Secondary text (optional)",
                text: $secondaryText,
                focusedFieldValue: .secondaryText,
                insertTarget: .secondary,
                accessibilityID: "EditorTextField.SecondaryText"
            )

            templateFeedbackRows(for: secondaryText, fieldID: "SecondaryText")

            if matchedSetEnabled {
                Text("Text fields are currently editing: \(editingFamilyLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Text")
        } footer: {
            Text("Tap \(Image(systemName: "curlybraces.square")) to insert variables. Preview appears when templates are detected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showInsertPicker) {
            NavigationStack {
                WidgetWeaverVariableInsertPickerView(
                    isProUnlocked: isProUnlocked,
                    customVariables: WidgetWeaverVariableStore.shared.loadAll(),
                    onInsert: { snippet in
                        insertSnippet(snippet)
                    }
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField == .primaryText || focusedField == .secondaryText {
                    Spacer()

                    Button {
                        openInsertPickerForFocusedField()
                    } label: {
                        Label("Insert variable", systemImage: "curlybraces.square")
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        let headerID = "EditorSectionHeader." + title.replacingOccurrences(of: " ", with: "_")

        return Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityIdentifier(headerID)
    }

    private func templateFeedbackRows(for raw: String, fieldID: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let hasDelimiters = trimmed.contains("{{") || trimmed.contains("}}")
        let isUnbalanced = hasDelimiters && hasUnbalancedTemplateDelimiters(trimmed)
        let isTimeDependent = hasDelimiters && !isUnbalanced && WidgetWeaverVariableTemplate.isTimeDependentTemplate(trimmed)

        let alignedStart = WidgetWeaverRenderClock.alignedTimelineStartDate(
            interval: 1.0,
            now: WidgetWeaverRenderClock.now
        )

        return Group {
            if !hasDelimiters {
                EmptyView()
            } else if isUnbalanced {
                Label("Unbalanced {{ }} delimiters", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("EditorTextField.TemplateWarning.\(fieldID)")
            } else if isTimeDependent {
                TimelineView(.periodic(from: alignedStart, by: 1.0)) { ctx in
                    templatePreviewRow(template: trimmed, now: ctx.date, fieldID: fieldID)
                }
            } else {
                templatePreviewRow(template: trimmed, now: WidgetWeaverRenderClock.now, fieldID: fieldID)
            }
        }
    }

    private func templatePreviewRow(template: String, now: Date, fieldID: String) -> some View {
        let rendered = renderTemplatePreview(template, now: now)

        return VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(rendered.isEmpty ? "—" : rendered)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .contextMenu {
            Button("Copy preview") {
                UIPasteboard.general.string = rendered
            }
        }
        .accessibilityIdentifier("EditorTextField.TemplatePreview.\(fieldID)")
    }

    private func variableTextFieldRow(
        title: String,
        text: Binding<String>,
        focusedFieldValue: FocusedField,
        insertTarget: InsertTarget,
        accessibilityID: String
    ) -> some View {
        HStack(spacing: 10) {
            TextField(title, text: text)
                .accessibilityIdentifier(accessibilityID)
                .focused($focusedField, equals: focusedFieldValue)

            Button {
                self.insertTarget = insertTarget
                showInsertPicker = true
            } label: {
                Image(systemName: "curlybraces.square")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Insert variable")
        }
    }

    private func openInsertPickerForFocusedField() {
        switch focusedField {
        case .primaryText:
            insertTarget = .primary
        case .secondaryText:
            insertTarget = .secondary
        default:
            return
        }

        showInsertPicker = true
    }

    private func insertSnippet(_ snippet: String) {
        switch insertTarget {
        case .primary:
            primaryText = appendingSnippet(snippet, to: primaryText)
        case .secondary:
            secondaryText = appendingSnippet(snippet, to: secondaryText)
        }
    }

    private func appendingSnippet(_ snippet: String, to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return snippet
        }

        if let last = text.last, last == "\n" || last == " " {
            return text + snippet
        }

        return text + " " + snippet
    }

    private func renderTemplatePreview(_ template: String, now: Date) -> String {
        var vars: [String: String] = [:]

        if isProUnlocked {
            vars = WidgetWeaverVariableStore.shared.loadAll()
        }

        let builtIns = WidgetWeaverVariableTemplate.builtInVariables(now: now)
        for (k, v) in builtIns where vars[k] == nil {
            vars[k] = v
        }

        for (k, v) in WidgetWeaverWeatherStore.shared.variablesDictionary(now: now) {
            vars[k] = v
        }

        for (k, v) in WidgetWeaverStepsStore.shared.variablesDictionary(now: now) {
            vars[k] = v
        }

        for (k, v) in WidgetWeaverActivityStore.shared.variablesDictionary(now: now) {
            vars[k] = v
        }

        return WidgetWeaverVariableTemplate.render(template, variables: vars, now: now, maxPasses: 3)
    }

    private func hasUnbalancedTemplateDelimiters(_ s: String) -> Bool {
        var balance = 0
        var i = s.startIndex
        let end = s.endIndex

        while i < end {
            let ch = s[i]

            if ch == "{" {
                let next = s.index(after: i)
                if next < end, s[next] == "{" {
                    balance += 1
                    i = s.index(after: next)
                    continue
                }
            } else if ch == "}" {
                let next = s.index(after: i)
                if next < end, s[next] == "}" {
                    if balance == 0 { return true }
                    balance -= 1
                    i = s.index(after: next)
                    continue
                }
            }

            i = s.index(after: i)
        }

        return balance != 0
    }
}
