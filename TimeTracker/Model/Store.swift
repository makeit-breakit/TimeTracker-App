import Foundation
import OSLog

private let logger = Logger(subsystem: "com.timetracker.app", category: "Store")

final class Store {
    private(set) var record: DayRecord

    init() {
        record = DayRecord(date: Store.logicalDateString())
    }

    // MARK: - Public API

    func credit(domain: String, seconds: Int) {
        record.domains[domain, default: DomainSession(totalSeconds: 0)].totalSeconds += seconds
    }

    func resetToday() {
        record = DayRecord(date: Store.logicalDateString())
        flush()
    }

    // MARK: - Persistence

    func load() {
        let today = Store.logicalDateString()
        guard let url = fileURL(for: today) else {
            record = DayRecord(date: today)
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            record = DayRecord(date: today)
            return
        }
        do {
            record = try JSONDecoder().decode(DayRecord.self, from: data)
        } catch {
            logger.error("Failed to decode day record, starting fresh: \(error)")
            record = DayRecord(date: today)
        }
    }

    func flush() {
        let today = Store.logicalDateString()
        if record.date != today {
            save(record)
            record = DayRecord(date: today)
        }
        save(record)
    }

    // MARK: - Private

    private func save(_ r: DayRecord) {
        guard let url = fileURL(for: r.date) else { return }
        do {
            let data = try JSONEncoder().encode(r)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save day record to \(url.path): \(error)")
        }
    }

    private func fileURL(for date: String) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("TimeTracker", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create support directory: \(error)")
                return nil
            }
        }
        return dir.appendingPathComponent("\(date).json")
    }

    // MARK: - Logical Date (3 AM daily reset)

    static func logicalDateString() -> String {
        // Treat 00:00–02:59 as still part of the previous calendar day.
        let adjusted = Date().addingTimeInterval(-3 * 3600)
        return dateFormatter.string(from: adjusted)
    }

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()
}
