import DonkeyContracts
import Foundation

public actor InMemoryReflexTraceStore {
    private let maxRecords: Int
    private var records: [ReflexTraceRecord] = []

    public init(maxRecords: Int = 300) {
        self.maxRecords = max(1, maxRecords)
    }

    @discardableResult
    public func append(_ record: ReflexTraceRecord) -> ReflexTraceRecord {
        records.append(record)

        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }

        return record
    }

    public func allRecords() -> [ReflexTraceRecord] {
        records
    }

    public func latestRecord() -> ReflexTraceRecord? {
        records.last
    }

    public func count() -> Int {
        records.count
    }
}
