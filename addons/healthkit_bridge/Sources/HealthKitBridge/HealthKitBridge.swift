import SwiftGodot
import HealthKit

@Godot
class HealthKitBridge: RefCounted {
    // Emitted on the main thread after a successful step query.
    #signal("steps_ready", arguments: ["count": Int.self])
    // Emitted when HealthKit is unavailable or permission is denied.
    #signal("health_unavailable")

    private var healthStore: HKHealthStore?

    required init() {
        super.init()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore = HKHealthStore()
    }

    required init(nativeHandle: UnsafeRawPointer) {
        super.init(nativeHandle: nativeHandle)
    }

    // Call from GDScript as `request_and_fetch()`.
    // Requests read permission then queries today's step count.
    @Callable
    func requestAndFetch() {
        guard let store = healthStore else {
            emit(signal: HealthKitBridge.healthUnavailable)
            return
        }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            emit(signal: HealthKitBridge.healthUnavailable)
            return
        }
        store.requestAuthorization(toShare: nil, read: [stepType]) { [weak self] granted, _ in
            guard let self else { return }
            guard granted else {
                self.emit(signal: HealthKitBridge.healthUnavailable)
                return
            }
            self.queryTodaySteps(store: store, stepType: stepType)
        }
    }

    private func queryTodaySteps(store: HKHealthStore, stepType: HKQuantityType) {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate  = HKQuery.predicateForSamples(
            withStart: startOfDay, end: Date(), options: .strictStartDate
        )
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, _ in
            let count = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            self?.emit(signal: HealthKitBridge.stepsReady, count)
        }
        store.execute(query)
    }
}

// Generates the C entry point that Godot loads via the .gdextension file.
#initSwiftExtension(cdecl: "healthkit_bridge_init", types: [HealthKitBridge.self])
