//
//  EditorTooling.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

/// Stable identifiers for editor tool sections.
///
/// IDs are referenced by:
/// - manifests/registries
/// - analytics (optional)
/// - tests
/// - accessibility anchors
enum EditorToolID: String, CaseIterable, Hashable, Sendable {
    case status
    case designs
    case widgets
    case layout
    case text
    case symbol
    case image

    case smartPhoto
    case smartPhotoCrop
    case smartRules
    case albumShuffle

    case style
    case typography
    case actions

    case matchedSet
    case variables
    case sharing
    case ai

    case pro
}

/// Capabilities that determine whether a tool can ever be shown.
///
/// Capabilities are derived from:
/// - current template
/// - entitlements (Pro, etc.)
/// - current content state (e.g. “has image configured”)
/// - platform permissions (e.g. Photos)
struct EditorCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    // Structural/template capabilities
    static let canEditLayout = EditorCapabilities(rawValue: 1 << 0)
    static let canEditTextContent = EditorCapabilities(rawValue: 1 << 1)
    static let canEditSymbol = EditorCapabilities(rawValue: 1 << 2)
    static let canEditImage = EditorCapabilities(rawValue: 1 << 3)
    static let canEditSmartPhoto = EditorCapabilities(rawValue: 1 << 4)
    static let canEditAlbumShuffle = EditorCapabilities(rawValue: 1 << 5)
    static let canEditStyle = EditorCapabilities(rawValue: 1 << 6)
    static let canEditTypography = EditorCapabilities(rawValue: 1 << 7)
    static let canEditActions = EditorCapabilities(rawValue: 1 << 8)
    static let canUseAI = EditorCapabilities(rawValue: 1 << 9)
    static let canUseProFeatures = EditorCapabilities(rawValue: 1 << 10)

    // Runtime/configuration capabilities (availability)
    static let hasSymbolConfigured = EditorCapabilities(rawValue: 1 << 20)
    static let hasImageConfigured = EditorCapabilities(rawValue: 1 << 21)
    static let hasSmartPhotoConfigured = EditorCapabilities(rawValue: 1 << 22)

    // Permissions
    static let canAccessPhotoLibrary = EditorCapabilities(rawValue: 1 << 30)

    static let allKnown: [EditorCapabilities] = [
        .canEditLayout,
        .canEditTextContent,
        .canEditSymbol,
        .canEditImage,
        .canEditSmartPhoto,
        .canEditAlbumShuffle,
        .canEditStyle,
        .canEditTypography,
        .canEditActions,
        .canUseAI,
        .canUseProFeatures,
        .hasSymbolConfigured,
        .hasImageConfigured,
        .hasSmartPhotoConfigured,
        .canAccessPhotoLibrary,
    ]
}

extension EditorCapabilities {
    func debugLabels() -> [String] {
        var labels: [String] = []
        for cap in EditorCapabilities.allKnown {
            if contains(cap) {
                labels.append(cap.debugLabel)
            }
        }
        return labels
    }

    private var debugLabel: String {
        switch self {
        case .canEditLayout: return "canEditLayout"
        case .canEditTextContent: return "canEditTextContent"
        case .canEditSymbol: return "canEditSymbol"
        case .canEditImage: return "canEditImage"
        case .canEditSmartPhoto: return "canEditSmartPhoto"
        case .canEditAlbumShuffle: return "canEditAlbumShuffle"
        case .canEditStyle: return "canEditStyle"
        case .canEditTypography: return "canEditTypography"
        case .canEditActions: return "canEditActions"
        case .canUseAI: return "canUseAI"
        case .canUseProFeatures: return "canUseProFeatures"
        case .hasSymbolConfigured: return "hasSymbolConfigured"
        case .hasImageConfigured: return "hasImageConfigured"
        case .hasSmartPhotoConfigured: return "hasSmartPhotoConfigured"
        case .canAccessPhotoLibrary: return "canAccessPhotoLibrary"
        default: return "unknown(\(rawValue))"
        }
    }
}

/// Multi-selection stance is explicit per tool.
///
/// This helps prevent new tools accidentally appearing in mixed/multi contexts.
enum EditorMultiSelectionPolicy: String, CaseIterable, Hashable, Sendable {
    /// Default: show only tools that explicitly declare mixed/multi support.
    case strict
}

/// Central registry of editor tools.
///
/// The registry is used for:
/// - data-driven tool ordering
/// - capability requirements
/// - eligibility constraints (selection/focus)
/// - unit tests
enum EditorToolRegistry {
    // MARK: - Tool manifest

    static let tools: [EditorToolDefinition] = [
        EditorToolDefinition(
            id: .status,
            order: 0,
            requiredCapabilities: [],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .designs,
            order: 10,
            requiredCapabilities: [],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .widgets,
            order: 20,
            requiredCapabilities: [],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .layout,
            order: 30,
            requiredCapabilities: [.canEditLayout],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .text,
            order: 40,
            requiredCapabilities: [.canEditTextContent],
            eligibility: .singleTarget(
                focus: .widgetSuite,
                selectionDescriptor: .allowsNonAlbumOrNone
            )
        ),
        EditorToolDefinition(
            id: .symbol,
            order: 50,
            requiredCapabilities: [.canEditSymbol],
            eligibility: .singleTarget(
                focus: .widgetSuite,
                selectionDescriptor: .allowsNonAlbumOrNone
            )
        ),
        EditorToolDefinition(
            id: .image,
            order: 70,
            requiredCapabilities: [.canEditImage],
            eligibility: .singleTarget(
                focus: .smartPhotoContainerSuite,
                selectionDescriptor: .mixedDisallowed
            )
        ),
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
                focus: .smartPhotoContainerSuite,
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
                    allowedAlbumContainerSubtypes: [.smart],
                    allowAnyAlbumPhotoItem: false,
                    allowedAlbumPhotoItemSubtypes: [.smart]
                ),
                selectionDescriptor: .allowsAlbumContainerOrNonAlbumHomogeneousOrNone
            )
        ),
        EditorToolDefinition(
            id: .smartRules,
            order: 83,
            requiredCapabilities: [.canEditSmartPhoto, .hasSmartPhotoConfigured],
            eligibility: .singleTarget(
                focus: .smartPhotoContainerSuite,
                selectionDescriptor: .allowsAlbumContainerOrNonAlbumHomogeneousOrNone
            )
        ),
        EditorToolDefinition(
            id: .style,
            order: 90,
            requiredCapabilities: [.canEditStyle],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .typography,
            order: 100,
            requiredCapabilities: [.canEditTypography],
            eligibility: .singleTarget(
                focus: .widgetSuite,
                selectionDescriptor: .allowsNonAlbumOrNone
            )
        ),
        EditorToolDefinition(
            id: .actions,
            order: 110,
            requiredCapabilities: [.canEditActions],
            eligibility: .singleTarget(
                focus: .widgetSuite,
                selectionDescriptor: .allowsNonAlbumOrNone
            )
        ),
        EditorToolDefinition(
            id: .matchedSet,
            order: 200,
            requiredCapabilities: [.canUseProFeatures],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .variables,
            order: 210,
            requiredCapabilities: [],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .sharing,
            order: 220,
            requiredCapabilities: [],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .ai,
            order: 230,
            requiredCapabilities: [.canUseAI],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .pro,
            order: 1000,
            requiredCapabilities: [],
            eligibility: .multiSafe()
        ),
    ]

    // MARK: - Policy

    static let multiSelectionPolicy: EditorMultiSelectionPolicy = .strict

    // MARK: - Capability derivation

    static func capabilities(for context: EditorToolContext) -> EditorCapabilities {
        var c: EditorCapabilities = []

        // Template-level tool support
        switch context.template {
        case .classic:
            c.insert(.canEditLayout)
            c.insert(.canEditTextContent)
            c.insert(.canEditSymbol)
            c.insert(.canEditStyle)
            c.insert(.canEditTypography)
            c.insert(.canEditActions)

        case .poster:
            c.insert(.canEditLayout)
            c.insert(.canEditTextContent)
            c.insert(.canEditImage)
            c.insert(.canEditSmartPhoto)
            c.insert(.canEditAlbumShuffle)
            c.insert(.canEditStyle)
            c.insert(.canEditTypography)

        case .hero:
            c.insert(.canEditLayout)
            c.insert(.canEditTextContent)
            c.insert(.canEditSymbol)
            c.insert(.canEditStyle)
            c.insert(.canEditTypography)
            c.insert(.canEditActions)

        case .photo:
            c.insert(.canEditLayout)
            c.insert(.canEditTextContent)
            c.insert(.canEditImage)
            c.insert(.canEditStyle)
            c.insert(.canEditTypography)

        case .clock:
            c.insert(.canEditLayout)
            c.insert(.canEditStyle)
            c.insert(.canEditTypography)
        }

        // Entitlements
        if context.isProUnlocked {
            c.insert(.canUseProFeatures)
        }

        // Matched set availability is Pro-gated.
        if context.matchedSetEnabled && context.isProUnlocked {
            c.insert(.canUseProFeatures)
        }

        // AI is currently gated behind Pro.
        if context.isProUnlocked {
            c.insert(.canUseAI)
        }

        // Runtime/configuration capabilities
        if context.hasSymbolConfigured {
            c.insert(.hasSymbolConfigured)
        }
        if context.hasImageConfigured {
            c.insert(.hasImageConfigured)
        }
        if context.hasSmartPhotoConfigured {
            c.insert(.hasSmartPhotoConfigured)
        }

        // Permissions
        if context.photoLibraryAccess.allowsReadWrite {
            c.insert(.canAccessPhotoLibrary)
        }

        return c
    }

    /// Legacy capability derivation intentionally ignores runtime availability gating.
    ///
    /// Legacy tool lists are a safety valve: when the context-aware feature flag is OFF,
    /// the editor should still surface the full tool suite even if Photos permission
    /// is denied or Smart Photo metadata is not configured yet.
    static func legacyCapabilities(for context: EditorToolContext) -> EditorCapabilities {
        var c = capabilities(for: context)

        // Treat runtime/availability capabilities as present in legacy mode so tools
        // remain discoverable and can drive their own “unavailable” UI where needed.
        c.insert(.canAccessPhotoLibrary)
        c.insert(.hasImageConfigured)
        c.insert(.hasSmartPhotoConfigured)

        return c
    }

    static func legacyVisibleTools(for context: EditorToolContext) -> [EditorToolID] {
        // Old behaviour: capabilities-only ordering (no eligibility/focus gating).
        let caps = legacyCapabilities(for: context)

        return tools
            .filter { $0.requiredCapabilities.isSubset(of: caps) }
            .sorted { $0.order < $1.order }
            .map(\.id)
    }

    static func visibleTools(for context: EditorToolContext) -> [EditorToolID] {
        let caps = capabilities(for: context)

        let eligible = tools
            .filter { $0.isEligible(context: context, capabilities: caps, multiSelectionPolicy: multiSelectionPolicy) }
            .sorted { $0.order < $1.order }
            .map(\.id)

        // Apply focus gating as last-mile filter.
        let focusGroup = editorToolFocusGroup(for: context.focus)
        var gated = editorToolIDsApplyingFocusGate(eligible: eligible, focusGroup: focusGroup)

        // Prioritise Smart Rules when editing them.
        if context.focus == .smartRuleEditor,
           let idx = gated.firstIndex(of: .smartRules) {
            gated.remove(at: idx)
            gated.insert(.smartRules, at: 0)
        }

        return gated
    }
}
