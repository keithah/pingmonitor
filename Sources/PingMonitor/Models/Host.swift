import Foundation

enum PingMethod: String, Codable {
    case icmp = "ICMP"
    case httpHead = "HTTP HEAD"
}

struct Host: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var address: String
    var enabled: Bool
    var pingMethod: PingMethod
    var customThresholds: PingThresholds?

    init(id: UUID = UUID(), name: String, address: String, enabled: Bool = true, pingMethod: PingMethod = .icmp, customThresholds: PingThresholds? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.enabled = enabled
        self.pingMethod = pingMethod
        self.customThresholds = customThresholds
    }

    static let defaultHosts: [Host] = [
        Host(name: "Google DNS", address: "8.8.8.8"),
        Host(name: "Cloudflare", address: "1.1.1.1"),
        Host(name: "Router", address: "192.168.1.1")
    ]
}