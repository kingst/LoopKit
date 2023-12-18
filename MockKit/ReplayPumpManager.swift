//
//  ReplayPumpManager.swift
//  MockKit
//
//  Created by Sam King on 12/18/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopKitUI
import LoopTestingKit

public class ReplayPumpManager: TestingPumpManager {
    public var reservoirFillFraction: Double = 1.0
    
    public func injectPumpEvents(_ pumpEvents: [LoopKit.NewPumpEvent]) {
        
    }
    
    public static var onboardingMaximumBasalScheduleEntryCount: Int = 1
    
    public static var onboardingSupportedBasalRates: [Double] = []
    
    public static var onboardingSupportedBolusVolumes: [Double] = []
    
    public static var onboardingSupportedMaximumBolusVolumes: [Double] = []
    
    public var delegateQueue: DispatchQueue!
    
    public var supportedBasalRates: [Double] = []
    
    public var supportedBolusVolumes: [Double] = []
    
    public var supportedMaximumBolusVolumes: [Double] = []
    
    public var maximumBasalScheduleEntryCount: Int = 1
    
    public var minimumBasalScheduleEntryDuration: TimeInterval = 30.minutes
    
    public var pumpManagerDelegate: LoopKit.PumpManagerDelegate?
    
    public var pumpRecordsBasalProfileStartEvents: Bool = false
    private static let deliveryUnitsPerMinute = 1.5
    public var pumpReservoirCapacity: Double = 100.0
    
    public var lastSync: Date?
    
    public var status: LoopKit.PumpManagerStatus {
        get {
            return PumpManagerStatus(
                timeZone: .current,
                device: ReplayPumpManager.device,
                pumpBatteryChargeRemaining: 1.0,
                basalDeliveryState: .none,
                bolusState: .noBolus,
                insulinType: .humalog,
                deliveryIsUncertain: false
            )
        }
    }
    
    public func addStatusObserver(_ observer: LoopKit.PumpManagerStatusObserver, queue: DispatchQueue) {
        
    }
    
    public func removeStatusObserver(_ observer: LoopKit.PumpManagerStatusObserver) {
        
    }
    let healthStore = HKHealthStore()
    private var cachedEventLogAuthToken: String?
    
    private func recentGlucoseSamples() async -> [HKQuantitySample] {
        return await withCheckedContinuation() { continuation in
            let sortByDate = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let glucose = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
            let query = HKSampleQuery(sampleType: glucose, predicate: nil, limit: 100, sortDescriptors: [sortByDate]) { (query, results, error) in
                continuation.resume(returning: results as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
    }
    
    private func mostRecentGlucoseSample() async -> HKQuantitySample? {
        let recentSamples = await recentGlucoseSamples()
        print("AuthToken: count \(recentSamples.count)")
        
        let bioKernelSamples = recentSamples.filter { $0.metadata?["bioKernel.totpToken"] != nil }
        
        print("AuthToken: filtered count \(bioKernelSamples.count)")
        return bioKernelSamples.sorted(by: {$0.startDate < $1.startDate}).last
    }
    
    private func downloadEventLogAuthToken(glucoseSample: HKQuantitySample) async -> String? {
        guard let totpToken = glucoseSample.metadata?["bioKernel.totpToken"] as? String, let eventLogId = glucoseSample.metadata?["bioKernel.eventLogId"] as? String else { return nil }
            
        let url = "https://event-log-server.uc.r.appspot.com/v1/event_log/auth/\(eventLogId)/read_only_auth_token"
        let request = EventLogAuthRequest(totpToken: totpToken)
        let response: EventLogAuthResponse? = await JsonHttp().post(url: url, data: request)
        return response?.authToken
    }
    
    private func eventLogAuthToken() async -> String? {
        guard cachedEventLogAuthToken == nil else { return cachedEventLogAuthToken }
        guard let glucoseSample = await mostRecentGlucoseSample() else { return nil }
        cachedEventLogAuthToken = await downloadEventLogAuthToken(glucoseSample: glucoseSample)
        return cachedEventLogAuthToken
    }
    
    public func ensureCurrentPumpData(completion: ((Date?) -> Void)?) {
        Task {
            guard let authToken = await eventLogAuthToken() else {
                print("AuthToken: nil")
                completion?(nil)
                return
            }
            print("AuthToken: \(authToken)")
            let url = "https://event-log-server.uc.r.appspot.com/v1/event_log/query"
            guard let pumpEventsResponse: [EventLogQueryResponse] = await JsonHttp().get(url: url, headers: ["x-auth-token": authToken]) else {
                print("AuthToken: no pump events")
                completion?(nil)
                return
            }
            self.lastSync = pumpEventsResponse.sorted(by: {$0.ctime < $1.ctime}).last?.ctime
            let pumpEvents = pumpEventsResponse.compactMap({ $0.pumpEvents })
            for pumpEvent in pumpEvents {
                delegate.notify { delegate in
                    delegate?.pumpManager(self, hasNewPumpEvents: pumpEvent, lastReconciliation: self.lastSync) { _ in }
                }
            }
            completion?(nil)
        }
    }
    
    public func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool) {
        
    }
    
    public func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> LoopKit.DoseProgressReporter? {
        return nil
    }
    
    public func estimatedDuration(toBolus units: Double) -> TimeInterval {
        return .minutes(units / type(of: self).deliveryUnitsPerMinute)
    }
    
    public func enactBolus(units: Double, activationType: LoopKit.BolusActivationType, completion: @escaping (LoopKit.PumpManagerError?) -> Void) {
        
    }
    
    public func cancelBolus(completion: @escaping (LoopKit.PumpManagerResult<LoopKit.DoseEntry?>) -> Void) {
        
    }
    
    public func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval, completion: @escaping (LoopKit.PumpManagerError?) -> Void) {
        
    }
    
    public func suspendDelivery(completion: @escaping (Error?) -> Void) {
        
    }
    
    public func resumeDelivery(completion: @escaping (Error?) -> Void) {
        
    }
    
    public func syncBasalRateSchedule(items scheduleItems: [LoopKit.RepeatingScheduleValue<Double>], completion: @escaping (Result<LoopKit.BasalRateSchedule, Error>) -> Void) {
        
    }
    
    public func syncDeliveryLimits(limits deliveryLimits: LoopKit.DeliveryLimits, completion: @escaping (Result<LoopKit.DeliveryLimits, Error>) -> Void) {
        
    }
    
    public static let device = HKDevice(
        name: ReplayPumpManager.managerIdentifier,
        manufacturer: nil,
        model: nil,
        hardwareVersion: nil,
        firmwareVersion: nil,
        softwareVersion: "1.0",
        localIdentifier: nil,
        udiDeviceIdentifier: nil
    )
    
    public var testingDevice: HKDevice {
        return ReplayPumpManager.device
    }
    
    public static let managerIdentifier = "ReplayPumpManager"
    public var managerIdentifier: String {
        return ReplayPumpManager.managerIdentifier
    }
    
    public static let localizedTitle = "Replay Pump Manager"
    public var localizedTitle: String { ReplayPumpManager.localizedTitle }
    
    public init() {
        
    }
    
    public required init?(rawState: RawStateValue) {
        
    }
    
    private let delegate = WeakSynchronizedDelegate<PumpManagerDelegate>()
    
    public var rawState: RawStateValue {
        //return ["state": state.rawValue]
        return ["state": "some state"]
    }
    
    public var isOnboarded: Bool = true
    
    public var debugDescription: String = "Replay Pump Manager"
    
    public func acknowledgeAlert(alertIdentifier: LoopKit.Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    
    public func getSoundBaseURL() -> URL? {
        return nil
    }
    
    public func getSounds() -> [LoopKit.Alert.Sound] {
        return []
    }
}

extension ReplayPumpManager: PumpManagerUI {
    public static func setupViewController(initialSettings settings: LoopKitUI.PumpManagerSetupSettings, bluetoothProvider: LoopKit.BluetoothProvider, colorPalette: LoopKitUI.LoopUIColorPalette, allowDebugFeatures: Bool, allowedInsulinTypes: [LoopKit.InsulinType]) -> LoopKitUI.SetupUIResult<LoopKitUI.PumpManagerViewController, LoopKitUI.PumpManagerUI> {
        .createdAndOnboarded(ReplayPumpManager())
    }
    
    public func settingsViewController(bluetoothProvider: LoopKit.BluetoothProvider, colorPalette: LoopKitUI.LoopUIColorPalette, allowDebugFeatures: Bool, allowedInsulinTypes: [LoopKit.InsulinType]) -> LoopKitUI.PumpManagerViewController {
        return PumpManagerSettingsNavigationViewController()
    }
    
    public func deliveryUncertaintyRecoveryViewController(colorPalette: LoopKitUI.LoopUIColorPalette, allowDebugFeatures: Bool) -> (UIViewController & LoopKitUI.CompletionNotifying) {
        return PumpManagerSettingsNavigationViewController()
    }
    
    public func hudProvider(bluetoothProvider: LoopKit.BluetoothProvider, colorPalette: LoopKitUI.LoopUIColorPalette, allowedInsulinTypes: [LoopKit.InsulinType]) -> LoopKitUI.HUDProvider? {
        return nil
    }
    
    public static func createHUDView(rawValue: [String : Any]) -> LoopKitUI.BaseHUDView? {
        return nil
    }
    
    public static var onboardingImage: UIImage? {
        return nil
    }
    
    public var smallImage: UIImage? {
        return nil
    }
    
    public var pumpStatusHighlight: LoopKit.DeviceStatusHighlight? {
        return nil
    }
    
    public var pumpLifecycleProgress: LoopKit.DeviceLifecycleProgress? {
        return nil
    }
    
    public var pumpStatusBadge: LoopKitUI.DeviceStatusBadge? {
        return nil
    }
}

struct EventLogAuthRequest: Codable {
    let totpToken: String
}

struct EventLogAuthResponse: Codable {
    let eventLogId: String
    let authToken: String
}

extension NewPumpEvent: Encodable, Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let date = try container.decode(Date.self, forKey: .date)
        let dose = try container.decodeIfPresent(DoseEntry.self, forKey: .dose)
        let raw = try container.decode(Data.self, forKey: .raw)
        let title = try container.decode(String.self, forKey: .title)
        let alarmType = try container.decodeIfPresent(PumpAlarmType.self, forKey: .alarmType)
        let rawType = try container.decodeIfPresent(String.self, forKey: .type)
        let type = PumpEventType(rawValue: rawType ?? "")

        self.init(date: date, dose: dose, raw: raw, title: title, type: type, alarmType: alarmType)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(dose, forKey: .dose)
        try container.encode(raw, forKey: .raw)
        try container.encodeIfPresent(type?.rawValue, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(alarmType, forKey: .alarmType)
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case dose
        case raw
        case type
        case title
        case alarmType
    }
}

struct EventLogQueryResponse: Decodable {
    let ctime: Date
    let eventLogId: String
    let identifier: String
    let pumpEvents: [NewPumpEvent]?
}

protocol Http {
    func post<ResponseType>(url: String, data: Encodable, headers: [String: String]) async -> ResponseType? where ResponseType: Decodable
    func get<ResponseType>(url: String, headers: [String : String]) async -> ResponseType? where ResponseType : Decodable
}

extension Http {
    func post<ResponseType>(url: String, data: Encodable) async -> ResponseType? where ResponseType: Decodable {
        return await post(url: url, data: data, headers: [:])
    }
    
    func get<ResponseType>(url: String) async -> ResponseType? where ResponseType : Decodable {
        return await get(url: url, headers: [:])
    }
}

struct JsonHttp: Http {
    static let shared = JsonHttp()
    
    func post<ResponseType>(url: String, data: Encodable, headers: [String : String]) async -> ResponseType? where ResponseType : Decodable {
        
        guard let url = URL(string: url) else { return nil }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let jsonData = try? encoder.encode(data) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        guard let httpResponse = response as? HTTPURLResponse else { return nil }
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else { return nil }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return try decoder.decode(ResponseType.self, from: data)
        } catch {
            print("error decoding: \(String(describing: error))")
            return nil
        }
    }
    
    private func getOrHead<ResponseType>(method: String, url: String, headers: [String : String]) async -> ResponseType? where ResponseType : Decodable {
        guard let url = URL(string: url) else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        guard let httpResponse = response as? HTTPURLResponse else { return nil }
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else { return nil }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(ResponseType.self, from: data)
    }
    
    func get<ResponseType>(url: String, headers: [String : String]) async -> ResponseType? where ResponseType : Decodable {
        return await getOrHead(method: "GET", url: url, headers: headers)
    }
}
