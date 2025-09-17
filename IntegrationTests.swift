#!/usr/bin/swift

//
//  IntegrationTests.swift
//  Integration tests that simulate real PingMonitor app usage
//
//  Tests the complete ping workflow including different ping types,
//  timeout handling, and statistics calculation - all using the
//  sandbox-compatible Network.framework implementations.
//

import Foundation
import Network
import SystemConfiguration

// MARK: - Mock Data Models (copied from main app)

struct PingResult: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let host: String
    let pingTime: Double?
    let status: PingStatus
}

enum PingStatus {
    case good, warning, error, timeout

    var description: String {
        switch self {
        case .good: return "Good"
        case .warning: return "Warning"
        case .error: return "Error"
        case .timeout: return "Timeout"
        }
    }
}

enum PingType: String, CaseIterable {
    case icmp = "ICMP"
    case udp = "UDP"
    case tcp = "TCP"
}

struct PingSettings {
    let interval: TimeInterval
    let timeout: TimeInterval
    let type: PingType
    let goodThreshold: Double
    let warningThreshold: Double
    let port: Int?
}

struct Host {
    let address: String
    let name: String
    let pingSettings: PingSettings
}

// MARK: - Ping Implementation (copied from main app)

class PingMonitor {
    private var pingHistory: [PingResult] = []

    func performPing(host: Host) -> PingResult {
        switch host.pingSettings.type {
        case .icmp:
            return performICMPPing(host: host)
        case .udp:
            return performUDPPing(host: host)
        case .tcp:
            return performTCPPing(host: host)
        }
    }

    private func performICMPPing(host: Host) -> PingResult {
        let startTime = Date()
        var result: PingResult?
        let semaphore = DispatchSemaphore(value: 0)

        // For sandbox compatibility, we'll use TCP connection to port 80 as an ICMP alternative
        let port: UInt16 = 80
        let connection = NWConnection(
            host: NWEndpoint.Host(host.address),
            port: NWEndpoint.Port(integerLiteral: port),
            using: .tcp
        )

        connection.start(queue: .global())

        // Set timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + host.pingSettings.timeout) {
            connection.cancel()
            if result == nil {
                result = PingResult(host: host.address, pingTime: nil, status: .timeout)
                semaphore.signal()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let pingTime = Date().timeIntervalSince(startTime) * 1000 // Convert to ms
                let status = self.determineStatus(pingTime: pingTime, settings: host.pingSettings)
                result = PingResult(host: host.address, pingTime: pingTime, status: status)
                connection.cancel()
                semaphore.signal()
            case .failed(_), .cancelled:
                if result == nil {
                    result = PingResult(host: host.address, pingTime: nil, status: .timeout)
                    semaphore.signal()
                }
            default:
                break
            }
        }

        semaphore.wait()
        return result ?? PingResult(host: host.address, pingTime: nil, status: .timeout)
    }

    private func performUDPPing(host: Host) -> PingResult {
        let port = host.pingSettings.port ?? 53 // Default to DNS port
        let startTime = Date()
        var result: PingResult?
        let semaphore = DispatchSemaphore(value: 0)

        let connection = NWConnection(
            host: NWEndpoint.Host(host.address),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .udp
        )

        connection.start(queue: .global())

        // Set timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + host.pingSettings.timeout) {
            connection.cancel()
            if result == nil {
                result = PingResult(host: host.address, pingTime: nil, status: .timeout)
                semaphore.signal()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let pingTime = Date().timeIntervalSince(startTime) * 1000 // Convert to ms
                let status = self.determineStatus(pingTime: pingTime, settings: host.pingSettings)
                result = PingResult(host: host.address, pingTime: pingTime, status: status)
                connection.cancel()
                semaphore.signal()
            case .failed(_), .cancelled:
                if result == nil {
                    result = PingResult(host: host.address, pingTime: nil, status: .timeout)
                    semaphore.signal()
                }
            default:
                break
            }
        }

        semaphore.wait()
        return result ?? PingResult(host: host.address, pingTime: nil, status: .timeout)
    }

    private func performTCPPing(host: Host) -> PingResult {
        let port = host.pingSettings.port ?? 80 // Default to HTTP port
        let startTime = Date()
        var result: PingResult?
        let semaphore = DispatchSemaphore(value: 0)

        let connection = NWConnection(
            host: NWEndpoint.Host(host.address),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )

        connection.start(queue: .global())

        // Set timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + host.pingSettings.timeout) {
            connection.cancel()
            if result == nil {
                result = PingResult(host: host.address, pingTime: nil, status: .timeout)
                semaphore.signal()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let pingTime = Date().timeIntervalSince(startTime) * 1000 // Convert to ms
                let status = self.determineStatus(pingTime: pingTime, settings: host.pingSettings)
                result = PingResult(host: host.address, pingTime: pingTime, status: status)
                connection.cancel()
                semaphore.signal()
            case .failed(_), .cancelled:
                if result == nil {
                    result = PingResult(host: host.address, pingTime: nil, status: .timeout)
                    semaphore.signal()
                }
            default:
                break
            }
        }

        semaphore.wait()
        return result ?? PingResult(host: host.address, pingTime: nil, status: .timeout)
    }

    private func determineStatus(pingTime: Double, settings: PingSettings) -> PingStatus {
        if pingTime <= settings.goodThreshold {
            return .good
        } else if pingTime <= settings.warningThreshold {
            return .warning
        } else {
            return .error
        }
    }

    func addResult(_ result: PingResult) {
        pingHistory.append(result)
    }

    func calculateStats() -> (min: Double, avg: Double, max: Double, count: Int) {
        let validResults = pingHistory.compactMap { $0.pingTime }
        guard !validResults.isEmpty else {
            return (0, 0, 0, 0)
        }

        let min = validResults.min() ?? 0
        let max = validResults.max() ?? 0
        let avg = validResults.reduce(0, +) / Double(validResults.count)

        return (min, avg, max, validResults.count)
    }
}

// MARK: - Integration Tests

print("🔄 PingMonitor Integration Tests")
print("===============================")
print("")

let monitor = PingMonitor()

// Test hosts configuration
let defaultSettings = PingSettings(
    interval: 2.0,
    timeout: 3.0,
    type: .icmp,
    goodThreshold: 50.0,
    warningThreshold: 150.0,
    port: nil
)

let testHosts = [
    Host(address: "8.8.8.8", name: "Google DNS", pingSettings: defaultSettings),
    Host(address: "1.1.1.1", name: "Cloudflare DNS", pingSettings: PingSettings(
        interval: 2.0,
        timeout: 3.0,
        type: .udp,
        goodThreshold: 50.0,
        warningThreshold: 150.0,
        port: 53
    )),
    Host(address: "httpbin.org", name: "HTTP Test", pingSettings: PingSettings(
        interval: 2.0,
        timeout: 3.0,
        type: .tcp,
        goodThreshold: 50.0,
        warningThreshold: 150.0,
        port: 80
    ))
]

print("📡 Testing all ping types with real hosts...")
print("")

var successCount = 0
var totalTests = 0

for host in testHosts {
    totalTests += 1
    print("Testing \(host.name) (\(host.address)) with \(host.pingSettings.type.rawValue)...")

    let result = monitor.performPing(host: host)
    monitor.addResult(result)

    if let pingTime = result.pingTime {
        print("  ✅ Success: \(String(format: "%.1f", pingTime))ms - \(result.status.description)")
        successCount += 1
    } else {
        print("  ❌ Failed: \(result.status.description)")
    }

    // Small delay between tests
    Thread.sleep(forTimeInterval: 0.5)
}

print("")
print("📊 Calculating statistics...")
let stats = monitor.calculateStats()
print("  Min: \(String(format: "%.1f", stats.min))ms")
print("  Avg: \(String(format: "%.1f", stats.avg))ms")
print("  Max: \(String(format: "%.1f", stats.max))ms")
print("  Count: \(stats.count) successful pings")

print("")
print("🧪 Testing error conditions...")

// Test timeout with unreachable host
let timeoutHost = Host(
    address: "192.0.2.1", // RFC 5737 test address
    name: "Timeout Test",
    pingSettings: PingSettings(
        interval: 2.0,
        timeout: 1.0, // Short timeout
        type: .tcp,
        goodThreshold: 50.0,
        warningThreshold: 150.0,
        port: 12345
    )
)

print("Testing timeout behavior...")
let timeoutResult = monitor.performPing(host: timeoutHost)
if timeoutResult.status == .timeout {
    print("  ✅ Timeout handling works correctly")
    successCount += 1
} else {
    print("  ❌ Timeout not detected properly")
}
totalTests += 1

// Test invalid host
let invalidHost = Host(
    address: "invalid.nonexistent.domain.test",
    name: "Invalid Host",
    pingSettings: defaultSettings
)

print("Testing invalid host handling...")
let invalidResult = monitor.performPing(host: invalidHost)
if invalidResult.status == .timeout || invalidResult.status == .error {
    print("  ✅ Invalid host handling works correctly")
    successCount += 1
} else {
    print("  ❌ Invalid host not handled properly")
}
totalTests += 1

print("")
print("="*50)
print("INTEGRATION TEST SUMMARY")
print("="*50)
print("Tests completed: \(totalTests)")
print("Successful: \(successCount)")
print("Failed: \(totalTests - successCount)")
print("Success rate: \(String(format: "%.1f", Double(successCount)/Double(totalTests)*100))%")

if successCount == totalTests {
    print("🎉 ALL INTEGRATION TESTS PASSED!")
    print("✅ PingMonitor is ready for App Store sandbox!")
} else {
    print("❌ Some tests failed - review before App Store submission")
}

print("="*50)

extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}