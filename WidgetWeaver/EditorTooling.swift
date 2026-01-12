//
//  EditorTooling.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

// MARK: - Context model

struct EditorToolContext: Hashable, Sendable {
    var template: LayoutTemplateToken
    var isProUnlocked: Bool
    var matchedSetEnabled: Bool

    var selection: EditorSelectionKind
    var focus: EditorFocusTarget

    /// Exact selection count when known.
    ///
    /// Nil means the selection is known to be multi-select but an exact count
    /// is unavailable.
    var selectionCount: Int?

    /// Coarse selection composition when known.
    ///
    /// When `.unknown`, selection modelling falls back to conservative heuristics.
    var selectionComposition: EditorSelectionComposition

    var photoLibraryAccess: EditorPhotoLibraryAccess

    var hasSymbolConfigured: Bool
    var hasImageConfigured: Bool
    var hasSmartPhotoConfigured: Bool

    init(
        template: LayoutTemplateToken,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        selection: EditorSelectionKind,
        focus: EditorFocusTarget,
        selectionCount: Int? = nil,
        selectionComposition: EditorSelectionComposition = .unknown,
        photoLibraryAccess: EditorPhotoLibraryAccess,
        hasSymbolConfigured: Bool,
        hasImageConfigured: Bool,
        hasSmartPhotoConfigured: Bool
    ) {
        self.template = template
        self.isProUnlocked = isProUnlocked
        self.matchedSetEnabled = matchedSetEnabled
        self.selection = selection
        self.focus = focus
        self.selectionCount = selectionCount
        self.selectionComposition = selectionComposition
        self.photoLibraryAccess = photoLibraryAccess
        self.hasSymbolConfigured = hasSymbolConfigured
        self.hasImageConfigured = hasImageConfigured
        self.hasSmartPhotoConfigured = hasSmartPhotoConfigured
    }
}

// MARK: - Capability vocabulary

struct EditorCapability: Hashable, Sendable, RawRepresentable {
    var rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
}

typealias EditorCapabilities = Set<EditorCapability>


// MARK: - Non-Photos capability scaffolding (10S-B1)

/// Capability keys for non-Photos editor requirements.
///
/// These keys model availability that is not derived from Photos/Albums content (for example:
/// feature flags, external permissions, service availability, subscription state, etc).
///
/// 10S-B1 intentionally introduces this vocabulary without changing behaviour. Tools will only
/// be impacted once they explicitly declare requirements against these keys.
struct EditorNonPhotosCapability: Hashable, Sendable, RawRepresentable {
    var rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
}

typealias EditorNonPhotosCapabilities = Set<EditorNonPhotosCapability>

extension EditorNonPhotosCapability {
    /// Non-Photos capability indicating Pro is unlocked.
    static let proUnlocked = EditorNonPhotosCapability(rawValue: "proUnlocked")

    /// Non-Photos capability indicating Matched Set can be edited.
    ///
    /// This is supported when Pro is unlocked, or when a matched set is already enabled (so the
    /// user can always turn it off even if Pro later becomes unavailable).
    static let matchedSetAvailable = EditorNonPhotosCapability(rawValue: "matchedSetAvailable")
}


/// Deterministic snapshot of non-Photos capabilities at a point in time.
struct EditorNonPhotosCapabilitySnapshot: Hashable, Sendable {
    var supported: EditorNonPhotosCapabilities

    init(supported: EditorNonPhotosCapabilities = []) {
        self.supported = supported
    }

    /// Stable ordering for diagnostics/tests.
    var sortedDebugLabels: [String] {
        supported.map(\.rawValue).sorted()
    }

    var debugSummary: String {
        sortedDebugLabels.joined(separator: ",")
    }
}

/// Aggregated capability snapshot used by the manifest/eligibility pipeline.
struct EditorToolCapabilitySnapshot: Hashable, Sendable {
    var toolCapabilities: EditorCapabilities
    var nonPhotos: EditorNonPhotosCapabilitySnapshot
}

/// Derivation entry point for non-Photos capabilities.
/// 10S-B1: returns an empty snapshot (no behaviour change).
enum EditorNonPhotosCapabilityDeriver {
    static func derive(for context: EditorToolContext) -> EditorNonPhotosCapabilitySnapshot {
        var supported: EditorNonPhotosCapabilities = []

        if context.isProUnlocked {
            supported.insert(.proUnlocked)
        }

        if context.isProUnlocked || context.matchedSetEnabled {
            supported.insert(.matchedSetAvailable)
        }

        return EditorNonPhotosCapabilitySnapshot(supported: supported)
    }
}

extension EditorCapability {
    // Template / tool availability.
    static let canEditLayout = EditorCapability(rawValue: "layout")
    static let canEditTextContent = EditorCapability(rawValue: "text")
    static let canEditSymbol = EditorCapability(rawValue: "symbol")
    static let canEditImage = EditorCapability(rawValue: "image")
    static let canEditSmartPhoto = EditorCapability(rawValue: "smartPhoto")
    static let canEditSmartRules = EditorCapability(rawValue: "smartRules")
    static let canEditTypography = EditorCapability(rawValue: "typography")
    static let canEditStyle = EditorCapability(rawValue: "style")

    // Non-Photos tools.
    static let canEditMatchedSet = EditorCapability(rawValue: "matchedSet")
    static let canEditVariables = EditorCapability(rawValue: "variables")
    static let canEditActions = EditorCapability(rawValue: "actions")
    static let canShare = EditorCapability(rawValue: "sharing")
    static let canUseAI = EditorCapability(rawValue: "ai")
    static let canPurchasePro = EditorCapability(rawValue: "pro")

    // Albums.
    static let canEditAlbumShuffle = EditorCapability(rawValue: "albumShuffle")

    // Permissions and derived availability.
    static let canAccessPhotoLibrary = EditorCapability(rawValue: "photosAccess")
    static let hasImageConfigured = EditorCapability(rawValue: "hasImage")
    static let hasSmartPhotoConfigured = EditorCapability(rawValue: "hasSmartPhoto")
}

// MARK: - Tool IDs

enum EditorToolID: String, CaseIterable, Hashable, Identifiable, Sendable {
    case status
    case designs
    case widgets

    case layout
    case text
    case symbol
    case image
    case smartPhoto
    case smartPhotoCrop
    case albumShuffle
    case smartRules
    case typography
    case style

    case actions
    case matchedSet
    case variables
    case sharing
    case ai
    case pro

    var id: String { rawValue }
}

enum EditorToolMissingNonPhotosCapabilityPolicy: Hashable, Sendable {
    case hide
    case showAsUnavailable(EditorUnavailableState)
}

struct EditorVisibleTool: Hashable, Sendable {
    var id: EditorToolID
    var unavailableState: EditorUnavailableState?

    init(id: EditorToolID, unavailableState: EditorUnavailableState? = nil) {
        self.id = id
        self.unavailableState = unavailableState
    }
}

struct EditorToolDefinition: Hashable, Sendable {
    var id: EditorToolID
    var order: Int

    var requiredCapabilities: EditorCapabilities
    var requiredNonPhotosCapabilities: EditorNonPhotosCapabilities
    var missingNonPhotosCapabilityPolicy: EditorToolMissingNonPhotosCapabilityPolicy
    var eligibility: EditorToolEligibility

    init(
        id: EditorToolID,
        order: Int,
        requiredCapabilities: EditorCapabilities = [],
        requiredNonPhotosCapabilities: EditorNonPhotosCapabilities = [],
        missingNonPhotosCapabilityPolicy: EditorToolMissingNonPhotosCapabilityPolicy = .hide,
        eligibility: EditorToolEligibility = .init()
    ) {
        self.id = id
        self.order = order
        self.requiredCapabilities = requiredCapabilities
        self.requiredNonPhotosCapabilities = requiredNonPhotosCapabilities
        self.missingNonPhotosCapabilityPolicy = missingNonPhotosCapabilityPolicy
        self.eligibility = eligibility
    }

    func resolveVisibleTool(
        context: EditorToolContext,
        capabilities: EditorCapabilities,
        nonPhotosCapabilities: EditorNonPhotosCapabilitySnapshot,
        selectionDescriptor: EditorSelectionDescriptor,
        multiSelectionPolicy: EditorMultiSelectionPolicy
    ) -> EditorVisibleTool? {
        guard requiredCapabilities.isSubset(of: capabilities) else { return nil }

        let eligibleBySelectionAndFocus = EditorToolEligibilityEvaluator.isEligible(
            eligibility: eligibility,
            selection: context.selection,
            selectionDescriptor: selectionDescriptor,
            focus: context.focus,
            multiSelectionPolicy: multiSelectionPolicy
        )
        guard eligibleBySelectionAndFocus else { return nil }

        if requiredNonPhotosCapabilities.isSubset(of: nonPhotosCapabilities.supported) {
            return EditorVisibleTool(id: id, unavailableState: nil)
        }

        switch missingNonPhotosCapabilityPolicy {
        case .hide:
            return nil
        case .showAsUnavailable(let state):
            return EditorVisibleTool(id: id, unavailableState: state)
        }
    }
}


// MARK: - Capability change handling (10S-B5 scaffolding)

enum EditorToolCapabilityChangeReason: String, Hashable, Sendable {
    case unknown
    case proStateChanged
    case matchedSetEnabledChanged
    case photoLibraryAccessChanged
}

extension Notification.Name {
    /// Posted when editor tooling capabilities change at runtime.
    ///
    /// The notification object, when present, is an `EditorToolCapabilityChangeReason`.
    static let editorToolCapabilitiesDidChange = Notification.Name("widgetweaver.editorToolCapabilitiesDidChange")
}

// MARK: - Registry

enum EditorToolRegistry {
    static let multiSelectionPolicy: EditorMultiSelectionPolicy = .intersection

    private final class ToolSuiteCache: @unchecked Sendable {
        private let lock = NSLock()
        private var lastContext: EditorToolContext?
        private var lastSuite: [EditorVisibleTool] = []
        private var lastToolIDs: [EditorToolID] = []

        func cachedSuite(for context: EditorToolContext) -> [EditorVisibleTool]? {
            lock.lock()
            defer { lock.unlock() }

            guard lastContext == context else { return nil }
            return lastSuite
        }

        func cachedToolIDs(for context: EditorToolContext) -> [EditorToolID]? {
            lock.lock()
            defer { lock.unlock() }

            guard lastContext == context else { return nil }
            return lastToolIDs
        }

        func store(context: EditorToolContext, suite: [EditorVisibleTool]) {
            lock.lock()
            lastContext = context
            lastSuite = suite
            lastToolIDs = suite.map(\.id)
            lock.unlock()
        }

        func invalidate() {
            lock.lock()
            lastContext = nil
            lastSuite = []
            lastToolIDs = []
            lock.unlock()
        }
    }

    private static let toolSuiteCache = ToolSuiteCache()

    /// Explicitly busts the memoised visible tool suite cache.
    ///
    /// This is intended for scenarios where a capability input can change at runtime
    /// and the UI needs the next tool-suite query to recompute deterministically.
    static func invalidateVisibleToolSuiteCache() {
        toolSuiteCache.invalidate()
    }

    /// Entry point for signalling that editor capabilities have changed at runtime.
    ///
    /// 10S-B5 stage 1 introduces this explicit pathway without wiring it into the UI.
    /// Follow-on slices should call this when entitlement/permission/service state flips,
    /// then apply the 10R teardown + focus restoration contracts.
    static func capabilitiesDidChange(reason: EditorToolCapabilityChangeReason = .unknown) {
        invalidateVisibleToolSuiteCache()

        // Post on the main actor so SwiftUI observers can safely update state.
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .editorToolCapabilitiesDidChange, object: reason)
        } else {
            Task { @MainActor in
                NotificationCenter.default.post(name: .editorToolCapabilitiesDidChange, object: reason)
            }
        }
    }

    /// Canonical tool manifest.
    static let tools: [EditorToolDefinition] = [
        // Workflow.
        EditorToolDefinition(id: .status, order: 10, requiredCapabilities: [], eligibility: .multiSafe(selectionDescriptor: .mixedAllowed)),
        EditorToolDefinition(id: .designs, order: 20, requiredCapabilities: [], eligibility: .multiSafe(selectionDescriptor: .mixedAllowed)),
        EditorToolDefinition(id: .widgets, order: 30, requiredCapabilities: [], eligibility: .multiSafe(selectionDescriptor: .mixedAllowed)),

        // Core editing.
        EditorToolDefinition(
            id: .layout,
            order: 40,
            requiredCapabilities: [.canEditLayout],
            eligibility: .multiSafe(
                focus: .any,
                selection: .any,
                selectionDescriptor: .mixedAllowed
            )
        ),
        EditorToolDefinition(
            id: .text,
            order: 50,
            requiredCapabilities: [.canEditTextContent],
            eligibility: .singleTarget(
                focus: .any,
                selectionDescriptor: .mixedDisallowed
            )
        ),
        EditorToolDefinition(
            id: .symbol,
            order: 60,
            requiredCapabilities: [.canEditSymbol],
            eligibility: .singleTarget(
                focus: .any,
                selectionDescriptor: .mixedDisallowed
            )
        ),
        EditorToolDefinition(
            id: .image,
            order: 70,
            requiredCapabilities: [.canEditImage],
            eligibility: .singleTarget(
                focus: .smartPhotoPhotoItemSuite,
                selectionDescriptor: .mixedDisallowed
            )
        ),

        // Smart Photos / Albums.
        EditorToolDefinition(
            id: .smartPhoto,
            order: 80,
            requiredCapabilities: [.canEditSmartPhoto],
            eligibility: .singleTarget(
                focus: .smartPhotoContainerSuite,
                selectionDescriptor: .mixedDisallowed
            )
        ),
        EditorToolDefinition(
            id: .smartPhotoCrop,
            order: 81,
            requiredCapabilities: [.canEditSmartPhoto, .hasSmartPhotoConfigured],
            eligibility: .singleTarget(
                focus: .smartPhotoPhotoItemSuite,
                selectionDescriptor: .mixedDisallowed
            )
        ),
        EditorToolDefinition(
            id: .albumShuffle,
            order: 82,
            requiredCapabilities: [.canEditAlbumShuffle, .hasSmartPhotoConfigured, .canAccessPhotoLibrary],
            eligibility: .singleTarget(
                focus: EditorToolFocusConstraint(
                    allowClock: false,
                    allowSmartRuleEditor: true,
                    allowAnyElement: false,
                    allowedElementIDPrefixes: ["smartPhoto"],
                    allowAnyAlbumContainer: false,
                    allowedAlbumContainerSubtypes: [],
                    allowAnyAlbumPhotoItem: false,
                    allowedAlbumPhotoItemSubtypes: []
                ),
                selectionDescriptor: .mixedDisallowed
            )
        ),
        EditorToolDefinition(
            id: .smartRules,
            order: 83,
            requiredCapabilities: [.canEditSmartPhoto, .hasSmartPhotoConfigured, .hasImageConfigured],
            eligibility: .singleTarget(
                focus: .smartPhotoContainerSuite,
                selectionDescriptor: .mixedDisallowed
            )
        ),

        // Style group.
        EditorToolDefinition(
            id: .style,
            order: 90,
            requiredCapabilities: [.canEditStyle],
            eligibility: .multiSafe(selectionDescriptor: .mixedAllowed)
        ),

        // Typography group.
        EditorToolDefinition(
            id: .typography,
            order: 100,
            requiredCapabilities: [.canEditTypography],
            eligibility: .singleTarget(
                focus: .any,
                selectionDescriptor: .mixedDisallowed
            )
        ),

        // Non-Photos tools (Pro upsell / add-ons).
        EditorToolDefinition(
            id: .actions,
            order: 115,
            requiredCapabilities: [.canEditActions],
            eligibility: .singleTarget(
                focus: .any,
                selectionDescriptor: .mixedDisallowed
            )
        ),
        EditorToolDefinition(
            id: .matchedSet,
            order: 120,
            requiredCapabilities: [.canEditMatchedSet],
            requiredNonPhotosCapabilities: [.matchedSetAvailable],
            missingNonPhotosCapabilityPolicy: .showAsUnavailable(EditorUnavailableState.proRequiredForMatchedSet()),
            eligibility: .multiSafe(selectionDescriptor: .mixedAllowed)
        ),
        EditorToolDefinition(
            id: .variables,
            order: 130,
            requiredCapabilities: [.canEditVariables],
            requiredNonPhotosCapabilities: [.proUnlocked],
            missingNonPhotosCapabilityPolicy: .showAsUnavailable(EditorUnavailableState.proRequiredForVariables()),
            eligibility: .multiSafe(selectionDescriptor: .mixedAllowed)
        ),
        EditorToolDefinition(
            id: .sharing,
            order: 140,
            requiredCapabilities: [.canShare],
            eligibility: .multiSafe(selectionDescriptor: .mixedAllowed)
        ),
        EditorToolDefinition(
            id: .ai,
            order: 150,
            requiredCapabilities: [.canUseAI],
            requiredNonPhotosCapabilities: [.proUnlocked],
            missingNonPhotosCapabilityPolicy: .showAsUnavailable(EditorUnavailableState.proRequiredForAI()),
            eligibility: .multiSafe(selectionDescriptor: .mixedAllowed)
        ),
        EditorToolDefinition(
            id: .pro,
            order: 160,
            requiredCapabilities: [.canPurchasePro],
            eligibility: .multiSafe(selectionDescriptor: .mixedAllowed)
        ),
    ]

    static let toolsSortedByOrder: [EditorToolDefinition] = tools.sorted { $0.order < $1.order }

    static func capabilitySnapshot(for context: EditorToolContext) -> EditorToolCapabilitySnapshot {
        EditorToolCapabilitySnapshot(
            toolCapabilities: capabilities(for: context),
            nonPhotos: EditorNonPhotosCapabilityDeriver.derive(for: context)
        )
    }

    static func capabilities(for context: EditorToolContext) -> EditorCapabilities {
        var c: EditorCapabilities = [
            .canEditLayout,
            .canEditTextContent,
            .canEditStyle,
            .canEditMatchedSet,
            .canEditVariables,
            .canShare,
            .canUseAI,
            .canPurchasePro,
        ]

        if context.matchedSetEnabled {
            c.insert(.canEditMatchedSet)
        }

        switch context.template {
        case .classic, .hero:
            c.insert(.canEditSymbol)
            c.insert(.canEditTypography)
            c.insert(.canEditActions)

        case .poster:
            c.insert(.canEditImage)
            c.insert(.canEditSmartPhoto)
            c.insert(.canEditAlbumShuffle)
            c.insert(.canEditTypography)

        case .weather:
            c.insert(.canEditTypography)

        case .nextUpCalendar:
            c.insert(.canEditTypography)
        }

        // Permissions and derived availability.
        if context.photoLibraryAccess.allowsReadWrite {
            c.insert(.canAccessPhotoLibrary)
        }
        if context.hasImageConfigured {
            c.insert(.hasImageConfigured)
        }
        if context.hasSmartPhotoConfigured {
            c.insert(.hasSmartPhotoConfigured)
        }

        return c
    }

    static func legacyCapabilities(for context: EditorToolContext) -> EditorCapabilities {
        var c = capabilities(for: context)

        // Legacy tool lists intentionally ignore permission and runtime availability gating.
        // Tools remain discoverable and can present their own “unavailable” UI when needed.
        c.insert(.canAccessPhotoLibrary)
        c.insert(.hasImageConfigured)
        c.insert(.hasSmartPhotoConfigured)

        return c
    }

    static func legacyVisibleTools(for context: EditorToolContext) -> [EditorToolID] {
        // Old behaviour: capabilities-only ordering (no eligibility/focus gating).
        let caps = legacyCapabilities(for: context)
        let nonPhotos = EditorNonPhotosCapabilityDeriver.derive(for: context)

        var visible: [EditorToolID] = []
        visible.reserveCapacity(toolsSortedByOrder.count)

        for tool in toolsSortedByOrder {
            guard tool.requiredCapabilities.isSubset(of: caps) else { continue }

            if tool.requiredNonPhotosCapabilities.isSubset(of: nonPhotos.supported) {
                visible.append(tool.id)
                continue
            }

            switch tool.missingNonPhotosCapabilityPolicy {
            case .hide:
                continue
            case .showAsUnavailable:
                visible.append(tool.id)
            }
        }

        return visible
    }

    static func visibleToolSuite(for context: EditorToolContext) -> [EditorVisibleTool] {
        if let cached = toolSuiteCache.cachedSuite(for: context) {
            return cached
        }

        let snapshot = capabilitySnapshot(for: context)
        let caps = snapshot.toolCapabilities
        let nonPhotos = snapshot.nonPhotos

        let selectionDescriptor = EditorSelectionDescriptor.describe(
            selection: context.selection,
            focus: context.focus,
            selectionCount: context.selectionCount,
            composition: context.selectionComposition
        )

        var visible: [EditorVisibleTool] = []
        visible.reserveCapacity(toolsSortedByOrder.count)

        for tool in toolsSortedByOrder {
            if let resolved = tool.resolveVisibleTool(
                context: context,
                capabilities: caps,
                nonPhotosCapabilities: nonPhotos,
                selectionDescriptor: selectionDescriptor,
                multiSelectionPolicy: multiSelectionPolicy
            ) {
                visible.append(resolved)
            }
        }

        // Apply focus gating as last-mile filter.
        let focusGroup = editorToolFocusGroup(for: context.focus)
        let gatedIDs = editorToolIDsApplyingFocusGate(
            eligible: visible.map(\.id),
            focusGroup: focusGroup
        )

        var focusGated: [EditorVisibleTool] = gatedIDs.compactMap { id in
            visible.first(where: { $0.id == id })
        }

        // Prioritise Smart Rules when editing them.
        if case .smartRuleEditor = context.focus,
           let idx = focusGated.firstIndex(where: { $0.id == EditorToolID.smartRules }),
           idx != 0 {
            let tool = focusGated.remove(at: idx)
            focusGated.insert(tool, at: 0)
        }

        toolSuiteCache.store(context: context, suite: focusGated)
        return focusGated
    }

    static func visibleTools(for context: EditorToolContext) -> [EditorToolID] {
        if let cached = toolSuiteCache.cachedToolIDs(for: context) {
            return cached
        }

        return visibleToolSuite(for: context).map(\.id)
    }

    static func unavailableState(for toolID: EditorToolID, context: EditorToolContext) -> EditorUnavailableState? {
        visibleToolSuite(for: context).first(where: { $0.id == toolID })?.unavailableState
    }
}

// MARK: - Debug / diagnostics

extension EditorToolContext {
    var debugSummary: String {
        """
        template=\(template.rawValue)
        pro=\(isProUnlocked)
        matchedSet=\(matchedSetEnabled)
        selection=\(selection.rawValue)
        focus=\(focus.debugLabel)
        photos=\(photoLibraryAccess.status.rawValue)
        hasSymbol=\(hasSymbolConfigured)
        hasImage=\(hasImageConfigured)
        hasSmartPhoto=\(hasSmartPhotoConfigured)
        """
    }
}

extension EditorFocusTarget {
    var debugLabel: String {
        switch self {
        case .widget:
            return "widget"
        case .clock:
            return "clock"
        case .smartRuleEditor(let albumID):
            return "smartRuleEditor(\(albumID))"
        case .element(let id):
            return "element(\(id))"
        case .albumContainer(let id, let subtype):
            return "albumContainer(\(id), \(subtype.rawValue))"
        case .albumPhoto(let albumID, let itemID, let subtype):
            return "albumPhoto(\(albumID), \(itemID), \(subtype.rawValue))"
        }
    }
}

extension EditorCapabilities {
    static let allKnown: [EditorCapability] = [
        .canEditLayout,
        .canEditTextContent,
        .canEditSymbol,
        .canEditImage,
        .canEditSmartPhoto,
        .canEditSmartRules,
        .canEditTypography,
        .canEditStyle,
        .canEditActions,
        .canEditMatchedSet,
        .canEditVariables,
        .canShare,
        .canUseAI,
        .canPurchasePro,
        .canEditAlbumShuffle,
        .canAccessPhotoLibrary,
        .hasImageConfigured,
        .hasSmartPhotoConfigured,
    ]
}
