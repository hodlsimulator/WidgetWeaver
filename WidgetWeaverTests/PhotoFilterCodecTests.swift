//
//  PhotoFilterCodecTests.swift
//  WidgetWeaver
//
//  Created by . . on 1/30/26.
//

import Foundation
import Testing
@testable import WidgetWeaver

struct PhotoFilterCodecTests {

    private func decodeImageSpec(_ json: String) throws -> ImageSpec {
        try JSONDecoder().decode(ImageSpec.self, from: Data(json.utf8))
    }

    private func encodeToJSONObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private func filterDict(from jsonObject: Any) -> [String: Any]? {
        guard let dict = jsonObject as? [String: Any] else { return nil }
        return dict["filter"] as? [String: Any]
    }

    @Test func imageSpec_roundTrip_preservesFilterTokenAndIntensity() throws {
        let original = ImageSpec(
            fileName: "photo.jpg",
            contentMode: .fill,
            height: 123,
            cornerRadius: 17,
            filter: PhotoFilterSpec(token: .noir, intensity: 0.42),
            smartPhoto: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImageSpec.self, from: data)

        #expect(decoded.fileName == "photo.jpg")
        #expect(decoded.contentMode == .fill)
        #expect(decoded.filter?.token == .noir)

        let intensity = decoded.filter?.intensity ?? -1
        #expect(abs(intensity - 0.42) < 0.000_001)
    }

    @Test func imageSpec_decodeWithoutFilterKey_defaultsToNil() throws {
        let json = #"{"fileName":"a.jpg","contentMode":"fill","height":120,"cornerRadius":16}"#
        let decoded = try decodeImageSpec(json)

        #expect(decoded.fileName == "a.jpg")
        #expect(decoded.contentMode == .fill)
        #expect(decoded.filter == nil)
    }

    @Test func imageSpec_decodeLegacyCropKey_isSupported() throws {
        let json = #"{"fileName":"a.jpg","crop":"fit","height":120,"cornerRadius":16}"#
        let decoded = try decodeImageSpec(json)

        #expect(decoded.fileName == "a.jpg")
        #expect(decoded.contentMode == .fit)
        #expect(decoded.filter == nil)
    }

    @Test func imageSpec_decodeFilterIntensityBelowZero_becomesNil() throws {
        let json = #"{"fileName":"a.jpg","contentMode":"fill","height":120,"cornerRadius":16,"filter":{"token":"noir","intensity":-1}}"#
        let decoded = try decodeImageSpec(json)

        #expect(decoded.filter == nil)
    }

    @Test func imageSpec_decodeFilterIntensityAboveOne_clampsToOne() throws {
        let json = #"{"fileName":"a.jpg","contentMode":"fill","height":120,"cornerRadius":16,"filter":{"token":"noir","intensity":2.5}}"#
        let decoded = try decodeImageSpec(json)

        #expect(decoded.filter?.token == .noir)
        #expect(decoded.filter?.intensity == 1.0)
    }

    @Test func imageSpec_encode_omitsFilterKeyWhenItNormalisesToNone() throws {
        let cases: [ImageSpec] = [
            ImageSpec(
                fileName: "a.jpg",
                contentMode: .fill,
                height: 120,
                cornerRadius: 16,
                filter: PhotoFilterSpec(token: .none, intensity: 1.0),
                smartPhoto: nil
            ),
            ImageSpec(
                fileName: "a.jpg",
                contentMode: .fill,
                height: 120,
                cornerRadius: 16,
                filter: PhotoFilterSpec(token: .noir, intensity: 0.0),
                smartPhoto: nil
            ),
            ImageSpec(
                fileName: "a.jpg",
                contentMode: .fill,
                height: 120,
                cornerRadius: 16,
                filter: PhotoFilterSpec(token: .noir, intensity: .nan),
                smartPhoto: nil
            ),
        ]

        for spec in cases {
            let obj = try encodeToJSONObject(spec)
            let filter = filterDict(from: obj)
            #expect(filter == nil)
        }
    }

    @Test func imageSpec_encode_clampsFilterIntensityAboveOne() throws {
        let spec = ImageSpec(
            fileName: "a.jpg",
            contentMode: .fill,
            height: 120,
            cornerRadius: 16,
            filter: PhotoFilterSpec(token: .sepia, intensity: 9.0),
            smartPhoto: nil
        )

        let obj = try encodeToJSONObject(spec)
        let filter = filterDict(from: obj)

        #expect(filter != nil)
        #expect(filter?["token"] as? String == "sepia")

        let intensity = (filter?["intensity"] as? NSNumber)?.doubleValue
        #expect(intensity == 1.0)
    }
}
