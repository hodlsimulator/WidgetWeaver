//
//  WidgetSpecAISnapshotStore.swift
//  WidgetWeaver
//
//  Created by . . on 1/29/26.
//

import Foundation

public struct WidgetSpecAISnapshot: Codable, Hashable {

    public enum ApplyMode: String, Codable, Hashable {
        case generate
        case patch
    }

    public var mode: ApplyMode
    public var capturedAt: Date

    /// The editor state immediately before Apply was tapped.
    public var preApplySpec: WidgetSpec

    /// The selected design ID immediately before Apply was tapped.
    public var preSelectedSpecID: UUID

    /// The default design ID immediately before Apply was tapped.
    public var preDefaultSpecID: UUID?

    /// The design ID that Apply wrote to (saved or created).
    public var appliedSpecID: UUID

    /// True when a design with `appliedSpecID` existed in storage before Apply ran.
    public var appliedSpecExistedBeforeApply: Bool

    /// When Apply overwrote an existing, different spec ID, this contains the pre-Apply stored value.
    public var overwrittenAppliedSpecBefore: WidgetSpec?

    public init(
        mode: ApplyMode,
        capturedAt: Date,
        preApplySpec: WidgetSpec,
        preSelectedSpecID: UUID,
        preDefaultSpecID: UUID?,
        appliedSpecID: UUID,
        appliedSpecExistedBeforeApply: Bool,
        overwrittenAppliedSpecBefore: WidgetSpec?
    ) {
        self.mode = mode
        self.capturedAt = capturedAt
        self.preApplySpec = preApplySpec
        self.preSelectedSpecID = preSelectedSpecID
        self.preDefaultSpecID = preDefaultSpecID
        self.appliedSpecID = appliedSpecID
        self.appliedSpecExistedBeforeApply = appliedSpecExistedBeforeApply
        self.overwrittenAppliedSpecBefore = overwrittenAppliedSpecBefore
    }
}

/// Stores the most recent “pre-AI-apply” snapshot so the editor can restore it with one tap.
///
/// Storage characteristics:
/// - One slot only (overwrites on each AI Apply).
/// - App Group (shared between app + widget extension).
public enum WidgetSpecAISnapshotStore {
    private enum Keys {
        static let snapshotData = "widgetweaver.ai.undo.snapshot.v1"
    }

    public static var hasSnapshot: Bool {
        load() != nil
    }

    public static func load() -> WidgetSpecAISnapshot? {
        let defaults = AppGroup.userDefaults
        guard let data = defaults.data(forKey: Keys.snapshotData) else { return nil }

        let decoder = makeDecoder()
        do {
            return try decoder.decode(WidgetSpecAISnapshot.self, from: data)
        } catch {
            // If decoding fails, clear the slot to avoid repeated failures.
            defaults.removeObject(forKey: Keys.snapshotData)
            defaults.synchronize()
            return nil
        }
    }

    public static func save(_ snapshot: WidgetSpecAISnapshot) {
        let defaults = AppGroup.userDefaults
        let encoder = makeEncoder()

        do {
            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: Keys.snapshotData)
            defaults.synchronize()
        } catch {
            // Encoding failures should not block Apply.
        }
    }

    public static func clear() {
        let defaults = AppGroup.userDefaults
        defaults.removeObject(forKey: Keys.snapshotData)
        defaults.synchronize()
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
