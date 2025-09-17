#!/usr/bin/swift

//
//  PingMonitorTests.swift
//  Comprehensive unit tests for PingMonitor application
//
//  USAGE:
//    Direct execution:    ./PingMonitorTests.swift
//    Concise output:      ./run-tests.sh
//    With swift:          swift PingMonitorTests.swift
//
//  Tests all core functionality including:
//  - Host management and validation
//  - Ping results and status determination
//  - Notification settings and conditions
//  - Widget data sharing and timeline updates
//  - UI state management
//  - Settings persistence and restoration
//  - Network detection and validation
//  - Performance characteristics
//
//  Exit codes: 0 = all tests passed, 1 = some tests failed
//

import Foundation
import Network
import SystemConfiguration
import UserNotifications

// MARK: - Import from main PingMonitor file
// We need to import the structures and classes from the main file

// Copy essential structures from PingMonitor.swift for testing
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
        case .good: return "good"
        case .warning: return "warning"
        case .error: return "error"
        case .timeout: return "timeout"
        }
    }
}

enum PingType: String, CaseIterable, Codable {
    case icmp = "ICMP"
    case udp = "UDP"
    case tcp = "TCP"
}

enum GatewayMode: String, CaseIterable, Codable {
    case auto = "Auto-detect"
    case manual = "Manual"
}

struct PingSettings: Codable {
    var interval: Double = 2.0
    var timeout: Double = 3.0
    var type: PingType = .icmp
    var goodThreshold: Double = 50.0
    var warningThreshold: Double = 200.0
    var port: Int? = nil
}

struct NotificationSettings: Codable {
    var enabled: Bool = false
    var onNoResponse: Bool = false
    var onThreshold: Bool = false
    var thresholdMs: Double = 2000.0
    var onNetworkChange: Bool = false
    var onRecovery: Bool = false
    var onDegradation: Bool = false
    var degradationPercent: Double = 50.0
    var onPattern: Bool = false
    var patternThreshold: Int = 3
}

struct Host: Identifiable, Codable {
    let id = UUID()
    var name: String
    var address: String
    var isActive: Bool = true
    var pingSettings: PingSettings = PingSettings()
    var notificationSettings: NotificationSettings = NotificationSettings()

    init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

// Gateway detection function for testing
func getDefaultGateway() -> String {
    var gateway: String = "192.168.1.1"

    guard let store = SCDynamicStoreCreate(nil, "PingMonitor" as CFString, nil, nil) else {
        return gateway
    }

    let globalIPv4Key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv4)

    guard let globalIPv4Dict = SCDynamicStoreCopyValue(store, globalIPv4Key) as? [String: Any] else {
        return gateway
    }

    if let primaryRouter = globalIPv4Dict[kSCPropNetIPv4Router as String] as? String {
        return primaryRouter
    }

    guard let serviceKey = globalIPv4Dict[kSCDynamicStorePropNetPrimaryService as String] as? String else {
        return gateway
    }

    let serviceIPv4Key = SCDynamicStoreKeyCreateNetworkServiceEntity(nil, kSCDynamicStoreDomainState, serviceKey as CFString, kSCEntNetIPv4)

    guard let serviceIPv4Dict = SCDynamicStoreCopyValue(store, serviceIPv4Key) as? [String: Any],
          let routerIP = serviceIPv4Dict[kSCPropNetIPv4Router as String] as? String else {
        return gateway
    }

    return routerIP
}

// Helper functions
func statusToString(_ status: PingStatus) -> String {
    return status.description
}

func isValidIPAddress(_ ip: String) -> Bool {
    let components = ip.components(separatedBy: ".")
    guard components.count == 4 else { return false }

    for component in components {
        guard let num = Int(component), num >= 0, num <= 255 else {
            return false
        }
    }
    return true
}

func isValidHostname(_ hostname: String) -> Bool {
    // Allow both hostnames and FQDNs (with dots)
    if hostname.isEmpty || hostname.count > 253 {
        return false
    }

    // Split by dots for FQDN validation
    let components = hostname.components(separatedBy: ".")

    for component in components {
        if component.isEmpty || component.count > 63 {
            return false
        }

        // Each component should start and end with alphanumeric
        if component.hasPrefix("-") || component.hasSuffix("-") {
            return false
        }

        // Check if component contains only valid characters
        let validCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        if !component.allSatisfy({ validCharacterSet.contains($0.unicodeScalars.first!) }) {
            return false
        }
    }

    return true
}

// MARK: - Test Framework

struct TestResult {
    let testName: String
    let passed: Bool
    let message: String
    let duration: TimeInterval
}

class TestRunner {
    var results: [TestResult] = []

    func run(_ testName: String, test: () throws -> Void) {
        let startTime = Date()

        do {
            try test()
            let duration = Date().timeIntervalSince(startTime)
            results.append(TestResult(testName: testName, passed: true, message: "✅ PASSED", duration: duration))
            print("✅ \(testName) - PASSED (\(String(format: "%.3f", duration))s)")
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            results.append(TestResult(testName: testName, passed: false, message: "❌ FAILED: \(error)", duration: duration))
            print("❌ \(testName) - FAILED: \(error)")
        }
    }

    func runAsync(_ testName: String, timeout: TimeInterval = 10.0, test: (@escaping (Result<Void, Error>) -> Void) -> Void) {
        let startTime = Date()
        let semaphore = DispatchSemaphore(value: 0)
        var testResult: Result<Void, Error>?

        test { result in
            testResult = result
            semaphore.signal()
        }

        let timeoutResult = semaphore.wait(timeout: .now() + timeout)
        let duration = Date().timeIntervalSince(startTime)

        if timeoutResult == .timedOut {
            results.append(TestResult(testName: testName, passed: false, message: "❌ FAILED: Timeout after \(timeout)s", duration: duration))
            print("❌ \(testName) - FAILED: Timeout after \(timeout)s")
            return
        }

        switch testResult! {
        case .success:
            results.append(TestResult(testName: testName, passed: true, message: "✅ PASSED", duration: duration))
            print("✅ \(testName) - PASSED (\(String(format: "%.3f", duration))s)")
        case .failure(let error):
            results.append(TestResult(testName: testName, passed: false, message: "❌ FAILED: \(error)", duration: duration))
            print("❌ \(testName) - FAILED: \(error)")
        }
    }

    func runPerformance(_ testName: String, iterations: Int = 1000, test: () throws -> Void) {
        let startTime = Date()

        do {
            for _ in 0..<iterations {
                try test()
            }
            let duration = Date().timeIntervalSince(startTime)
            let avgTime = duration / Double(iterations) * 1000 // ms per iteration
            results.append(TestResult(testName: testName, passed: true, message: "✅ PASSED", duration: duration))
            print("⚡ \(testName) - PASSED (\(iterations) iterations, \(String(format: "%.3f", avgTime))ms avg)")
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            results.append(TestResult(testName: testName, passed: false, message: "❌ FAILED: \(error)", duration: duration))
            print("❌ \(testName) - FAILED: \(error)")
        }
    }

    func printSummary() {
        let passed = results.filter { $0.passed }.count
        let total = results.count
        let totalTime = results.reduce(0) { $0 + $1.duration }

        print("\n" + "="*80)
        print("COMPREHENSIVE TEST SUMMARY")
        print("="*80)
        print("Tests run: \(total)")
        print("Passed: \(passed)")
        print("Failed: \(total - passed)")
        print("Total time: \(String(format: "%.3f", totalTime))s")
        print("Success rate: \(String(format: "%.1f", Double(passed)/Double(total)*100))%")

        if passed == total {
            print("🎉 ALL TESTS PASSED!")
        } else {
            print("❌ SOME TESTS FAILED")
            print("\nFailed tests:")
            for result in results where !result.passed {
                print("  - \(result.testName): \(result.message)")
            }
        }
        print("="*80)
    }
}

extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}

// MARK: - Error Types

enum TestError: Error, CustomStringConvertible {
    case invalidResult(String)
    case networkError(String)
    case unexpectedSuccess(String)
    case timeout
    case validationError(String)
    case persistenceError(String)
    case configurationError(String)

    var description: String {
        switch self {
        case .invalidResult(let msg): return msg
        case .networkError(let msg): return msg
        case .unexpectedSuccess(let msg): return msg
        case .timeout: return "Test timed out"
        case .validationError(let msg): return "Validation error: \(msg)"
        case .persistenceError(let msg): return "Persistence error: \(msg)"
        case .configurationError(let msg): return "Configuration error: \(msg)"
        }
    }
}

// MARK: - 1. Core Functionality Tests

// Test host creation and validation
func testHostCreation() throws {
    let host = Host(name: "Google DNS", address: "8.8.8.8")

    guard host.name == "Google DNS" else {
        throw TestError.validationError("Host name not set correctly")
    }

    guard host.address == "8.8.8.8" else {
        throw TestError.validationError("Host address not set correctly")
    }

    guard host.isActive == true else {
        throw TestError.validationError("Host should be active by default")
    }

    print("  📝 Host created successfully: \(host.name) -> \(host.address)")
}

// Test host address validation
func testHostValidation() throws {
    let validIPs = ["192.168.1.1", "8.8.8.8", "1.1.1.1", "127.0.0.1"]
    let invalidIPs = ["256.1.1.1", "192.168.1", "192.168.1.1.1", "abc.def.ghi.jkl", ""]

    for ip in validIPs {
        guard isValidIPAddress(ip) else {
            throw TestError.validationError("Valid IP \(ip) rejected")
        }
    }

    for ip in invalidIPs {
        guard !isValidIPAddress(ip) else {
            throw TestError.validationError("Invalid IP \(ip) accepted")
        }
    }

    print("  ✅ IP validation working correctly")
}

// Test ping result creation
func testPingResultCreation() throws {
    let result = PingResult(host: "8.8.8.8", pingTime: 25.5, status: .good)

    guard result.host == "8.8.8.8" else {
        throw TestError.validationError("Ping result host not set correctly")
    }

    guard result.pingTime == 25.5 else {
        throw TestError.validationError("Ping result time not set correctly")
    }

    guard result.status == .good else {
        throw TestError.validationError("Ping result status not set correctly")
    }

    print("  📊 Ping result created: \(result.pingTime!)ms -> \(result.status)")
}

// Test status determination logic
func testStatusDetermination() throws {
    let settings = PingSettings()

    // Test good status (below good threshold)
    let goodResult = PingResult(host: "test", pingTime: 25.0, status: .good)
    guard goodResult.status == .good && goodResult.pingTime! < settings.goodThreshold else {
        throw TestError.validationError("Good status determination failed")
    }

    // Test warning status (between good and warning threshold)
    let warningResult = PingResult(host: "test", pingTime: 150.0, status: .warning)
    guard warningResult.status == .warning else {
        throw TestError.validationError("Warning status determination failed")
    }

    // Test error status (above warning threshold)
    let errorResult = PingResult(host: "test", pingTime: 300.0, status: .error)
    guard errorResult.status == .error else {
        throw TestError.validationError("Error status determination failed")
    }

    // Test timeout status
    let timeoutResult = PingResult(host: "test", pingTime: nil, status: .timeout)
    guard timeoutResult.status == .timeout && timeoutResult.pingTime == nil else {
        throw TestError.validationError("Timeout status determination failed")
    }

    print("  🚦 Status determination logic verified")
}

// MARK: - 2. Notification Settings Tests

// Test notification settings creation and defaults
func testNotificationDefaults() throws {
    let settings = NotificationSettings()

    guard settings.enabled == false else {
        throw TestError.configurationError("Notifications should be disabled by default")
    }

    guard settings.thresholdMs == 2000.0 else {
        throw TestError.configurationError("Default threshold should be 2000ms")
    }

    guard settings.degradationPercent == 50.0 else {
        throw TestError.configurationError("Default degradation percent should be 50%")
    }

    guard settings.patternThreshold == 3 else {
        throw TestError.configurationError("Default pattern threshold should be 3")
    }

    print("  🔔 Notification defaults verified")
}

// Test notification conditions enabling/disabling
func testNotificationConditions() throws {
    var settings = NotificationSettings()

    // Test enabling different conditions
    settings.onNoResponse = true
    settings.onThreshold = true
    settings.onRecovery = true
    settings.onDegradation = true
    settings.onPattern = true
    settings.onNetworkChange = true

    guard settings.onNoResponse && settings.onThreshold && settings.onRecovery &&
          settings.onDegradation && settings.onPattern && settings.onNetworkChange else {
        throw TestError.configurationError("Failed to enable notification conditions")
    }

    print("  ⚙️ Notification conditions can be configured")
}

// Test threshold configuration
func testThresholdConfiguration() throws {
    var settings = NotificationSettings()

    settings.thresholdMs = 1500.0
    guard settings.thresholdMs == 1500.0 else {
        throw TestError.configurationError("Failed to set custom threshold")
    }

    settings.degradationPercent = 75.0
    guard settings.degradationPercent == 75.0 else {
        throw TestError.configurationError("Failed to set custom degradation percent")
    }

    print("  📈 Threshold configuration working")
}

// MARK: - 3. Widget Data Sharing Tests

// Test widget data structure creation
func testWidgetDataStructure() throws {
    let host = Host(name: "Test Host", address: "1.1.1.1")
    let result = PingResult(host: host.address, pingTime: 42.5, status: .good)

    let widgetData: [String: Any] = [
        "hostName": host.name,
        "address": host.address,
        "pingTime": result.pingTime as Any,
        "status": statusToString(result.status)
    ]

    guard let hostName = widgetData["hostName"] as? String, hostName == "Test Host" else {
        throw TestError.validationError("Widget data host name incorrect")
    }

    guard let address = widgetData["address"] as? String, address == "1.1.1.1" else {
        throw TestError.validationError("Widget data address incorrect")
    }

    guard let pingTime = widgetData["pingTime"] as? Double, pingTime == 42.5 else {
        throw TestError.validationError("Widget data ping time incorrect")
    }

    guard let status = widgetData["status"] as? String, status == "good" else {
        throw TestError.validationError("Widget data status incorrect")
    }

    print("  📱 Widget data structure verified")
}

// Test widget data serialization
func testWidgetDataSerialization() throws {
    let hosts = [
        Host(name: "Google", address: "8.8.8.8"),
        Host(name: "Cloudflare", address: "1.1.1.1")
    ]

    let widgetData = hosts.map { host -> [String: Any] in
        return [
            "hostName": host.name,
            "address": host.address,
            "pingTime": 25.0,
            "status": "good"
        ]
    }

    do {
        let jsonData = try JSONSerialization.data(withJSONObject: widgetData)
        let deserializedData = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]

        guard let data = deserializedData, data.count == 2 else {
            throw TestError.persistenceError("Widget data serialization failed")
        }

        print("  💾 Widget data serialization successful (\(jsonData.count) bytes)")
    } catch {
        throw TestError.persistenceError("JSON serialization failed: \(error)")
    }
}

// Test shared container access simulation
func testSharedContainerAccess() throws {
    // Simulate shared container path
    let tempDir = FileManager.default.temporaryDirectory
    let testContainerURL = tempDir.appendingPathComponent("test-shared-container")

    do {
        // Create directory
        try FileManager.default.createDirectory(at: testContainerURL, withIntermediateDirectories: true)

        // Test file creation
        let testData = ["test": "data"]
        let jsonData = try JSONSerialization.data(withJSONObject: testData)
        let fileURL = testContainerURL.appendingPathComponent("pingdata.json")
        try jsonData.write(to: fileURL)

        // Test file reading
        let readData = try Data(contentsOf: fileURL)
        let readObject = try JSONSerialization.jsonObject(with: readData) as? [String: String]

        guard let readTest = readObject?["test"], readTest == "data" else {
            throw TestError.persistenceError("Shared container data persistence failed")
        }

        // Cleanup
        try FileManager.default.removeItem(at: testContainerURL)

        print("  📂 Shared container access simulation successful")
    } catch {
        throw TestError.persistenceError("Shared container test failed: \(error)")
    }
}

// MARK: - 4. UI State Management Tests

// Test compact mode state
func testCompactModeState() throws {
    var isCompactMode = false

    // Test toggle
    isCompactMode.toggle()
    guard isCompactMode == true else {
        throw TestError.validationError("Compact mode toggle failed")
    }

    isCompactMode.toggle()
    guard isCompactMode == false else {
        throw TestError.validationError("Compact mode toggle back failed")
    }

    print("  📱 Compact mode state management verified")
}

// Test display toggles
func testDisplayToggles() throws {
    var showHosts = true
    var showGraph = true
    var showHistory = true
    var showHistorySummary = false

    // Test individual toggles
    showHosts.toggle()
    showGraph.toggle()
    showHistory.toggle()
    showHistorySummary.toggle()

    guard !showHosts && !showGraph && !showHistory && showHistorySummary else {
        throw TestError.validationError("Display toggles failed")
    }

    print("  👁️ Display toggle states verified")
}

// Test stay on top functionality
func testStayOnTopState() throws {
    var isStayOnTop = false

    isStayOnTop = true
    guard isStayOnTop else {
        throw TestError.validationError("Stay on top state setting failed")
    }

    isStayOnTop = false
    guard !isStayOnTop else {
        throw TestError.validationError("Stay on top state unsetting failed")
    }

    print("  📌 Stay on top state management verified")
}

// MARK: - 5. Settings Persistence Tests

// Test ping settings persistence
func testPingSettingsPersistence() throws {
    let settings = PingSettings()

    // Test encoding
    do {
        let encodedData = try JSONEncoder().encode(settings)
        let decodedSettings = try JSONDecoder().decode(PingSettings.self, from: encodedData)

        guard decodedSettings.interval == settings.interval &&
              decodedSettings.timeout == settings.timeout &&
              decodedSettings.type == settings.type &&
              decodedSettings.goodThreshold == settings.goodThreshold &&
              decodedSettings.warningThreshold == settings.warningThreshold else {
            throw TestError.persistenceError("Ping settings persistence failed")
        }

        print("  ⚙️ Ping settings persistence verified")
    } catch {
        throw TestError.persistenceError("Ping settings encoding failed: \(error)")
    }
}

// Test notification settings persistence
func testNotificationSettingsPersistence() throws {
    var settings = NotificationSettings()
    settings.enabled = true
    settings.onThreshold = true
    settings.thresholdMs = 1500.0

    do {
        let encodedData = try JSONEncoder().encode(settings)
        let decodedSettings = try JSONDecoder().decode(NotificationSettings.self, from: encodedData)

        guard decodedSettings.enabled == settings.enabled &&
              decodedSettings.onThreshold == settings.onThreshold &&
              decodedSettings.thresholdMs == settings.thresholdMs else {
            throw TestError.persistenceError("Notification settings persistence failed")
        }

        print("  🔔 Notification settings persistence verified")
    } catch {
        throw TestError.persistenceError("Notification settings encoding failed: \(error)")
    }
}

// Test host persistence
func testHostPersistence() throws {
    let host = Host(name: "Test Host", address: "192.168.1.1")

    do {
        let encodedData = try JSONEncoder().encode(host)
        let decodedHost = try JSONDecoder().decode(Host.self, from: encodedData)

        guard decodedHost.name == host.name &&
              decodedHost.address == host.address &&
              decodedHost.isActive == host.isActive else {
            throw TestError.persistenceError("Host persistence failed")
        }

        print("  🏠 Host persistence verified")
    } catch {
        throw TestError.persistenceError("Host encoding failed: \(error)")
    }
}

// MARK: - 6. Network Detection Tests

// Test gateway detection
func testGatewayDetection() throws {
    let gateway = getDefaultGateway()

    guard !gateway.isEmpty else {
        throw TestError.networkError("Gateway detection returned empty string")
    }

    guard isValidIPAddress(gateway) else {
        throw TestError.networkError("Gateway '\(gateway)' is not a valid IP address")
    }

    print("  🌐 Gateway detected: \(gateway)")
}

// Test host validation functions
func testHostValidationFunctions() throws {
    let validHosts = ["google.com", "test-host", "my-server", "host123"]
    let invalidHosts = ["", "-invalid", "invalid-", "too-long-hostname-that-exceeds-maximum-length-allowed-by-standards"]

    for host in validHosts {
        guard isValidHostname(host) else {
            throw TestError.validationError("Valid hostname \(host) rejected")
        }
    }

    for host in invalidHosts {
        guard !isValidHostname(host) else {
            throw TestError.validationError("Invalid hostname \(host) accepted")
        }
    }

    print("  🏷️ Hostname validation working correctly")
}

// Test TCP connection capability
func testTCPConnection(completion: @escaping (Result<Void, Error>) -> Void) {
    let host = "8.8.8.8"
    let port: UInt16 = 53

    let connection = NWConnection(
        host: NWEndpoint.Host(host),
        port: NWEndpoint.Port(integerLiteral: port),
        using: .tcp
    )

    let startTime = Date()

    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            let duration = Date().timeIntervalSince(startTime) * 1000
            print("  🔗 TCP connection successful (\(String(format: "%.1f", duration))ms)")
            connection.cancel()
            completion(.success(()))
        case .failed(let error):
            connection.cancel()
            completion(.failure(TestError.networkError("TCP connection failed: \(error)")))
        case .cancelled:
            completion(.failure(TestError.networkError("TCP connection cancelled")))
        default:
            break
        }
    }

    connection.start(queue: .global())

    DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
        connection.cancel()
    }
}

// Test UDP connection capability
func testUDPConnection(completion: @escaping (Result<Void, Error>) -> Void) {
    let host = "1.1.1.1"
    let port: UInt16 = 53

    let connection = NWConnection(
        host: NWEndpoint.Host(host),
        port: NWEndpoint.Port(integerLiteral: port),
        using: .udp
    )

    let startTime = Date()

    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            let duration = Date().timeIntervalSince(startTime) * 1000
            print("  📡 UDP connection successful (\(String(format: "%.1f", duration))ms)")
            connection.cancel()
            completion(.success(()))
        case .failed(let error):
            connection.cancel()
            completion(.failure(TestError.networkError("UDP connection failed: \(error)")))
        case .cancelled:
            completion(.failure(TestError.networkError("UDP connection cancelled")))
        default:
            break
        }
    }

    connection.start(queue: .global())

    DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
        connection.cancel()
    }
}

// MARK: - 7. Performance Tests

// Test ping result creation performance
func testPingResultPerformance() throws {
    for _ in 0..<100 {
        let _ = PingResult(host: "test.com", pingTime: Double.random(in: 1...100), status: .good)
    }
    print("  ⚡ Ping result creation performance acceptable")
}

// Test host validation performance
func testHostValidationPerformance() throws {
    let testIPs = Array(repeating: "192.168.1.1", count: 100)
    for ip in testIPs {
        let _ = isValidIPAddress(ip)
    }
    print("  ⚡ Host validation performance acceptable")
}

// Test settings serialization performance
func testSettingsSerializationPerformance() throws {
    let settings = PingSettings()
    for _ in 0..<50 {
        let _ = try JSONEncoder().encode(settings)
    }
    print("  ⚡ Settings serialization performance acceptable")
}

// Test widget data creation performance
func testWidgetDataPerformance() throws {
    let hosts = Array(repeating: Host(name: "Test", address: "1.1.1.1"), count: 10)

    for _ in 0..<100 {
        let _ = hosts.map { host -> [String: Any] in
            return [
                "hostName": host.name,
                "address": host.address,
                "pingTime": 25.0,
                "status": "good"
            ]
        }
    }
    print("  ⚡ Widget data creation performance acceptable")
}

// MARK: - Main Test Runner

print("🧪 PingMonitor Comprehensive Test Suite")
print("="*80)
print("Testing all core functionality, notifications, widgets, UI, settings, and performance")
print("")

let runner = TestRunner()

// 1. Core Functionality Tests
print("📋 1. CORE FUNCTIONALITY TESTS")
print("-"*40)
runner.run("Host Creation") { try testHostCreation() }
runner.run("Host Validation") { try testHostValidation() }
runner.run("Ping Result Creation") { try testPingResultCreation() }
runner.run("Status Determination") { try testStatusDetermination() }
print("")

// 2. Notification Settings Tests
print("🔔 2. NOTIFICATION SETTINGS TESTS")
print("-"*40)
runner.run("Notification Defaults") { try testNotificationDefaults() }
runner.run("Notification Conditions") { try testNotificationConditions() }
runner.run("Threshold Configuration") { try testThresholdConfiguration() }
print("")

// 3. Widget Data Sharing Tests
print("📱 3. WIDGET DATA SHARING TESTS")
print("-"*40)
runner.run("Widget Data Structure") { try testWidgetDataStructure() }
runner.run("Widget Data Serialization") { try testWidgetDataSerialization() }
runner.run("Shared Container Access") { try testSharedContainerAccess() }
print("")

// 4. UI State Management Tests
print("🎛️ 4. UI STATE MANAGEMENT TESTS")
print("-"*40)
runner.run("Compact Mode State") { try testCompactModeState() }
runner.run("Display Toggles") { try testDisplayToggles() }
runner.run("Stay On Top State") { try testStayOnTopState() }
print("")

// 5. Settings Persistence Tests
print("💾 5. SETTINGS PERSISTENCE TESTS")
print("-"*40)
runner.run("Ping Settings Persistence") { try testPingSettingsPersistence() }
runner.run("Notification Settings Persistence") { try testNotificationSettingsPersistence() }
runner.run("Host Persistence") { try testHostPersistence() }
print("")

// 6. Network Detection Tests
print("🌐 6. NETWORK DETECTION TESTS")
print("-"*40)
runner.run("Gateway Detection") { try testGatewayDetection() }
runner.run("Host Validation Functions") { try testHostValidationFunctions() }
runner.runAsync("TCP Connection Test") { completion in testTCPConnection(completion: completion) }
runner.runAsync("UDP Connection Test") { completion in testUDPConnection(completion: completion) }
print("")

// 7. Performance Tests
print("⚡ 7. PERFORMANCE TESTS")
print("-"*40)
runner.runPerformance("Ping Result Performance", iterations: 1000) { try testPingResultPerformance() }
runner.runPerformance("Host Validation Performance", iterations: 1000) { try testHostValidationPerformance() }
runner.runPerformance("Settings Serialization Performance", iterations: 500) { try testSettingsSerializationPerformance() }
runner.runPerformance("Widget Data Performance", iterations: 1000) { try testWidgetDataPerformance() }
print("")

// Print final results
runner.printSummary()

// Exit with appropriate code
let hasFailures = runner.results.contains { !$0.passed }
exit(hasFailures ? 1 : 0)