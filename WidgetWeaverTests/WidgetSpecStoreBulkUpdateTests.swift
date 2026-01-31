//
//  WidgetSpecStoreBulkUpdateTests.swift
//  WidgetWeaver
//
//  Created by . . on 1/31/26.
//

import Foundation
import Testing
@testable import WidgetWeaver

struct WidgetSpecStoreBulkUpdateTests {

    private func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "WidgetSpecStoreBulkUpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func seedStoreWithMultipleSpecs(defaults: UserDefaults) -> WidgetSpecStore {
        let store = WidgetSpecStore(defaults: defaults)

        // Seed additional deterministic specs so the store contains a non-trivial number of designs.
        for i in 1...9 {
            let id = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(i)")!
            let spec = WidgetSpec(
                version: WidgetSpec.currentVersion,
                id: id,
                name: "Spec \(i)",
                primaryText: "Hello",
                secondaryText: nil,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(i)),
                symbol: nil,
                image: nil,
                layout: LayoutSpec.defaultLayout,
                style: StyleSpec.defaultStyle,
                actionBar: nil,
                remindersConfig: nil,
                clockConfig: nil,
                matchedSet: nil
            )
            store.save(spec, makeDefault: false)
        }

        return store
    }

    @Test func bulkUpdate_updatesAllSpecs_andFlushesOnce() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = seedStoreWithMultipleSpecs(defaults: defaults)
        let totalSpecs = store.loadAll().count

        var flushCount = 0
        store.debug_onFlushAndNotifyWidgets = { flushCount += 1 }

        let changed = store.bulkUpdate(ids: nil) { spec in
            var out = spec
            out.name = "Bulk \(spec.name)"
            out.updatedAt = Date(timeIntervalSince1970: 123)
            return out
        }

        #expect(changed == totalSpecs)
        #expect(flushCount == 1)
        #expect(store.loadAll().allSatisfy { $0.name.hasPrefix("Bulk ") })
    }

    @Test func bulkUpdate_updatesSubset_andFlushesOnce() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = seedStoreWithMultipleSpecs(defaults: defaults)

        let target1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let target2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let target3 = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let targets: Set<UUID> = [target1, target2, target3]

        let before = Dictionary(uniqueKeysWithValues: store.loadAll().map { ($0.id, $0) })

        var flushCount = 0
        store.debug_onFlushAndNotifyWidgets = { flushCount += 1 }

        let changed = store.bulkUpdate(ids: targets) { spec in
            var out = spec
            out.primaryText = "Bulk Primary"
            out.updatedAt = Date(timeIntervalSince1970: 456)
            return out
        }

        #expect(changed == targets.count)
        #expect(flushCount == 1)

        let after = Dictionary(uniqueKeysWithValues: store.loadAll().map { ($0.id, $0) })

        for (id, beforeSpec) in before {
            guard let afterSpec = after[id] else {
                #expect(Bool(false))
                continue
            }

            if targets.contains(id) {
                #expect(afterSpec.primaryText == "Bulk Primary")
                #expect(afterSpec.updatedAt == Date(timeIntervalSince1970: 456))
            } else {
                #expect(afterSpec == beforeSpec)
            }
        }
    }
}
