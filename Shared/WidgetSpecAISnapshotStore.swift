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

    public var preApplySpec: WidgetSpec
    public var preSelectedSpecID: UUID
    public var preDefaultSpecID: UUID?

    public var appliedSpecID: UUID
    public var appliedSpecExistedBeforeApply: Bool

    /// When an Apply overwrote an existing spec that was not the one being edited, this stores the overwritten value.
    /// This is expected to be nil for the current Generate/Patch flows, but is kept for resilience.
    public var overwrittenAppliedSpecBefore: WidgetSpec?

    public init(
        mode: ApplyMode,
        capturedAt: Date,
        preApplySpec: WidgetSpec,
        preSelectedSpecID: UUID,
        preDefaultSpecID: UUID?,
        appliedSpecID: UUID,
        appliedSpecExistedBeforeApply: Bool,
        overwrittenAppliedSpecBefore: WidgetSpec? = nil
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

public enum WidgetSpecAISnapshotStore {
    private enum Keys {
        static let snapshotData = "widgetweaver.ai.undo.snapshot.v1"
    }

    private static let floatStringPositiveInfinity = "Infinity"
    private static let floatStringNegativeInfinity = "-Infinity"
    private static let floatStringNaN = "NaN"

    @inline(__always)
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: floatStringPositiveInfinity,
            negativeInfinity: floatStringNegativeInfinity,
            nan: floatStringNaN
        )
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    @inline(__always)
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: floatStringPositiveInfinity,
            negativeInfinity: floatStringNegativeInfinity,
            nan: floatStringNaN
        )
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static var hasSnapshot: Bool {
        load() != nil
    }

    public static func load() -> WidgetSpecAISnapshot? {
        let ud = AppGroup.userDefaults
        guard let data = ud.data(forKey: Keys.snapshotData) else { return nil }

        let decoder = makeDecoder()
        do {
            return try decoder.decode(WidgetSpecAISnapshot.self, from: data)
        } catch {
            ud.removeObject(forKey: Keys.snapshotData)
            ud.synchronize()
            return nil
        }
    }

    public static func save(_ snapshot: WidgetSpecAISnapshot) {
        let ud = AppGroup.userDefaults
        let encoder = makeEncoder()

        do {
            let data = try encoder.encode(snapshot)
            ud.set(data, forKey: Keys.snapshotData)
            ud.synchronize()
        } catch {
            // Encoding failures should not block Apply.
        }
    }

    public static func clear() {
        let ud = AppGroup.userDefaults
        ud.removeObject(forKey: Keys.snapshotData)
        ud.synchronize()
    }
}
