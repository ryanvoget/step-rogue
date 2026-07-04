import SwiftGodot
import HealthKit

@Godot
class HealthKitBridge: RefCounted {
    @Signal var stepsReady: SignalWithArguments<Int>
    @Signal var healthUnavailable: SimpleSignal

    private var healthStore: HKHealthStore?

    required init(_ context: InitContext) {
        super.init(context)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore = HKHealthStore()
    }

    @Callable
    func requestAndFetch() {
        print("[HKBridge] requestAndFetch called, healthStore=\(healthStore != nil)")
        guard let store = healthStore else {
            print("[HKBridge] no healthStore — emitting health_unavailable")
            healthUnavailable.emit()
            return
        }
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        print("[HKBridge] requesting HealthKit authorization")
        store.requestAuthorization(toShare: [], read: [stepType]) { [weak self] success, error in
            print("[HKBridge] auth callback success=\(success) error=\(String(describing: error))")
            guard let self, success else {
                self?.healthUnavailable.emit()
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
                self?.stepsReady.emit(count)
            }
        }
        store.execute(query)
    }
}
