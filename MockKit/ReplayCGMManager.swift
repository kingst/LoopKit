//
//  ReplayCGMManager.swift
//  MockKit
//
//  Created by Sam King on 12/18/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopKitUI
import LoopTestingKit
import UIKit

public struct ReplayCGMState: GlucoseDisplayable {
    public var isStateValid: Bool
    public var queryAnchor: Data?
    
    public var trendType: LoopKit.GlucoseTrend?
    
    public var trendRate: HKQuantity?
    
    public var isLocal: Bool = true
    
    public var glucoseRangeCategory: LoopKit.GlucoseRangeCategory?
}

public final class ReplayCGMManager: TestingCGMManager {
    public func injectGlucoseSamples(_ samples: [LoopKit.NewGlucoseSample]) {
        
    }
    
    public var cgmManagerDelegate: LoopKit.CGMManagerDelegate? {
        get {
            return delegate.delegate
        }
        set {
            delegate.delegate = newValue
        }
    }
    
    public var providesBLEHeartbeat: Bool = false
    
    public var managedDataInterval: TimeInterval?
    
    public var shouldSyncToRemoteService: Bool = false
    
    private var lastCommunicationDate: Date? = nil
    
    public var cgmManagerStatus: LoopKit.CGMManagerStatus {
        return CGMManagerStatus(hasValidSensorSession: true, lastCommunicationDate: lastCommunicationDate, device: testingDevice)
    }
    
    public var delegateQueue: DispatchQueue! {
        get {
            return delegate.queue
        }
        set {
            delegate.queue = newValue
        }
    }

    private let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()
    
    let glucose = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
    let healthStore = HKHealthStore()
    private var query: HKAnchoredObjectQuery?
    
    func handleResults(_ query: HKAnchoredObjectQuery, _ samplesOrNil: [HKSample]?, _ deletedObjectsOrNil: [HKDeletedObject]?, _ newAnchor: HKQueryAnchor?, _ errorOrNil: Error?) {
        print("handleResults")
        guard let samples = samplesOrNil, let quantitySamples = samples as? [HKQuantitySample], let deletedObjects = deletedObjectsOrNil else {
            print("Query error for \(glucose)")
            return
        }
        
        let glucoseSamples = samples.map { sample in
            let quantitySample = sample as! HKQuantitySample
            let syncId = (sample.metadata?["bioKernel.syncIdentifier"] as? String) ?? UUID().uuidString
            return NewGlucoseSample(date: sample.startDate, quantity: quantitySample.quantity, condition: nil, trend: nil, trendRate: nil, isDisplayOnly: false, wasUserEntered: false, syncIdentifier: syncId)
        }
        
        sendCGMReadingResult(.newData(glucoseSamples))
    }
    
    public func fetchNewDataIfNeeded(_ completion: @escaping (LoopKit.CGMReadingResult) -> Void) {
        print("fetchNewDataIfNeeded")
        completion(.noData)
    }
    
    public var testingDevice = HKDevice(
        name: "ReplayCGMManager",
        manufacturer: "LoopKit",
        model: "ReplayCGMManager",
        hardwareVersion: nil,
        firmwareVersion: nil,
        softwareVersion: "1.0",
        localIdentifier: nil,
        udiDeviceIdentifier: nil
    )
    
    deinit {
        if let query = query {
            healthStore.stop(query)
        }
    }
    
    public init() {
        let datePredicate = HKQuery.predicateForSamples(withStart: Date() - 1.hours, end: nil)
        query = HKAnchoredObjectQuery(type: glucose, predicate: datePredicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: self.handleResults)
        if let query = query {
            query.updateHandler = self.handleResults
            healthStore.execute(query)
        }
    }
    
    public init?(rawState: RawStateValue) {
        if let replaySensorStateRawValue = rawState["replaySensorState"] as? ReplayCGMState.RawValue,
            let replaySensorState = ReplayCGMState(rawValue: replaySensorStateRawValue) {
            self.lockedReplaySensorState.value = replaySensorState
        } else {
            self.lockedReplaySensorState.value = ReplayCGMState(isStateValid: true)
            self.notifyStatusObservers(cgmManagerStatus: self.cgmManagerStatus)
        }
        
        // FIXME: save the anchor and set it here
        let datePredicate = HKQuery.predicateForSamples(withStart: Date() - 1.hours, end: nil)
        query = HKAnchoredObjectQuery(type: glucose, predicate: datePredicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: self.handleResults)
        if let query = query {
            query.updateHandler = self.handleResults
            healthStore.execute(query)
        }
    }
    
    private var statusObservers = WeakSynchronizedSet<CGMManagerStatusObserver>()

    public func addStatusObserver(_ observer: CGMManagerStatusObserver, queue: DispatchQueue) {
        statusObservers.insert(observer, queue: queue)
    }

    public func removeStatusObserver(_ observer: CGMManagerStatusObserver) {
        statusObservers.removeElement(observer)
    }
    
    private func notifyStatusObservers(cgmManagerStatus: CGMManagerStatus) {
        delegate.notify { delegate in
            delegate?.cgmManagerDidUpdateState(self)
            delegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
        }
        statusObservers.forEach { observer in
            observer.cgmManager(self, didUpdate: cgmManagerStatus)
        }
    }
    
    private let lockedReplaySensorState = Locked(ReplayCGMState(isStateValid: true))
    public var replaySensorState: ReplayCGMState {
        get {
            lockedReplaySensorState.value
        }
        set {
            lockedReplaySensorState.mutate { $0 = newValue }
        }
    }

    public var glucoseDisplay: GlucoseDisplayable? {
        return replaySensorState
    }
    
    public var rawState: RawStateValue {
        return [
            "replaySensorState": replaySensorState.rawValue
        ]
    }
    
    public var isOnboarded: Bool = true
    
    public var debugDescription: String = "ReplayCGMManager"
    
    
    public static let managerIdentifier = "ReplayCGMManager"

    public var managerIdentifier: String {
        return ReplayCGMManager.managerIdentifier
    }
    
    public static let localizedTitle = "Replay CGM"
    
    public var localizedTitle: String {
        return ReplayCGMManager.localizedTitle
    }

    private func sendCGMReadingResult(_ result: CGMReadingResult) {
        self.delegate.notify { delegate in
            delegate?.cgmManager(self, hasNew: result)
        }
    }
    
}

// MARK: Alert Stuff, just ignore this since we won't issue alerts

extension ReplayCGMManager {
    
    public func getSoundBaseURL() -> URL? { return nil }
    public func getSounds() -> [Alert.Sound] { return [] }
    public var hasRetractableAlert: Bool { return false }
    public var currentAlertIdentifier: Alert.AlertIdentifier? { return nil }
    
    public func issueAlert(identifier: Alert.AlertIdentifier, trigger: Alert.Trigger, delay: TimeInterval?, metadata: Alert.Metadata? = nil) {
    }
    
    public func issueSignalLossAlert() {
    }
    
    public func retractSignalLossAlert() {

    }
    
    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    public func retractCurrentAlert() {
    }

    public func retractAlert(identifier: Alert.AlertIdentifier) {

    }
    
}

extension ReplayCGMState: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let isStateValid = rawValue["isStateValid"] as? Bool else
        {
            return nil
        }
        self.isStateValid = isStateValid
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [
            "isStateValid": isStateValid
        ]
        return rawValue
    }
}

extension ReplayCGMManager: CGMManagerUI {
    public static func setupViewController(bluetoothProvider: LoopKit.BluetoothProvider, displayGlucoseUnitObservable: LoopKitUI.DisplayGlucoseUnitObservable, colorPalette: LoopKitUI.LoopUIColorPalette, allowDebugFeatures: Bool) -> LoopKitUI.SetupUIResult<LoopKitUI.CGMManagerViewController, LoopKitUI.CGMManagerUI> {
        .createdAndOnboarded(ReplayCGMManager())
    }
    
    public func settingsViewController(bluetoothProvider: LoopKit.BluetoothProvider, displayGlucoseUnitObservable: LoopKitUI.DisplayGlucoseUnitObservable, colorPalette: LoopKitUI.LoopUIColorPalette, allowDebugFeatures: Bool) -> LoopKitUI.CGMManagerViewController {
        return CGMManagerSettingsNavigationViewController()
    }
    
    public static var onboardingImage: UIImage? {
        return nil
    }
    
    public var smallImage: UIImage? {
        return nil
    }
    
    public var cgmStatusHighlight: LoopKit.DeviceStatusHighlight? {
        return nil
    }
    
    public var cgmLifecycleProgress: LoopKit.DeviceLifecycleProgress? {
        return nil
    }
    
    public var cgmStatusBadge: LoopKitUI.DeviceStatusBadge? {
        return nil
    }
}
