//
//  ContentViewSupport.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI
import UIKit
import StoreKit

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
                        Button {
                            dismiss()
                        } label: {
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
                            Text("Working…")
                                .foregroundStyle(.secondary)
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
            .task {
                await manager.refresh()
            }
        }
    }
}
