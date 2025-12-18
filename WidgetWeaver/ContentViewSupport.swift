//
//  ContentViewSupport.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation
import SwiftUI
import UIKit
import StoreKit
import WidgetKit

// MARK: - Widget workflow help

struct WidgetWorkflowHelpView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Widgets update when the saved design changes and WidgetKit reloads timelines.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("How widgets update")
                }

                Section {
                    Text("Each widget instance can follow \"Default (App)\" or a specific saved design.")
                        .foregroundStyle(.secondary)
                    Text("To change this: long-press the widget → Edit Widget → Design.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Design selection")
                }

                Section {
                    Text("Try \"Refresh Widgets\" in the app, then wait a moment.")
                        .foregroundStyle(.secondary)
                    Text("If it still doesn’t update, reselect the Design in Edit Widget.\nRemoving and re-adding the widget is only needed after major schema changes.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("If a widget doesn’t change")
                }
            }
            .navigationTitle("Widgets")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Editor background

struct EditorBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color.accentColor.opacity(0.22), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 640
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.accentColor.opacity(0.10), Color.clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 760
            )
            .ignoresSafeArea()
        }
    }
}

enum Keyboard {
    static func dismiss() {
        Task { @MainActor in
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

// MARK: - Pro (StoreKit 2) (Milestone 8)

@MainActor
final class WidgetWeaverProManager: ObservableObject {
    static let productID = "com.conornolan.widgetweaver.pro"

    @Published private(set) var isProUnlocked: Bool = WidgetWeaverEntitlements.isProUnlocked
    @Published private(set) var product: Product?
    @Published private(set) var isBusy: Bool = false
    @Published var statusMessage: String = ""

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { await observeTransactionUpdates() }
        Task { await refresh() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        await loadProduct()
        await refreshEntitlementFromStoreKitIfNeeded()
    }

    func purchasePro() async {
        guard let product else {
            statusMessage = "Product info unavailable."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    WidgetWeaverEntitlements.setProUnlocked(true)
                    isProUnlocked = true
                    statusMessage = "Pro unlocked."
                    await transaction.finish()

                case .unverified:
                    statusMessage = "Purchase could not be verified."
                }

            case .userCancelled:
                statusMessage = "Purchase cancelled."

            case .pending:
                statusMessage = "Purchase pending."

            @unknown default:
                statusMessage = "Purchase did not complete."
            }
        } catch {
            statusMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await AppStore.sync()
            await refreshEntitlementFromStoreKitIfNeeded()
            statusMessage = isProUnlocked ? "Purchases restored." : "No purchases found."
        } catch {
            statusMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            statusMessage = "Store unavailable: \(error.localizedDescription)"
        }
    }

    private func refreshEntitlementFromStoreKitIfNeeded() async {
        if WidgetWeaverEntitlements.isProUnlocked {
            isProUnlocked = true
            return
        }

        var found = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.productID == Self.productID {
                found = true
                break
            }
        }

        if found {
            WidgetWeaverEntitlements.setProUnlocked(true)
            isProUnlocked = true
        } else {
            isProUnlocked = WidgetWeaverEntitlements.isProUnlocked
        }
    }

    private func observeTransactionUpdates() async {
        for await update in Transaction.updates {
            guard case .verified(let transaction) = update else { continue }

            if transaction.productID == Self.productID {
                WidgetWeaverEntitlements.setProUnlocked(true)
                isProUnlocked = true
            }

            await transaction.finish()
        }
    }
}

private struct ProFeatureRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "checkmark.seal.fill")
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct WidgetWeaverProView: View {
    @ObservedObject var manager: WidgetWeaverProManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if manager.isProUnlocked {
                        Label("WidgetWeaver Pro is unlocked.", systemImage: "checkmark.seal.fill")
                        Text("Matched sets, variables, and unlimited designs are enabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("WidgetWeaver Pro", systemImage: "crown.fill")
                        Text("Unlock matched sets, variables, and unlimited designs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Status")
                }

                Section {
                    ProFeatureRow(
                        title: "Unlimited designs",
                        subtitle: "Free tier is limited to \(WidgetWeaverEntitlements.maxFreeDesigns) saved designs."
                    )
                    ProFeatureRow(
                        title: "Matched sets",
                        subtitle: "Per-size overrides for Small/Medium/Large while sharing style and typography."
                    )
                    ProFeatureRow(
                        title: "Variables + Shortcuts",
                        subtitle: "Use {{key}} templates plus App Intents actions to update widget values."
                    )
                } header: {
                    Text("What Pro unlocks")
                }

                Section {
                    if manager.isProUnlocked {
                        Button { dismiss() } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                    } else {
                        Button {
                            Task { await manager.purchasePro() }
                        } label: {
                            let price = manager.product?.displayPrice ?? "…"
                            Label("Unlock Pro (\(price))", systemImage: "crown.fill")
                        }
                        .disabled(manager.isBusy || manager.product == nil)

                        Button {
                            Task { await manager.restorePurchases() }
                        } label: {
                            Label("Restore Purchases", systemImage: "arrow.clockwise")
                        }
                        .disabled(manager.isBusy)
                    }

                    if manager.isBusy {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Working…").foregroundStyle(.secondary)
                        }
                    }

                    if !manager.statusMessage.isEmpty {
                        Text(manager.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Actions")
                }
            }
            .navigationTitle("Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await manager.refresh() }
        }
    }
}

// MARK: - Inspector

struct WidgetWeaverDesignInspectorView: View {
    let spec: WidgetSpec

    @State private var family: WidgetFamily
    @State private var statusMessage: String = ""

    @Environment(\.dismiss) private var dismiss

    init(spec: WidgetSpec, initialFamily: WidgetFamily = .systemSmall) {
        self.spec = spec
        _family = State(initialValue: initialFamily)
    }

    var body: some View {
        NavigationStack {
            List {
                overviewSection
                resolutionSection
                variablesSection
                jsonLinksSection
                imagesSection

                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var overviewSection: some View {
        Section {
            LabeledContent("Name", value: spec.normalised().name)
            LabeledContent("ID", value: spec.id.uuidString)
                .font(.caption)
                .textSelection(.enabled)

            LabeledContent("Schema version", value: "\(spec.normalised().version)")
            LabeledContent("Updated", value: spec.normalised().updatedAt.formatted(date: .abbreviated, time: .standard))

            let hasMatched = (spec.normalised().matchedSet != nil)
            LabeledContent("Matched set", value: hasMatched ? "Yes" : "No")
        } header: {
            Text("Overview")
        }
    }

    private var resolutionSection: some View {
        Section {
            Picker("Preview size", selection: $family) {
                Text("Small").tag(WidgetFamily.systemSmall)
                Text("Medium").tag(WidgetFamily.systemMedium)
                Text("Large").tag(WidgetFamily.systemLarge)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            let resolved = resolvedSpec(for: family)

            LabeledContent("Resolved name", value: resolved.name)
            LabeledContent("Primary", value: resolved.primaryText)

            if let sec = resolved.secondaryText, !sec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LabeledContent("Secondary", value: sec)
            } else {
                LabeledContent("Secondary", value: "—")
                    .foregroundStyle(.secondary)
            }

            if let sym = resolved.symbol {
                Text("Symbol: \(sym.name) • \(Int(sym.size))pt • \(sym.weight.rawValue) • \(sym.renderingMode.rawValue) • \(sym.tint.rawValue) • \(sym.placement.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Symbol: —")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let img = resolved.image {
                Text("Image: \(img.fileName) • \(img.contentMode.rawValue) • h=\(Int(img.height)) • r=\(Int(img.cornerRadius))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Image: —")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Layout: \(resolved.layout.axis.rawValue) • \(resolved.layout.alignment.rawValue) • spacing=\(Int(resolved.layout.spacing)) • lines(s)=\(resolved.layout.primaryLineLimitSmall) • lines=\(resolved.layout.primaryLineLimit)/\(resolved.layout.secondaryLineLimit)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("Style: \(resolved.style.background.rawValue) • \(resolved.style.accent.rawValue) • pad=\(Int(resolved.style.padding)) • r=\(Int(resolved.style.cornerRadius)) • fonts=\(resolved.style.nameTextStyle.rawValue)/\(resolved.style.primaryTextStyle.rawValue)/\(resolved.style.secondaryTextStyle.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

        } header: {
            Text("Resolved (matched set + variables)")
        } footer: {
            Text("Resolution matches the widget render path: matched-set variant first, then variables.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var variablesSection: some View {
        Section {
            if WidgetWeaverEntitlements.isProUnlocked {
                let vars = WidgetWeaverVariableStore.shared.loadAll()
                LabeledContent("Saved variables", value: "\(vars.count)")

                if vars.isEmpty {
                    Text("No variables saved.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(vars.keys.sorted().prefix(6)), id: \.self) { key in
                        let val = vars[key] ?? ""
                        LabeledContent(key, value: val.isEmpty ? " " : val)
                    }
                }
            } else {
                Text("Variables are locked (Pro).")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Variables")
        }
    }

    private var jsonLinksSection: some View {
        let base = spec.normalised()
        let resolved = resolvedSpec(for: family)

        let baseJSON = jsonString(for: base)
        let resolvedJSON = jsonString(for: resolved)

        let exchangeJSON = exchangeJSONString(for: base)

        return Section {
            NavigationLink {
                WidgetWeaverMonospaceTextView(
                    title: "Design JSON",
                    text: baseJSON,
                    onCopy: { copyToClipboard(baseJSON, message: "Copied design JSON.") }
                )
            } label: {
                Label("Design JSON", systemImage: "doc.plaintext")
            }

            NavigationLink {
                WidgetWeaverMonospaceTextView(
                    title: "Resolved JSON",
                    text: resolvedJSON,
                    onCopy: { copyToClipboard(resolvedJSON, message: "Copied resolved JSON.") }
                )
            } label: {
                Label("Resolved JSON (\(familyLabel(family)))", systemImage: "doc.text.magnifyingglass")
            }

            NavigationLink {
                WidgetWeaverMonospaceTextView(
                    title: "Exchange JSON (no images)",
                    text: exchangeJSON,
                    onCopy: { copyToClipboard(exchangeJSON, message: "Copied exchange JSON.") }
                )
            } label: {
                Label("Exchange JSON (no images)", systemImage: "shippingbox")
            }

        } header: {
            Text("JSON")
        } footer: {
            Text("Exchange JSON matches the import/export format (with images omitted).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var imagesSection: some View {
        let infos = imageInfos(in: spec.normalised())

        return Section {
            if infos.isEmpty {
                Text("No image references in this design.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(infos) { info in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.fileName)
                            .font(.subheadline.weight(.semibold))
                            .textSelection(.enabled)

                        Text(info.detailLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = info.fileName
                            statusMessage = "Copied image file name."
                        } label: {
                            Label("Copy file name", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        } header: {
            Text("Images")
        }
    }

    // MARK: - Helpers

    private func resolvedSpec(for family: WidgetFamily) -> WidgetSpec {
        let base = spec.normalised()
        return base
            .resolved(for: family)
            .resolvingVariables()
            .normalised()
    }

    private func familyLabel(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: return "Small"
        case .systemMedium: return "Medium"
        case .systemLarge: return "Large"
        default: return "Small"
        }
    }

    private func jsonString<T: Encodable>(for value: T) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Encoding failed: \(error.localizedDescription)"
        }
    }

    private func exchangeJSONString(for spec: WidgetSpec) -> String {
        do {
            let data = try WidgetSpecStore.shared.exportExchangeData(specs: [spec], includeImages: false)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Export failed: \(error.localizedDescription)"
        }
    }

    private func copyToClipboard(_ text: String, message: String) {
        UIPasteboard.general.string = text
        statusMessage = message
    }

    private struct ImageInfo: Identifiable {
        let id: String
        let fileName: String
        let detailLine: String
    }

    private func imageInfos(in spec: WidgetSpec) -> [ImageInfo] {
        var names: Set<String> = []

        if let img = spec.image?.fileName, !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            names.insert(img)
        }

        if let matched = spec.matchedSet {
            if let v = matched.small, let img = v.image?.fileName, !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                names.insert(img)
            }
            if let v = matched.medium, let img = v.image?.fileName, !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                names.insert(img)
            }
            if let v = matched.large, let img = v.image?.fileName, !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                names.insert(img)
            }
        }

        let sorted = names.sorted()
        return sorted.map { fileName in
            let url = AppGroup.imageFileURL(fileName: fileName)
            let exists = FileManager.default.fileExists(atPath: url.path)

            var bytesText = "unknown size"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? NSNumber {
                bytesText = ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
            }

            let detail = exists ? "On disk • \(bytesText)" : "Missing on disk"
            return ImageInfo(id: fileName, fileName: fileName, detailLine: detail)
        }
    }
}

private struct WidgetWeaverMonospaceTextView: View {
    let title: String
    let text: String
    let onCopy: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(16)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Copy") { onCopy() }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}
