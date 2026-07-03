import SwiftGodot
import HealthKit

// Registered with Godot via initHookCb in ParsecApp.init().
// GDScript accesses this class by name ("HealthKitBridge") through ClassDB —
// the same interface sync_steps.gd already uses.
@Godot
class HealthKitBridge: RefCounted {
    @Signal var stepsReady: SignalWith1Argument<Int>
    @Signal var healthUnavailable: SimpleSignal

    private var healthStore: HKHealthStore?

    required init(_ context: InitContext) {
        super.init(context)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore = HKHealthStore()
    }

    @Callable
    func requestAndFetch() {
        guard let store = healthStore else {
            emit(signal: HealthKitBridge.healthUnavailable)
            return
        }
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        store.requestAuthorization(toShare: [], read: [stepType]) { [weak self] success, _ in
            guard let self, success else {
                self?.emit(signal: HealthKitBridge.healthUnavailable)
                return
            }
            self.fetchSteps(store: store, stepType: stepType)
        }
    }

    private func fetchSteps(store: HKHealthStore, stepType: HKQuantityType) {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, _ in
            let count = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            DispatchQueue.main.async {
                self?.emit(signal: HealthKitBridge.stepsReady, count)
            }
        }
        store.execute(query)
    }
}
