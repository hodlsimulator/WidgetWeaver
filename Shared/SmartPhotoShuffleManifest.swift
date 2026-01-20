//
//  SmartPhotoShuffleManifest.swift
//  WidgetWeaver
//
//  Created by . . on 1/5/26.
//

import Foundation

public struct SmartPhotoShuffleManifest: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var masterFileName: String

        public var smallAutoRenderFileName: String
        public var mediumAutoRenderFileName: String
        public var largeAutoRenderFileName: String

        public var smallAutoCropRect: NormalisedRect
        public var mediumAutoCropRect: NormalisedRect
        public var largeAutoCropRect: NormalisedRect

        public var smallManualRenderFileName: String?
        public var mediumManualRenderFileName: String?
        public var largeManualRenderFileName: String?

        public var smallManualCropRect: NormalisedRect?
        public var mediumManualCropRect: NormalisedRect?
        public var largeManualCropRect: NormalisedRect?

        public var smallManualStraightenDegrees: Double?
        public var mediumManualStraightenDegrees: Double?
        public var largeManualStraightenDegrees: Double?

        /// Optional clockwise quarter-turn rotations (90° steps) applied before straightening.
        /// Nil (or effectively zero) means no rotation.
        public var smallManualRotationQuarterTurns: Int?
        public var mediumManualRotationQuarterTurns: Int?
        public var largeManualRotationQuarterTurns: Int?

        public var preparedAt: Date?

        public init(
            id: String,
            masterFileName: String,
            smallAutoRenderFileName: String,
            mediumAutoRenderFileName: String,
            largeAutoRenderFileName: String,
            smallAutoCropRect: NormalisedRect,
            mediumAutoCropRect: NormalisedRect,
            largeAutoCropRect: NormalisedRect,
            smallManualRenderFileName: String? = nil,
            mediumManualRenderFileName: String? = nil,
            largeManualRenderFileName: String? = nil,
            smallManualCropRect: NormalisedRect? = nil,
            mediumManualCropRect: NormalisedRect? = nil,
            largeManualCropRect: NormalisedRect? = nil,
            smallManualStraightenDegrees: Double? = nil,
            mediumManualStraightenDegrees: Double? = nil,
            largeManualStraightenDegrees: Double? = nil,
            smallManualRotationQuarterTurns: Int? = nil,
            mediumManualRotationQuarterTurns: Int? = nil,
            largeManualRotationQuarterTurns: Int? = nil,
            preparedAt: Date? = nil
        ) {
            self.id = id
            self.masterFileName = masterFileName
            self.smallAutoRenderFileName = smallAutoRenderFileName
            self.mediumAutoRenderFileName = mediumAutoRenderFileName
            self.largeAutoRenderFileName = largeAutoRenderFileName
            self.smallAutoCropRect = smallAutoCropRect
            self.mediumAutoCropRect = mediumAutoCropRect
            self.largeAutoCropRect = largeAutoCropRect
            self.smallManualRenderFileName = smallManualRenderFileName
            self.mediumManualRenderFileName = mediumManualRenderFileName
            self.largeManualRenderFileName = largeManualRenderFileName
            self.smallManualCropRect = smallManualCropRect
            self.mediumManualCropRect = mediumManualCropRect
            self.largeManualCropRect = largeManualCropRect
            self.smallManualStraightenDegrees = smallManualStraightenDegrees
            self.mediumManualStraightenDegrees = mediumManualStraightenDegrees
            self.largeManualStraightenDegrees = largeManualStraightenDegrees
            self.smallManualRotationQuarterTurns = smallManualRotationQuarterTurns
            self.mediumManualRotationQuarterTurns = mediumManualRotationQuarterTurns
            self.largeManualRotationQuarterTurns = largeManualRotationQuarterTurns
            self.preparedAt = preparedAt
        }
    }

    public var createdAt: Date
    public var entries: [Entry]

    public init(createdAt: Date, entries: [Entry]) {
        self.createdAt = createdAt
        self.entries = entries
    }
}
