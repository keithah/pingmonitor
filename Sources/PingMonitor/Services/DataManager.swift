import Foundation
import AppKit
import UserNotifications

class DataManager {
    static let shared = DataManager()
    private let hostsKey = "SavedHosts"
    private let historyKey = "PingHistory"

    private init() {
        requestNotificationPermissions()
    }

    func saveHosts(_ hosts: [Host]) {
        if let encoded = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(encoded, forKey: hostsKey)
        }
    }

    func loadHosts() -> [Host] {
        guard let data = UserDefaults.standard.data(forKey: hostsKey),
              let hosts = try? JSONDecoder().decode([Host].self, from: data) else {
            return Host.defaultHosts
        }
        return hosts
    }

    func savePingHistory(_ history: [PingResult]) {
        let limitedHistory = Array(history.prefix(500))
        if let encoded = try? JSONEncoder().encode(limitedHistory) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }

    func loadPingHistory() -> [PingResult] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([PingResult].self, from: data) else {
            return []
        }
        return history
    }

    func exportPingHistory(_ history: [PingResult]) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "ping-history-\(Date().timeIntervalSince1970).csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            let csvContent = self.generateCSV(from: history)
            do {
                try csvContent.write(to: url, atomically: true, encoding: .utf8)
                self.showNotification(title: "Export Successful",
                                     message: "Ping history exported to \(url.lastPathComponent)")
            } catch {
                self.showNotification(title: "Export Failed",
                                     message: "Could not export ping history: \(error.localizedDescription)")
            }
        }
    }

    private func generateCSV(from history: [PingResult]) -> String {
        var csv = "Timestamp,Host,Ping (ms),Status,Packet Loss (%)\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for result in history {
            let timestamp = dateFormatter.string(from: result.timestamp)
            let pingTime = result.pingTime != nil ? String(format: "%.2f", result.pingTime!) : "N/A"
            let packetLoss = String(format: "%.1f", result.packetLoss * 100)

            csv += "\(timestamp),\(result.host),\(pingTime),\(result.status.rawValue),\(packetLoss)\n"
        }

        return csv
    }

    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permissions granted")
            } else if let error = error {
                print("Notification permissions error: \(error)")
            }
        }
    }

    func showNotification(title: String, message: String, isError: Bool = false) {
        guard UserDefaults.standard.bool(forKey: "enableNotifications") else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message

        if UserDefaults.standard.bool(forKey: "enableSounds") {
            content.sound = isError ? .defaultCritical : .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }

    func notifyHostStatusChange(host: String, oldStatus: PingStatus, newStatus: PingStatus) {
        if oldStatus == .good && newStatus != .good {
            showNotification(
                title: "Host Down",
                message: "\(host) is experiencing connectivity issues",
                isError: true
            )
        } else if oldStatus != .good && newStatus == .good {
            showNotification(
                title: "Host Recovered",
                message: "\(host) is back online",
                isError: false
            )
        }
    }
}