import Foundation
import HealthKit

/// Heart rate samples written by Apple Watch, via HealthKit. Fresh samples beat the camera.
final class WatchPulseSource {
    private let store = HKHealthStore()
    private var query: HKAnchoredObjectQuery?
    private let onSample: (Double, Date) -> Void
    private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()
    private(set) var authorised = false

    init(onSample: @escaping (Double, Date) -> Void) { self.onSample = onSample }

    func start() {
        guard isAvailable, let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        store.requestAuthorization(toShare: [], read: [hrType]) { [weak self] ok, _ in
            guard ok, let self else { return }
            self.authorised = true
            let unit = HKUnit.count().unitDivided(by: .minute())
            let since = Date().addingTimeInterval(-10 * 60)
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
            let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, _, _, _ in
                guard let self, let latest = (samples as? [HKQuantitySample])?.max(by: { $0.startDate < $1.startDate }) else { return }
                let bpm = latest.quantity.doubleValue(for: unit)
                DispatchQueue.main.async { self.onSample(bpm, latest.startDate) }
            }
            let q = HKAnchoredObjectQuery(type: hrType, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
            q.updateHandler = handler
            self.query = q
            self.store.execute(q)
            self.store.enableBackgroundDelivery(for: hrType, frequency: .immediate) { _, _ in }
        }
    }

    func stop() { if let q = query { store.stop(q) } }
}
