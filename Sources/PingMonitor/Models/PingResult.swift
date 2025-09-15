import Foundation

enum PingStatus: String, Codable {
    case good
    case warning
    case error
    case timeout

    var color: String {
        switch self {
        case .good: return "green"
        case .warning: return "yellow"
        case .error: return "red"
        case .timeout: return "gray"
        }
    }
}

struct PingResult: Identifiable, Codable {
    let id = UUID()
    let timestamp: Date
    let host: String
    let pingTime: Double?
    let status: PingStatus
    let packetLoss: Double

    init(timestamp: Date = Date(), host: String, pingTime: Double?, status: PingStatus, packetLoss: Double = 0.0) {
        self.timestamp = timestamp
        self.host = host
        self.pingTime = pingTime
        self.status = status
        self.packetLoss = packetLoss
    }

    static func determineStatus(from pingTime: Double?, thresholds: PingThresholds = PingThresholds()) -> PingStatus {
        guard let pingTime = pingTime else { return .timeout }

        if pingTime < thresholds.good {
            return .good
        } else if pingTime < thresholds.warning {
            return .warning
        } else {
            return .error
        }
    }
}

struct PingThresholds: Codable {
    var good: Double = 50.0
    var warning: Double = 150.0
    var error: Double = 500.0
}