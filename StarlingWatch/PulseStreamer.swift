import Foundation
import HealthKit
import WatchConnectivity
import Observation

/// Runs a workout session so the Watch samples heart rate every few seconds, and streams it to the phone.
@Observable
final class PulseStreamer: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, WCSessionDelegate {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    var bpm: Double?
    var isRunning = false
    var status = "Tap start, then read on your iPhone."
    private var sent = 0

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func start() {
        guard HKHealthStore.isHealthDataAvailable(), let hr = HKObjectType.quantityType(forIdentifier: .heartRate) else { status = "Health data unavailable"; return }
        store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [hr]) { [weak self] ok, err in
            guard let self else { return }
            guard ok else { DispatchQueue.main.async { self.status = "Health access denied" }; return }
            let config = HKWorkoutConfiguration()
            config.activityType = .other
            config.locationType = .indoor
            do {
                let session = try HKWorkoutSession(healthStore: self.store, configuration: config)
                let builder = session.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: self.store, workoutConfiguration: config)
                session.delegate = self
                builder.delegate = self
                self.session = session
                self.builder = builder
                let start = Date()
                session.startActivity(with: start)
                builder.beginCollection(withStart: start) { _, _ in }
                DispatchQueue.main.async { self.isRunning = true; self.status = "Streaming to Starling…" }
            } catch {
                DispatchQueue.main.async { self.status = "Couldn't start: \(error.localizedDescription)" }
            }
        }
    }

    func stop() {
        session?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.discardWorkout()
        }
        isRunning = false
        status = "Stopped"
    }

    // MARK: HKLiveWorkoutBuilderDelegate
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let hr = HKQuantityType.quantityType(forIdentifier: .heartRate), collectedTypes.contains(hr),
              let stats = workoutBuilder.statistics(for: hr),
              let q = stats.mostRecentQuantity() else { return }
        let value = q.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        DispatchQueue.main.async {
            self.bpm = value
            self.send(value)
        }
    }
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    // MARK: HKWorkoutSessionDelegate
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { self.isRunning = (toState == .running) }
    }
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.status = "Session error: \(error.localizedDescription)"; self.isRunning = false }
    }

    // MARK: WCSession
    private func send(_ bpm: Double) {
        let payload: [String: Any] = ["bpm": bpm, "t": Date().timeIntervalSince1970]
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil) { _ in }
            sent += 1
            status = "Live · sent \(sent)"
        } else {
            try? s.updateApplicationContext(payload)
            status = "Phone not reachable — open Starling on iPhone"
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
