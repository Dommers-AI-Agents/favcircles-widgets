import Foundation
import FavWidgetsCore
#if canImport(HealthKit) && os(iOS)
import HealthKit
#endif

/// Reads sleep from Apple Health — read-only; nothing is written to Health
/// and nothing leaves the phone except the nights saved to the widget.
enum SleepHealthReader {
    static var isAvailable: Bool {
        #if canImport(HealthKit) && os(iOS)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    #if canImport(HealthKit) && os(iOS)
    private static let store = HKHealthStore()
    private static let sleepType = HKCategoryType(.sleepAnalysis)
    #endif

    /// Shows Apple's permission sheet (first time only). Health never says
    /// whether READ access was granted, so callers just try to read.
    static func requestAccess() async -> Bool {
        #if canImport(HealthKit) && os(iOS)
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [sleepType])
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// The last `days` nights, one per wake day.
    static func nights(days: Int = 30, calendar: Calendar = .current) async -> [SleepNight] {
        #if canImport(HealthKit) && os(iOS)
        guard isAvailable else { return [] }
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        let mapped: [SleepSample] = samples.compactMap { s in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: s.value) else { return nil }
            let stage: SleepSample.Stage
            switch value {
            case .inBed: stage = .inBed
            case .awake: stage = .awake
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            default: stage = .asleep   // asleepUnspecified (iPhone, older Watch)
            }
            return SleepSample(start: s.startDate, end: s.endDate, stage: stage)
        }
        return SleepScore.nights(from: mapped, calendar: calendar)
        #else
        return []
        #endif
    }
}
