//
//  WidgetWeaverDesignExchangeCodecTests.swift
//  WidgetWeaver
//
//  Created by . . on 1/24/26.
//

import Foundation
import Testing
@testable import WidgetWeaver

struct WidgetWeaverDesignExchangeCodecTests {

    @Test func decodeAny_acceptsLegacyWidgetSpecArrayWithISO8601Dates() throws {
        let specA = WidgetSpec(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Import A",
            primaryText: "Hello",
            secondaryText: nil,
            updatedAt: Date(timeIntervalSince1970: 1_735_000_000),
            symbol: nil,
            image: nil,
            layout: .defaultLayout,
            style: .defaultStyle,
            actionBar: nil,
            remindersConfig: nil,
            clockConfig: nil,
            matchedSet: nil
        )

        let specB = WidgetSpec(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Import B",
            primaryText: "World",
            secondaryText: "Secondary",
            updatedAt: Date(timeIntervalSince1970: 1_736_000_000),
            symbol: nil,
            image: nil,
            layout: .defaultLayout,
            style: .defaultStyle,
            actionBar: nil,
            remindersConfig: nil,
            clockConfig: nil,
            matchedSet: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode([specA, specB])

        let payload = try WidgetWeaverDesignExchangeCodec.decodeAny(data)

        #expect(payload.specs.count == 2)

        let ids = Set(payload.specs.map(\.id))
        #expect(ids.contains(specA.id))
        #expect(ids.contains(specB.id))
    }

    @Test func decodeAny_acceptsLegacySingleWidgetSpecWithISO8601Dates() throws {
        let spec = WidgetSpec(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Import Single",
            primaryText: "Single",
            secondaryText: nil,
            updatedAt: Date(timeIntervalSince1970: 1_735_555_555),
            symbol: nil,
            image: nil,
            layout: .defaultLayout,
            style: .defaultStyle,
            actionBar: nil,
            remindersConfig: nil,
            clockConfig: nil,
            matchedSet: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(spec)

        let payload = try WidgetWeaverDesignExchangeCodec.decodeAny(data)

        #expect(payload.specs.count == 1)
        #expect(payload.specs.first?.id == spec.id)
        #expect(payload.specs.first?.name == spec.name)
    }
}
