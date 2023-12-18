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

public class ReplayPump {
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
    
    public func downloadPumpEvents(completion: @escaping (([NewPumpEvent]) -> Void)) {
        Task {
            guard let authToken = await eventLogAuthToken() else {
                print("AuthToken: nil")
                DispatchQueue.main.async { completion([]) }
                return
            }
            print("AuthToken: \(authToken)")
            let url = "https://event-log-server.uc.r.appspot.com/v1/event_log/query"
            guard let pumpEventsResponse: [EventLogQueryResponse] = await JsonHttp().get(url: url, headers: ["x-auth-token": authToken]) else {
                print("AuthToken: no pump events")
                DispatchQueue.main.async { completion([]) }
                return
            }
            let pumpEvents = pumpEventsResponse.compactMap({ $0.pumpEvents }).reduce([]) { $0 + $1 }
            
            DispatchQueue.main.async { completion(pumpEvents) }
        }
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
