//
//  WWInsertableTextView.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import SwiftUI
import UIKit

struct WWInsertableTextView: UIViewRepresentable {
    let placeholder: String
    let accessibilityIdentifier: String?
    let minHeight: CGFloat

    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var insertionRequest: WWTextInsertionRequest?

    init(
        placeholder: String,
        accessibilityIdentifier: String? = nil,
        minHeight: CGFloat = 34,
        text: Binding<String>,
        isFocused: Binding<Bool>,
        insertionRequest: Binding<WWTextInsertionRequest?>
    ) {
        self.placeholder = placeholder
        self.accessibilityIdentifier = accessibilityIdentifier
        self.minHeight = minHeight
        self._text = text
        self._isFocused = isFocused
        self._insertionRequest = insertionRequest
    }

    func makeUIView(context: Context) -> WWGrowingTextView {
        let view = WWGrowingTextView(minHeight: minHeight)
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = UIColor.label
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        view.isScrollEnabled = false
        view.keyboardDismissMode = .interactive
        view.delegate = context.coordinator
        view.placeholderText = placeholder

        if let accessibilityIdentifier {
            view.accessibilityIdentifier = accessibilityIdentifier
        }

        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return view
    }

    func updateUIView(_ uiView: WWGrowingTextView, context: Context) {
        context.coordinator.parent = self

        if uiView.placeholderText != placeholder {
            uiView.placeholderText = placeholder
        }

        if uiView.accessibilityIdentifier != accessibilityIdentifier, let accessibilityIdentifier {
            uiView.accessibilityIdentifier = accessibilityIdentifier
        }

        if uiView.text != text {
            context.coordinator.withProgrammaticUpdate {
                uiView.text = text
                uiView.updatePlaceholderVisibility()
            }
        }

        if isFocused {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
                context.coordinator.restoreSelectionIfPossible(on: uiView)
            }
        } else {
            if uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }

        if let req = insertionRequest, req.id != context.coordinator.lastAppliedInsertionID {
            let currentText = text
            let selection = context.coordinator.clampedSelection(for: currentText)
            let outcome = WWTextInsertion.apply(snippet: req.snippet, to: currentText, selectedRange: selection)

            context.coordinator.lastAppliedInsertionID = req.id
            context.coordinator.lastKnownSelection = outcome.selection

            context.coordinator.withProgrammaticUpdate {
                uiView.text = outcome.text
                uiView.selectedRange = outcome.selection
                uiView.updatePlaceholderVisibility()
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

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: WWInsertableTextView

        var lastAppliedInsertionID: UUID?
        var lastKnownSelection: NSRange = NSRange(location: 0, length: 0)

        private var isProgrammaticUpdate: Bool = false

        init(parent: WWInsertableTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            parent.text = textView.text ?? ""
            updateSelection(from: textView)
            (textView as? WWGrowingTextView)?.updatePlaceholderVisibility()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.isFocused = true
            }
            updateSelection(from: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.isFocused = false
            }
            updateSelection(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateSelection(from: textView)
        }

        private func updateSelection(from textView: UITextView) {
            lastKnownSelection = textView.selectedRange
        }

        func restoreSelectionIfPossible(on textView: UITextView) {
            let currentText = textView.text ?? ""
            textView.selectedRange = clampedSelection(for: currentText)
        }

        func clampedSelection(for text: String) -> NSRange {
            let length = text.utf16.count
            let location = min(max(0, lastKnownSelection.location), length)
            let maxLen = length - location
            let selLen = min(max(0, lastKnownSelection.length), maxLen)
            return NSRange(location: location, length: selLen)
        }

        func withProgrammaticUpdate(_ work: () -> Void) {
            isProgrammaticUpdate = true
            work()
            isProgrammaticUpdate = false
        }
    }
}

final class WWGrowingTextView: UITextView {
    private let placeholderLabel: UILabel = UILabel()
    private let minHeight: CGFloat
    private var lastIntrinsicHeight: CGFloat = 0

    var placeholderText: String = "" {
        didSet {
            placeholderLabel.text = placeholderText
        }
    }

    init(minHeight: CGFloat) {
        self.minHeight = minHeight
        super.init(frame: .zero, textContainer: nil)
        installPlaceholder()
    }

    required init?(coder: NSCoder) {
        self.minHeight = 34
        super.init(coder: coder)
        installPlaceholder()
    }

    override var intrinsicContentSize: CGSize {
        if isScrollEnabled {
            return super.intrinsicContentSize
        }
        let h = max(contentSize.height, minHeight)
        return CGSize(width: UIView.noIntrinsicMetric, height: h)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutPlaceholderIfNeeded()

        let targetHeight = max(contentSize.height, minHeight)
        if abs(targetHeight - lastIntrinsicHeight) > 0.5 {
            lastIntrinsicHeight = targetHeight
            invalidateIntrinsicContentSize()
        }
    }

    func updatePlaceholderVisibility() {
        let isEmpty = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        placeholderLabel.isHidden = !isEmpty
    }

    private func installPlaceholder() {
        placeholderLabel.font = UIFont.preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = UIColor.placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.isHidden = true

        addSubview(placeholderLabel)
        updatePlaceholderVisibility()
    }

    private func layoutPlaceholderIfNeeded() {
        let inset = textContainerInset
        let x = inset.left + textContainer.lineFragmentPadding
        let y = inset.top
        let w = max(0, bounds.width - x - inset.right - textContainer.lineFragmentPadding)

        let size = placeholderLabel.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
        placeholderLabel.frame = CGRect(x: x, y: y, width: w, height: size.height)
        updatePlaceholderVisibility()
    }
}
