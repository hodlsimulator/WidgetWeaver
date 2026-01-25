//
//  ContentView+Sheets.swift
//  WidgetWeaver
//
//  Created by . . on 1/17/26.
//

import Foundation
import StoreKit
import SwiftUI

// MARK: - Monetisation / Pro

enum WidgetWeaverProHiddenUnlockGate {
    static func initialIsEnabled() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func isEnabled(environmentRaw: String) -> Bool {
        #if DEBUG
        return true
        #else
        return environmentRaw.lowercased() == "sandbox"
        #endif
    }
}

@MainActor
final class WidgetWeaverProManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var ownedProducts: Set<String> = []
    @Published private(set) var latestTransaction: StoreKit.Transaction?
    @Published private(set) var errorMessage: String = ""
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var isProUnlocked: Bool = WidgetWeaverEntitlements.isProUnlocked
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var didAttemptLoadProducts: Bool = false
    @Published private(set) var storeEnvironmentLabel: String = "Unknown"
    @Published private(set) var isHiddenUnlockEnabled: Bool = false

    private let proProductIDs: Set<String> = [
        "com.conornolan.widgetweaver.pro"
    ]

    private var transactionUpdatesTask: Task<Void, Never>?

    private var hiddenUnlockTapCount: Int = 0
    private var hiddenUnlockLastTapAt: Date = .distantPast
    private let hiddenUnlockRequiredTapCount: Int = 7
    private let hiddenUnlockTimeoutSeconds: TimeInterval = 2.0

    init() {
        isHiddenUnlockEnabled = WidgetWeaverProHiddenUnlockGate.initialIsEnabled()
        startTransactionUpdatesListenerIfNeeded()
        Task { await refreshEntitlementFromStoreKit() }
        Task { await refreshStoreEnvironment() }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func refreshEntitlementFromStoreKit() async {
        var owned: Set<String> = []
        var latest: StoreKit.Transaction?

        for await result in StoreKit.Transaction.currentEntitlements {
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

        let previous = WidgetWeaverEntitlements.isProUnlocked
        let unlocked = !owned.isEmpty || previous
        if unlocked != previous {
            WidgetWeaverEntitlements.setProUnlocked(unlocked)
        }

        ownedProducts = owned
        latestTransaction = latest
        isProUnlocked = unlocked

        if unlocked {
            statusMessage = ""
        }
    }

    func loadProducts(force: Bool = false) async {
        if isLoadingProducts { return }
        if didAttemptLoadProducts, !force, !products.isEmpty { return }

        didAttemptLoadProducts = true
        isLoadingProducts = true
        errorMessage = ""
        defer { isLoadingProducts = false }

        do {
            let fetched = try await Product.products(for: Array(proProductIDs))
            let sorted = fetched.sorted(by: { $0.displayName < $1.displayName })
            products = sorted

            if sorted.isEmpty {
                errorMessage = "No products were returned. This usually indicates the product IDs are unavailable for this build or Storefront, or the device is not signed in to the App Store."
                statusMessage = "Unable to load products."
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Store error: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async {
        statusMessage = ""
        errorMessage = ""

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlementFromStoreKit()
                    statusMessage = "Purchase completed."

                case .unverified:
                    errorMessage = "Purchase could not be verified."
                    statusMessage = "Purchase could not be verified."
                }

            case .userCancelled:
                statusMessage = "Purchase cancelled."

            case .pending:
                statusMessage = "Purchase pending."

            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Purchase error: \(error.localizedDescription)"
        }
    }

    func restore() async {
        statusMessage = ""
        errorMessage = ""

        do {
            try await AppStore.sync()
            await refreshEntitlementFromStoreKit()
            statusMessage = isProUnlocked ? "Restore completed." : "No Pro purchase found."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Restore error: \(error.localizedDescription)"
        }
    }

    func registerHiddenUnlockTap() {
        guard isHiddenUnlockEnabled, !isProUnlocked else { return }

        let now = Date()
        if now.timeIntervalSince(hiddenUnlockLastTapAt) > hiddenUnlockTimeoutSeconds {
            hiddenUnlockTapCount = 0
        }
        hiddenUnlockLastTapAt = now
        hiddenUnlockTapCount += 1

        if hiddenUnlockTapCount >= hiddenUnlockRequiredTapCount {
            hiddenUnlockTapCount = 0
            unlockProFromHiddenMechanism()
        }
    }

    func unlockProFromHiddenMechanism() {
        guard isHiddenUnlockEnabled else {
            statusMessage = "Hidden unlock is unavailable in this build."
            return
        }

        WidgetWeaverEntitlements.setProUnlocked(true)
        isProUnlocked = true
        statusMessage = "Pro unlocked."
    }

    private func startTransactionUpdatesListenerIfNeeded() {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            for await result in StoreKit.Transaction.updates {
                if Task.isCancelled { return }
                await self.handleTransactionUpdate(result)
            }
        }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            if proProductIDs.contains(transaction.productID) {
                await refreshEntitlementFromStoreKit()
            }

            await transaction.finish()

        case .unverified:
            break
        }
    }

    private func refreshStoreEnvironment() async {
        do {
            let verificationResult = try await AppTransaction.shared

            let envRaw: String
            switch verificationResult {
            case .verified(let appTransaction):
                envRaw = appTransaction.environment.rawValue
            case .unverified(let appTransaction, _):
                envRaw = appTransaction.environment.rawValue
            }

            storeEnvironmentLabel = envRaw
            isHiddenUnlockEnabled = WidgetWeaverProHiddenUnlockGate.isEnabled(environmentRaw: envRaw)
        } catch {
            storeEnvironmentLabel = "Unknown"
            isHiddenUnlockEnabled = WidgetWeaverProHiddenUnlockGate.initialIsEnabled()
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
                    if manager.isLoadingProducts || (!manager.didAttemptLoadProducts && manager.products.isEmpty) {
                        ProgressView()
                    } else if manager.products.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Products could not be loaded.")
                                .font(.headline)

                            if !manager.errorMessage.isEmpty {
                                Text(manager.errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                Task { await manager.loadProducts(force: true) }
                            } label: {
                                Label("Try Again", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
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
                                    Text(manager.isProUnlocked ? "Purchased" : "Purchase")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(manager.isProUnlocked || manager.ownedProducts.contains(product.id))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Purchase")
                }

                Section {
                    Button("Restore Purchases") {
                        Task { await manager.restore() }
                    }
                } header: {
                    Text("Restore")
                }

                Section {
                    LabeledContent("Pro", value: manager.isProUnlocked ? "Unlocked" : "Locked")
                    LabeledContent("Store environment", value: manager.storeEnvironmentLabel)
                        .contentShape(Rectangle())
                        .onTapGesture { manager.registerHiddenUnlockTap() }

                    if let tx = manager.latestTransaction {
                        Text("Latest transaction: \(tx.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !manager.statusMessage.isEmpty {
                        Text(manager.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Status")
                }
            }
            .navigationTitle("Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await manager.refreshEntitlementFromStoreKit()
                if manager.products.isEmpty {
                    await manager.loadProducts()
                }
            }
        }
    }
}

extension ContentView {
    enum ActiveSheet: Identifiable {
        case widgetHelp
        case pro
        case variables
        case inspector
        case remix
        case weather
        case steps
        case activity
        case reminders
        case remindersSmartStackGuide
        case importReview

        #if DEBUG
        case clockFaceGallery
        #endif

        var id: Int {
            switch self {
            case .widgetHelp: return 1
            case .pro: return 2
            case .variables: return 3
            case .weather: return 4
            case .inspector: return 5
            case .remix: return 6
            case .steps: return 7
            case .activity: return 8
            case .reminders: return 10
            case .remindersSmartStackGuide: return 11
            case .importReview: return 9

            #if DEBUG
            case .clockFaceGallery: return 12
            #endif
            }
        }
    }

    func sheetContent(_ sheet: ActiveSheet) -> AnyView {
        switch sheet {
        case .widgetHelp:
            return AnyView(WidgetWeaverHelpView())

        case .pro:
            return AnyView(WidgetWeaverProView(manager: proManager))

        case .variables:
            return AnyView(
                WidgetWeaverVariablesView(
                    proManager: proManager,
                    onShowPro: { activeSheet = .pro }
                )
            )

        case .inspector:
            return AnyView(
                WidgetWeaverDesignInspectorView(
                    spec: draftSpec(id: selectedSpecID),
                    initialFamily: previewFamily
                )
            )

        case .remix:
            return AnyView(
                WidgetWeaverRemixSheet(
                    variants: remixVariants,
                    family: previewFamily,
                    onApply: { spec in applyRemixVariant(spec) },
                    onAgain: { remixAgain() },
                    onClose: { activeSheet = nil }
                )
            )

        case .weather:
            return AnyView(
                NavigationStack {
                    WidgetWeaverWeatherSettingsView(onClose: { activeSheet = nil })
                }
            )

        case .steps:
            return AnyView(
                NavigationStack {
                    WidgetWeaverStepsSettingsView(onClose: { activeSheet = nil })
                }
            )

        case .activity:
            return AnyView(
                NavigationStack {
                    WidgetWeaverActivitySettingsView(onClose: { activeSheet = nil })
                }
            )

        case .reminders:
            return AnyView(
                NavigationStack {
                    WidgetWeaverRemindersSettingsView(onClose: { activeSheet = nil })
                }
            )

        case .remindersSmartStackGuide:
            return AnyView(
                NavigationStack {
                    WidgetWeaverRemindersSmartStackGuideView(onClose: { activeSheet = nil })
                }
            )

        case .importReview:
            return importReviewSheetAnyView()

        #if DEBUG
        case .clockFaceGallery:
            let config = draftSpec(id: selectedSpecID).clockConfig ?? WidgetWeaverClockDesignConfig.default
            return AnyView(ClockFaceGalleryView(config: config))
        #endif
        }
    }
}
