#!/usr/bin/swift

import Foundation

// Test script to verify widget data sharing functionality

print("🔗 Testing Widget Data Sharing")
print("=============================")

// Test creating shared container and writing data
guard let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.pingmonitor.shared") else {
    print("❌ Failed to get shared container URL")
    exit(1)
}

print("📂 Shared container URL: \(sharedURL.path)")

// Create test ping data
let testWidgetData = [
    [
        "hostName": "Google",
        "address": "8.8.8.8",
        "pingTime": 12.3,
        "status": "good"
    ],
    [
        "hostName": "Cloudflare",
        "address": "1.1.1.1",
        "pingTime": 8.7,
        "status": "good"
    ],
    [
        "hostName": "Gateway",
        "address": "192.168.1.1",
        "pingTime": 2.1,
        "status": "good"
    ]
]

do {
    // Create directory if needed
    try FileManager.default.createDirectory(at: sharedURL, withIntermediateDirectories: true)
    print("✅ Created shared directory")

    // Write test data
    let data = try JSONSerialization.data(withJSONObject: testWidgetData, options: .prettyPrinted)
    let dataURL = sharedURL.appendingPathComponent("pingdata.json")
    try data.write(to: dataURL)
    print("✅ Wrote test data to: \(dataURL.path)")

    // Verify we can read it back
    let readData = try Data(contentsOf: dataURL)
    guard let jsonArray = try JSONSerialization.jsonObject(with: readData) as? [[String: Any]] else {
        print("❌ Failed to parse JSON data")
        exit(1)
    }

    print("✅ Successfully read back \(jsonArray.count) host entries")

    for (index, hostData) in jsonArray.enumerated() {
        let hostName = hostData["hostName"] as? String ?? "Unknown"
        let address = hostData["address"] as? String ?? "Unknown"
        let pingTime = hostData["pingTime"] as? Double ?? 0.0
        let status = hostData["status"] as? String ?? "timeout"

        print("  \(index + 1). \(hostName) (\(address)) - \(String(format: "%.1f", pingTime))ms - \(status)")
    }

    print("")
    print("🎉 Widget data sharing test PASSED!")
    print("   The main app can successfully share data with widgets")

} catch {
    print("❌ Error: \(error)")
    exit(1)
}