//
//  WWInsertableTextField.swift
//  WidgetWeaver
//
//  Created by . . on 1/26/26.
//

import SwiftUI
import UIKit

struct WWTextInsertionRequest: Identifiable, Hashable {
    let id: UUID
    let snippet: String

    init(snippet: String) {
        self.id = UUID()
        self.snippet = snippet
    }
}

struct WWInsertableTextField: UIViewRepresentable {
    let placeholder: String
    let accessibilityIdentifier: String?

    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var insertionRequest: WWTextInsertionRequest?

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor.label
        field.placeholder = placeholder
        field.delegate = context.coordinator
        field.autocorrectionType = .default
        field.autocapitalizationType = .sentences
        field.returnKeyType = .done
        field.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)

        if let accessibilityIdentifier {
            field.accessibilityIdentifier = accessibilityIdentifier
        }

        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self

        if uiView.placeholder != placeholder {
            uiView.placeholder = placeholder
        }

        if uiView.accessibilityIdentifier != accessibilityIdentifier, let accessibilityIdentifier {
            uiView.accessibilityIdentifier = accessibilityIdentifier
        }

        if (uiView.text ?? "") != text {
            context.coordinator.withProgrammaticUpdate {
                uiView.text = text
            }
        }

        let wasFocused = context.coordinator.lastSwiftUIIsFocused
        context.coordinator.lastSwiftUIIsFocused = isFocused

        if isFocused {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
                context.coordinator.restoreSelectionIfPossible(on: uiView)
            }
        } else {
            if wasFocused, uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }

        if let req = insertionRequest, req.id != context.coordinator.lastAppliedInsertionID {
            let currentText = text
            let selection = context.coordinator.clampedSelection(for: currentText)
            let outcome = WWTextInsertion.apply(snippet: req.snippet, to: currentText, selectedRange: selection)

            context.coordinator.lastAppliedInsertionID = req.id
            context.coordinator.lastKnownSelection = outcome.selection
            context.coordinator.hasRecordedSelection = true

            context.coordinator.withProgrammaticUpdate {
                uiView.text = outcome.text
                context.coordinator.setSelectedRange(outcome.selection, in: uiView)
            }

            DispatchQueue.main.async {
                self.text = outcome.text
                self.insertionRequest = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: WWInsertableTextField

        var lastAppliedInsertionID: UUID?
        var lastKnownSelection: NSRange = NSRange(location: 0, length: 0)

        var lastSwiftUIIsFocused: Bool = false
        var hasRecordedSelection: Bool = false

        private var isProgrammaticUpdate: Bool = false

        init(parent: WWInsertableTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ sender: UITextField) {
            guard !isProgrammaticUpdate else { return }
            parent.text = sender.text ?? ""
            updateSelection(from: sender)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            updateSelection(from: textField)
            DispatchQueue.main.async {
                self.parent.isFocused = true
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            updateSelection(from: textField)
            DispatchQueue.main.async {
                self.parent.isFocused = false
            }
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            updateSelection(from: textField)
        }

        private func updateSelection(from textField: UITextField) {
            guard let range = textField.selectedTextRange else { return }

            let location = textField.offset(from: textField.beginningOfDocument, to: range.start)
            let length = textField.offset(from: range.start, to: range.end)

            lastKnownSelection = NSRange(location: max(0, location), length: max(0, length))
            hasRecordedSelection = true
        }

        func restoreSelectionIfPossible(on textField: UITextField) {
            let currentText = textField.text ?? ""
            if hasRecordedSelection {
                let selection = clampedSelection(for: currentText)
                setSelectedRange(selection, in: textField)
            } else {
                let end = currentText.utf16.count
                setSelectedRange(NSRange(location: end, length: 0), in: textField)
            }
        }

        func clampedSelection(for text: String) -> NSRange {
            let length = text.utf16.count
            let location = min(max(0, lastKnownSelection.location), length)
            let maxLen = length - location
            let selLen = min(max(0, lastKnownSelection.length), maxLen)
            return NSRange(location: location, length: selLen)
        }

        func setSelectedRange(_ range: NSRange, in textField: UITextField) {
            guard let start = textField.position(from: textField.beginningOfDocument, offset: range.location) else { return }
            guard let end = textField.position(from: start, offset: range.length) else { return }
            guard let textRange = textField.textRange(from: start, to: end) else { return }
            textField.selectedTextRange = textRange
        }

        func withProgrammaticUpdate(_ work: () -> Void) {
            isProgrammaticUpdate = true
            work()
            isProgrammaticUpdate = false
        }
    }
}

enum WWTextInsertion {
    static func apply(snippet: String, to text: String, selectedRange: NSRange) -> (text: String, selection: NSRange) {
        let length = text.utf16.count

        let safeLocation = min(max(0, selectedRange.location), length)
        let safeLen = min(max(0, selectedRange.length), length - safeLocation)
        let safeRange = NSRange(location: safeLocation, length: safeLen)

        guard let replaceRange = Range(safeRange, in: text) else {
            let atEnd = NSRange(location: length, length: 0)
            let outcome = apply(snippet: snippet, to: text, selectedRange: atEnd)
            return (outcome.text, outcome.selection)
        }

        let startIndex = replaceRange.lowerBound
        let endIndex = replaceRange.upperBound

        let beforeChar: Character? = startIndex > text.startIndex ? text[text.index(before: startIndex)] : nil
        let afterChar: Character? = endIndex < text.endIndex ? text[endIndex] : nil

        let snippetStartsWithWhitespace = snippet.first?.isWhitespace == true || snippet.first?.isNewline == true
        let snippetEndsWithWhitespace = snippet.last?.isWhitespace == true || snippet.last?.isNewline == true

        let beforeIsSeparator: Bool = {
            guard let beforeChar else { return true }
            return isSeparator(beforeChar)
        }()

        let afterIsSeparator: Bool = {
            guard let afterChar else { return true }
            return isSeparator(afterChar)
        }()

        let needsLeadingSpace = !beforeIsSeparator && !snippetStartsWithWhitespace
        let needsTrailingSpace = !afterIsSeparator && !snippetEndsWithWhitespace

        var inserted = snippet
        if needsLeadingSpace {
            inserted = " " + inserted
        }
        if needsTrailingSpace {
            inserted += " "
        }

        var out = text
        out.replaceSubrange(replaceRange, with: inserted)

        let newCursor = safeRange.location + inserted.utf16.count
        let newSelection = NSRange(location: newCursor, length: 0)

        return (out, newSelection)
    }

    private static func isSeparator(_ ch: Character) -> Bool {
        if ch.isWhitespace || ch.isNewline { return true }
        let punctuation = "{}[]()<>.,;:!?/\\\"'“”‘’—–-"
        return punctuation.contains(ch)
    }
}
