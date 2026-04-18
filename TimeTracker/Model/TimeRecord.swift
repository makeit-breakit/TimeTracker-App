import Foundation

struct DomainSession: Codable {
    var totalSeconds: Int
}

struct DayRecord: Codable {
    var date: String
    var domains: [String: DomainSession]

    init(date: String) {
        self.date = date
        self.domains = [:]
    }
}
