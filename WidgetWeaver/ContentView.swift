//
//  ContentView.swift
//  WidgetWeaver
//
//  Created by . . on 12/16/25.
//

import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var name: String = ""
    @State private var primaryText: String = ""
    @State private var secondaryText: String = ""

    @State private var axis: LayoutAxisToken = LayoutSpec.defaultLayout.axis
    @State private var alignment: LayoutAlignmentToken = LayoutSpec.defaultLayout.alignment
    @State private var spacing: Double = LayoutSpec.defaultLayout.spacing
    @State private var showSecondaryInSmall: Bool = LayoutSpec.defaultLayout.showSecondaryInSmall

    @State private var padding: Double = StyleSpec.defaultStyle.padding
    @State private var cornerRadius: Double = StyleSpec.defaultStyle.cornerRadius
    @State private var background: BackgroundToken = StyleSpec.defaultStyle.background
    @State private var accent: AccentToken = StyleSpec.defaultStyle.accent
    @State private var primaryTextStyle: TextStyleToken = StyleSpec.defaultStyle.primaryTextStyle
    @State private var secondaryTextStyle: TextStyleToken = StyleSpec.defaultStyle.secondaryTextStyle

    @State private var lastSavedAt: Date?

    private let store = WidgetSpecStore.shared

    var body: some View {
        NavigationStack {
            Form {
                specSection
                layoutSection
                styleSection
                previewSection
                actionsSection

                if let lastSavedAt {
                    Section("Status") {
                        Text("Saved: \(lastSavedAt.formatted(date: .abbreviated, time: .standard))")
                    }
                }
            }
            .navigationTitle("WidgetWeaver")
            .onAppear { load() }
        }
    }

    private var specSection: some View {
        Section("Spec") {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)

            TextField("Primary text", text: $primaryText)

            TextField("Secondary text (optional)", text: $secondaryText)
        }
    }

    private var layoutSection: some View {
        Section("Layout") {
            Picker("Axis", selection: $axis) {
                ForEach(LayoutAxisToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Alignment", selection: $alignment) {
                ForEach(LayoutAlignmentToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Spacing")
                    Spacer()
                    Text("\(Int(spacing))")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $spacing, in: 0...24, step: 1)
            }

            Toggle("Show secondary in Small", isOn: $showSecondaryInSmall)
        }
    }

    private var styleSection: some View {
        Section("Style") {
            Picker("Background", selection: $background) {
                ForEach(BackgroundToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Accent", selection: $accent) {
                ForEach(AccentToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Padding")
                    Spacer()
                    Text("\(Int(padding))")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $padding, in: 0...24, step: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Corner radius")
                    Spacer()
                    Text("\(Int(cornerRadius))")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $cornerRadius, in: 0...44, step: 1)
            }

            Picker("Primary font", selection: $primaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Secondary font", selection: $secondaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    PreviewTile(
                        title: "Small",
                        family: .systemSmall,
                        spec: draftSpec(),
                        cornerRadius: cornerRadius
                    )

                    PreviewTile(
                        title: "Medium",
                        family: .systemMedium,
                        spec: draftSpec(),
                        cornerRadius: cornerRadius
                    )

                    PreviewTile(
                        title: "Large",
                        family: .systemLarge,
                        spec: draftSpec(),
                        cornerRadius: cornerRadius
                    )
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Save to Widget") { save() }
                .disabled(primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Load Saved") { load() }

            Button("Reset to Default", role: .destructive) { resetToDefault() }
        }
    }

    private func draftSpec() -> WidgetSpec {
        let layout = LayoutSpec(
            axis: axis,
            alignment: alignment,
            spacing: spacing,
            showSecondaryInSmall: showSecondaryInSmall,
            primaryLineLimitSmall: LayoutSpec.defaultLayout.primaryLineLimitSmall,
            primaryLineLimit: LayoutSpec.defaultLayout.primaryLineLimit,
            secondaryLineLimit: LayoutSpec.defaultLayout.secondaryLineLimit
        )

        let style = StyleSpec(
            padding: padding,
            cornerRadius: cornerRadius,
            background: background,
            accent: accent,
            nameTextStyle: .caption,
            primaryTextStyle: primaryTextStyle,
            secondaryTextStyle: secondaryTextStyle
        )

        return WidgetSpec(
            name: name,
            primaryText: primaryText,
            secondaryText: secondaryText.isEmpty ? nil : secondaryText,
            updatedAt: lastSavedAt ?? Date(),
            layout: layout,
            style: style
        )
        .normalised()
    }

    private func load() {
        let spec = store.load()

        name = spec.name
        primaryText = spec.primaryText
        secondaryText = spec.secondaryText ?? ""

        axis = spec.layout.axis
        alignment = spec.layout.alignment
        spacing = spec.layout.spacing
        showSecondaryInSmall = spec.layout.showSecondaryInSmall

        padding = spec.style.padding
        cornerRadius = spec.style.cornerRadius
        background = spec.style.background
        accent = spec.style.accent
        primaryTextStyle = spec.style.primaryTextStyle
        secondaryTextStyle = spec.style.secondaryTextStyle
    }

    private func save() {
        var spec = draftSpec()
        spec.updatedAt = Date()
        spec = spec.normalised()

        store.save(spec)
        lastSavedAt = spec.updatedAt

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
    }

    private func resetToDefault() {
        let spec = WidgetSpec.defaultSpec()
        store.save(spec)

        lastSavedAt = Date()
        load()

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
    }
}

private struct PreviewTile: View {
    let title: String
    let family: WidgetFamily
    let spec: WidgetSpec
    let cornerRadius: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            WidgetWeaverSpecView(spec: spec, family: family, context: .preview)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private var size: CGSize {
        switch family {
        case .systemSmall:
            return CGSize(width: 170, height: 170)
        case .systemMedium:
            return CGSize(width: 364, height: 170)
        case .systemLarge:
            return CGSize(width: 364, height: 382)
        default:
            return CGSize(width: 170, height: 170)
        }
    }
}
