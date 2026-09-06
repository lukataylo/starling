import Foundation
import HealthKit
import WatchConnectivity

/// Heart rate from Apple Watch. Two paths: live messages from the Starling watch app (seconds),
/// and HealthKit samples the Watch syncs on its own (minutes). Whichever is newest wins.
final class WatchPulseSource: NSObject, WCSessionDelegate {
    private let store = HKHealthStore()
    private var query: HKAnchoredObjectQuery?
    private let onSample: (Double, Date, Bool) -> Void   // bpm, when, isLive
    private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()
    private(set) var authorised = false
    private(set) var watchAppReachable = false

    init(onSample: @escaping (Double, Date, Bool) -> Void) {
        self.onSample = onSample
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

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
                DispatchQueue.main.async { self.onSample(bpm, latest.startDate, false) }
            }
            let q = HKAnchoredObjectQuery(type: hrType, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
            q.updateHandler = handler
            self.query = q
            self.store.execute(q)
            self.store.enableBackgroundDelivery(for: hrType, frequency: .immediate) { _, _ in }
        }
    }

    func stop() { if let q = query { store.stop(q) } }

    // MARK: WCSessionDelegate — live stream from the watch app
    private func handle(_ payload: [String: Any]) {
        guard let bpm = payload["bpm"] as? Double else { return }
        let t = (payload["t"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? Date()
        DispatchQueue.main.async { self.onSample(bpm, t, true) }
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { handle(applicationContext) }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        watchAppReachable = session.isReachable
    }
    func sessionReachabilityDidChange(_ session: WCSession) { watchAppReachable = session.isReachable }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
