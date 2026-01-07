//
//  EditorTooling.swift
//  WidgetWeaver
//
//  Created by . . on 1/5/26.
//

import Foundation

struct EditorToolContext: Hashable, Sendable {
    var template: LayoutTemplateToken
    var isProUnlocked: Bool
    var matchedSetEnabled: Bool
    var selection: EditorSelectionKind
    var focus: EditorFocusTarget
    var photoLibraryAccess: EditorPhotoLibraryAccess

    init(
        template: LayoutTemplateToken,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        selection: EditorSelectionKind,
        focus: EditorFocusTarget,
        photoLibraryAccess: EditorPhotoLibraryAccess
    ) {
        self.template = template
        self.isProUnlocked = isProUnlocked
        self.matchedSetEnabled = matchedSetEnabled
        self.selection = selection
        self.focus = focus
        self.photoLibraryAccess = photoLibraryAccess
    }
}

enum EditorToolID: String, CaseIterable, Hashable, Sendable {
    case layout
    case imageTheme
    case weather
    case calendar
    case steps
    case noiseMachine
    case smartPhoto
    case smartPhotoCrop
    case smartRules
    case albumShuffle
    case remix
    case importReview
}

struct EditorTool: Hashable, Sendable {
    var id: EditorToolID
    var title: String
    var isPro: Bool
    var eligibility: EditorToolEligibility

    init(
        id: EditorToolID,
        title: String,
        isPro: Bool,
        eligibility: EditorToolEligibility
    ) {
        self.id = id
        self.title = title
        self.isPro = isPro
        self.eligibility = eligibility
    }
}

enum EditorToolRegistry {

    static func visibleTools(for context: EditorToolContext) -> [EditorTool] {

        let selectionDescriptor = EditorSelectionDescriptor.describe(
            selection: context.selection,
            focus: context.focus
        )

        // 1) Start from all tools.
        var tools = Self.allTools()

        // 2) Apply eligibility engine.
        tools = tools.filter {
            EditorToolEligibilityEngine.isEligible(
                eligibility: $0.eligibility,
                selection: context.selection,
                selectionDescriptor: selectionDescriptor,
                focus: context.focus,
                isProUnlocked: context.isProUnlocked,
                photoLibraryAccess: context.photoLibraryAccess,
                matchedSetEnabled: context.matchedSetEnabled
            )
        }

        // 3) Apply focus gate (hard filter by focus group).
        var eligible = tools.map(\.id)

        let focusGroup = editorToolFocusGroup(for: context.focus)
        eligible = editorToolIDsApplyingFocusGate(
            eligible: eligible,
            focusGroup: focusGroup
        )

        // 4) Apply Smart Photos prioritisation (soft order tweak).
        if focusGroup == .smartPhotos {
            eligible = prioritiseToolsForSmartPhotos(
                eligibleToolIDs: eligible,
                focus: context.focus
            )
        }

        // 5) Rebuild tool list in the final order.
        let byID = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })
        let ordered = eligible.compactMap { byID[$0] }

        // 6) Debug safety checks.
        #if DEBUG
        if ordered.isEmpty {
            print(
                "[EditorToolRegistry] ⚠️ Visible tools empty | template=\(context.template) selection=\(context.selection.cardinalityLabel) focus=\(context.focus.debugLabel) " +
                    "descriptor=(\(selectionDescriptor.cardinalityLabel), \(selectionDescriptor.homogeneityLabel), \(selectionDescriptor.albumSpecificityLabel))"
            )
        } else if ordered.count <= 2 {
            let eligibleToolIDs = ordered.map(\.id)
            print(
                "[EditorToolRegistry] ⚠️ Visible tools suspiciously small (\(eligibleToolIDs.count)) | template=\(context.template) selection=\(context.selection.cardinalityLabel) focus=\(context.focus.debugLabel) " +
                    "tools=\(eligibleToolIDs.map(\.rawValue).joined(separator: ",")) " +
                    "descriptor=(\(selectionDescriptor.cardinalityLabel), \(selectionDescriptor.homogeneityLabel), \(selectionDescriptor.albumSpecificityLabel))"
            )
        }
        #endif

        return ordered
    }

    private static func prioritiseToolsForSmartPhotos(
        eligibleToolIDs: [EditorToolID],
        focus: EditorFocusTarget
    ) -> [EditorToolID] {
        let preferredOrder: [EditorToolID] = {
            switch focus {
            case .smartRules:
                return [.smartRules, .smartPhoto, .smartPhotoCrop, .albumShuffle]
            case .albumShuffle:
                return [.albumShuffle, .smartPhoto, .smartPhotoCrop, .smartRules]
            case .smartPhotoTarget, .smartPhotoContainerSuite:
                return [.smartPhoto, .smartPhotoCrop, .smartRules, .albumShuffle]
            default:
                return []
            }
        }()

        guard !preferredOrder.isEmpty else { return eligibleToolIDs }

        var remaining = eligibleToolIDs
        var prioritised: [EditorToolID] = []

        for id in preferredOrder {
            if let index = remaining.firstIndex(of: id) {
                prioritised.append(id)
                remaining.remove(at: index)
            }
        }

        prioritised.append(contentsOf: remaining)
        return prioritised
    }

    static func legacyVisibleTools(for context: EditorToolContext) -> [EditorTool] {
        Self.allTools()
    }

    private static func allTools() -> [EditorTool] {
        [
            EditorTool(
                id: .layout,
                title: "Layout",
                isPro: false,
                eligibility: EditorToolEligibility(
                    template: .any,
                    focus: .any,
                    selection: .any,
                    selectionDescriptor: .any,
                    supportsMultiSelection: true
                )
            ),
            EditorTool(
                id: .imageTheme,
                title: "Image Theme",
                isPro: false,
                eligibility: EditorToolEligibility(
                    template: .any,
                    focus: .any,
                    selection: .allowsNoneOrSingle,
                    selectionDescriptor: .any,
                    supportsMultiSelection: false,
                    photoLibraryAccess: .requiresAny
                )
            ),
            EditorTool(
                id: .weather,
                title: "Weather",
                isPro: true,
                eligibility: EditorToolEligibility(
                    template: .any,
                    focus: .any,
                    selection: .any,
                    selectionDescriptor: .any,
                    supportsMultiSelection: true
                )
            ),
            EditorTool(
                id: .calendar,
                title: "Calendar",
                isPro: true,
                eligibility: EditorToolEligibility(
                    template: .any,
                    focus: .any,
                    selection: .any,
                    selectionDescriptor: .any,
                    supportsMultiSelection: true
                )
            ),
            EditorTool(
                id: .steps,
                title: "Steps",
                isPro: true,
                eligibility: EditorToolEligibility(
                    template: .any,
                    focus: .any,
                    selection: .any,
                    selectionDescriptor: .any,
                    supportsMultiSelection: true
                )
            ),
            EditorTool(
                id: .noiseMachine,
                title: "Noise Machine",
                isPro: true,
                eligibility: EditorToolEligibility(
                    template: .any,
                    focus: .any,
                    selection: .any,
                    selectionDescriptor: .any,
                    supportsMultiSelection: true
                )
            ),
            EditorTool(
                id: .smartPhoto,
                title: "Smart Photo",
                isPro: false,
                eligibility: EditorToolEligibility(
                    template: .any,
                    focus: .smartPhotoTarget,
                    selection: .allowsNoneOrSingle,
                    selectionDescriptor: .allowsAlbumContainerOrNonAlbumHomogeneousOrNone,
                    supportsMultiSelection: false,
                    photoLibraryAccess: .requiresAny
                )
            ),
            EditorTool(
                id: .smartPhotoCrop,
                title: "Smart Photo Crop",
                isPro: true,
                eligibility: EditorToolEligibility(
                    template: .any,
                    focus: .smartPhotoTarget,
                    selection: .allowsNoneOrSingle,
                    selectionDescriptor: .allowsNonAlbumOnly,
                    supportsMultiSelection: false,
                    photoLibraryAccess: .requiresAny
                )
            ),
            EditorTool(
                id: .smartRules,
                title: "Smart Rules",
                isPro: true,
                eligibility: EditorToolEligibility(
                    template: .any,
                    focus: .smartRules,
                    selection: .any,
                    selectionDescriptor: .any,
                    supportsMultiSelection: true
                )
            ),
            EditorTool(
                id: .albumShuffle,
                title: "Album Shuffle",
                isPro: true,
                eligibility: EditorToolEligibility(
                    template: .any,
                    focus: .albumShuffle,
                    selection: .any,
                    selectionDescriptor: .any,
                    supportsMultiSelection: true,
                    photoLibraryAccess: .requiresAny
                )
            ),
            EditorTool(
                id: .remix,
                title: "Remix",
                isPro: false,
                eligibility: EditorToolEligibility(
                    template: .any,
                    focus: .any,
                    selection: .any,
                    selectionDescriptor: .any,
                    supportsMultiSelection: true
                )
            ),
            EditorTool(
                id: .importReview,
                title: "Import Review",
                isPro: false,
                eligibility: EditorToolEligibility(
                    template: .any,
                    focus: .importReview,
                    selection: .any,
                    selectionDescriptor: .any,
                    supportsMultiSelection: true
                )
            ),
        ]
    }
}
