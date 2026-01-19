//
//  ContentViewSupport.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation
import SwiftUI
import WidgetKit
import StoreKit

struct WidgetWorkflowHelpView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("WidgetWeaver has one Clock experience with two placement paths. Choose the path that matches the intent.")
                        .foregroundStyle(.secondary)

                    Text("Clock (Quick): add a standalone clock from the widget gallery. Fast to set up, with a compact, safe configuration.")
                        .foregroundStyle(.secondary)

                    Text("Clock (Designer): create a clock Design in the app, then add a WidgetWeaver widget and choose that Design in Edit Widget → Design. This path supports deeper customisation and stays consistent with other WidgetWeaver templates.")
                        .foregroundStyle(.secondary)

                    Text("If uncertain, start with Clock (Quick).")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Which clock should I use?")
                }

                Section {
                    Text("Widgets are snapshots. iOS refreshes them on its own schedule.")
                        .foregroundStyle(.secondary)
                    Text("WidgetWeaver also reloads widgets when you save a Design.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("How widgets update")
                }

                Section {
                    Text("To change a widget, long-press it → Edit Widget → choose a Design.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Design selection")
                }

                Section {
                    Text("If a widget doesn’t change, open WidgetWeaver and tap Refresh Widgets in More.")
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

@MainActor
final class WidgetWeaverProManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var ownedProducts: Set<String> = []
    @Published private(set) var latestTransaction: Transaction?
    @Published private(set) var errorMessage: String = ""

    private let proProductIDs: Set<String> = [
        "widgetweaver.pro.lifetime"
    ]

    init() {
        Task { await refreshEntitlementFromStoreKitIfNeeded() }
    }

    func refreshEntitlementFromStoreKitIfNeeded() async {
        if WidgetWeaverEntitlements.isProUnlocked {
            await refreshEntitlementFromStoreKit()
        }
    }

    func refreshEntitlementFromStoreKit() async {
        do {
            var owned: Set<String> = []
            var latest: Transaction?

            for await result in Transaction.currentEntitlements {
                switch result {
                case .verified(let transaction):
                    if proProductIDs.contains(transaction.productID) {
                        owned.insert(transaction.productID)
                        latest = transaction
                    }

                case .unverified:
                    break
                }
            }

            await MainActor.run {
                self.ownedProducts = owned
                self.latestTransaction = latest
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: Array(proProductIDs))
            await MainActor.run {
                self.products = products.sorted(by: { $0.displayName < $1.displayName })
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlementFromStoreKit()
                    await MainActor.run {
                        WidgetWeaverEntitlements.setProUnlocked(true)
                    }

                case .unverified:
                    await MainActor.run {
                        self.errorMessage = "Purchase could not be verified."
                    }
                }

            case .userCancelled:
                break

            case .pending:
                break

            @unknown default:
                break
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlementFromStoreKit()
            await MainActor.run {
                let unlocked = !ownedProducts.isEmpty
                WidgetWeaverEntitlements.setProUnlocked(unlocked)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}

struct WidgetWeaverProView: View {
    @ObservedObject var manager: WidgetWeaverProManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WidgetWeaver Pro")
                            .font(.title2.weight(.semibold))

                        Text("Unlock Pro templates, unlimited designs, and more advanced features.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if manager.products.isEmpty {
                        ProgressView()
                            .task {
                                await manager.loadProducts()
                            }
                    } else {
                        ForEach(manager.products, id: \.id) { product in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(product.displayName)
                                            .font(.headline)
                                        Text(product.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)

                                    Text(product.displayPrice)
                                        .font(.headline)
                                }

                                Button {
                                    Task { await manager.purchase(product) }
                                } label: {
                                    Text("Purchase")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(manager.ownedProducts.contains(product.id))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Purchase")
                } footer: {
                    if !manager.errorMessage.isEmpty {
                        Text(manager.errorMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Restore Purchases") {
                        Task { await manager.restore() }
                    }
                } header: {
                    Text("Restore")
                }

                if WidgetWeaverEntitlements.isProUnlocked {
                    Section {
                        Text("Pro is unlocked on this device.")
                            .foregroundStyle(.secondary)

                        if let tx = manager.latestTransaction {
                            Text("Latest transaction: \(tx.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Status")
                    }
                }
            }
            .navigationTitle("Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}


// MARK: - Preview

#Preview {
    WidgetWeaverProView(manager: WidgetWeaverProManager())
}


// MARK: - Design Inspector

@MainActor
struct WidgetWeaverDesignInspectorView: View {
    let spec: WidgetSpec
    let initialFamily: WidgetFamily

    @State private var family: WidgetFamily
    @State private var statusMessage: String = ""
    @State private var restrictToSmallOnly: Bool = false

    init(spec: WidgetSpec, initialFamily: WidgetFamily) {
        self.spec = spec
        self.initialFamily = initialFamily
        _family = State(initialValue: initialFamily)
    }

    var body: some View {
        NavigationStack {
            List {
                overviewSection
                resolutionSection
                widgetImageRenderSection
                variablesSection
                jsonLinksSection
                imagesSection

                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            statusMessage = "Reloading variables…"
                            WidgetWeaverVariableStore.shared.invalidateCache()
                            statusMessage = "Reloaded variables."
                        } label: {
                            Label("Reload variables", systemImage: "arrow.clockwise")
                        }

                        Button {
                            statusMessage = "Reloading designs…"
                            WidgetSpecStore.shared.invalidateCache()
                            statusMessage = "Reloaded designs."
                        } label: {
                            Label("Reload designs", systemImage: "arrow.clockwise")
                        }

                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                restrictToSmallOnly = spec.layout.template.isClock
                clampFamilyIfNeeded()
            }
        }
    }

    private func clampFamilyIfNeeded() {
        if restrictToSmallOnly, family != .systemSmall {
            family = .systemSmall
        }
    }

    private var overviewSection: some View {
        Section {
            LabeledContent("ID", value: spec.id.uuidString)
            LabeledContent("Name", value: spec.name)

            LabeledContent("Template", value: spec.layout.template.displayName)

            LabeledContent("Created", value: spec.normalised().createdAt.formatted(date: .abbreviated, time: .standard))
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
                if !restrictToSmallOnly {
                    Text("Medium").tag(WidgetFamily.systemMedium)
                    Text("Large").tag(WidgetFamily.systemLarge)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .onChange(of: family) { _, _ in
                clampFamilyIfNeeded()
            }

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

    private var widgetImageRenderSection: some View {
        let resolved = resolvedSpec(for: family)

        return Section {
            if let img = resolved.image {
                let preferred = img.fileNameForFamily(family)
                let base = img.fileName

                fileInfoBlock(title: "Widget render file (\(familyLabel(family)))", fileName: preferred)

                if preferred != base {
                    fileInfoBlock(title: "Fallback base file", fileName: base)

                    let preferredExists = fileInfo(for: preferred).exists
                    if !preferredExists {
                        Text("Preferred render is missing. Widget render will fall back to the base image.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let smart = img.smartPhoto {
                    fileInfoBlock(title: "Smart master file", fileName: smart.masterFileName)

                    Text("Smart metadata: v\(smart.algorithmVersion) • prepared \(smart.preparedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let referenced = img.allReferencedFileNames()
                if !referenced.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Referenced by this image")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(referenced, id: \.self) { name in
                            fileInfoInlineRow(fileName: name)
                        }
                    }
                    .padding(.top, 6)
                }
            } else {
                Text("No image is set for this size.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Widget image render")
        } footer: {
            Text("Matches the widget behaviour: prefer per-family render (Smart Photo), then fall back to the base file.")
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

    private struct FileInfo {
        let fileName: String
        let exists: Bool
        let sizeText: String
    }

    private func fileInfo(for fileName: String) -> FileInfo {
        let url = AppGroup.imageFileURL(fileName: fileName)
        let exists = FileManager.default.fileExists(atPath: url.path)

        var bytesText = "unknown size"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber {
            bytesText = ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
        }

        return FileInfo(fileName: fileName, exists: exists, sizeText: bytesText)
    }

    @ViewBuilder
    private func fileInfoBlock(title: String, fileName: String) -> some View {
        let info = fileInfo(for: fileName)

        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(info.fileName)
                .font(.subheadline.weight(.semibold))
                .textSelection(.enabled)

            Text(info.exists ? "On disk • \(info.sizeText)" : "Missing on disk")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func fileInfoInlineRow(fileName: String) -> some View {
        let info = fileInfo(for: fileName)

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(info.fileName)
                .font(.caption)
                .textSelection(.enabled)

            Spacer(minLength: 0)

            Text(info.exists ? info.sizeText : "missing")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private struct ImageInfo: Identifiable {
        let id: String
        let fileName: String
        let detailLine: String
    }

    private func imageInfos(in spec: WidgetSpec) -> [ImageInfo] {
        let names = spec.allReferencedImageFileNames()
        if names.isEmpty { return [] }

        return names.map { fileName in
            let info = fileInfo(for: fileName)
            let detail = info.exists ? "On disk • \(info.sizeText)" : "Missing on disk"
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
