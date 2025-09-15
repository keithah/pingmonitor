import Foundation
import Combine
import Network

class PingService: ObservableObject {
    @Published var latestResult: PingResult?
    @Published var isRunning = false

    private var timer: Timer?
    private var currentHost: Host?
    private var pingInterval: TimeInterval = 2.0
    private var timeout: TimeInterval = 5.0
    private let queue = DispatchQueue(label: "com.pingmonitor.ping", qos: .background)

    func startPinging(host: Host, interval: TimeInterval = 2.0) {
        stopPinging()

        currentHost = host
        pingInterval = interval
        isRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { _ in
            self.performPing(host: host)
        }

        performPing(host: host)
    }

    func stopPinging() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        currentHost = nil
    }

    private func performPing(host: Host) {
        queue.async { [weak self] in
            guard let self = self else { return }

            switch host.pingMethod {
            case .icmp:
                self.performICMPPing(host: host)
            case .httpHead:
                self.performHTTPPing(host: host)
            }
        }
    }

    private func performICMPPing(host: Host) {
        let startTime = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-t", "5", host.address]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                let pingTime = extractPingTime(from: output) ?? Date().timeIntervalSince(startTime) * 1000
                let packetLoss = extractPacketLoss(from: output)

                let thresholds = host.customThresholds ?? PingThresholds()
                let status = PingResult.determineStatus(from: pingTime, thresholds: thresholds)

                DispatchQueue.main.async {
                    self.latestResult = PingResult(
                        host: host.address,
                        pingTime: pingTime,
                        status: status,
                        packetLoss: packetLoss
                    )
                }
            } else {
                DispatchQueue.main.async {
                    self.latestResult = PingResult(
                        host: host.address,
                        pingTime: nil,
                        status: .timeout,
                        packetLoss: 1.0
                    )
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.latestResult = PingResult(
                    host: host.address,
                    pingTime: nil,
                    status: .error,
                    packetLoss: 1.0
                )
            }
        }
    }

    private func performHTTPPing(host: Host) {
        let startTime = Date()
        var urlString = host.address

        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://\(urlString)"
        }

        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.latestResult = PingResult(
                    host: host.address,
                    pingTime: nil,
                    status: .error,
                    packetLoss: 1.0
                )
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }

            let pingTime = Date().timeIntervalSince(startTime) * 1000

            if error == nil, let httpResponse = response as? HTTPURLResponse,
               (200...399).contains(httpResponse.statusCode) {
                let thresholds = host.customThresholds ?? PingThresholds()
                let status = PingResult.determineStatus(from: pingTime, thresholds: thresholds)

                DispatchQueue.main.async {
                    self.latestResult = PingResult(
                        host: host.address,
                        pingTime: pingTime,
                        status: status,
                        packetLoss: 0.0
                    )
                }
            } else {
                DispatchQueue.main.async {
                    self.latestResult = PingResult(
                        host: host.address,
                        pingTime: nil,
                        status: .timeout,
                        packetLoss: 1.0
                    )
                }
            }
        }.resume()
    }

    private func extractPingTime(from output: String) -> Double? {
        let pattern = "time=([0-9.]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let timeRange = Range(match.range(at: 1), in: output) else {
            return nil
        }

        return Double(output[timeRange])
    }

    private func extractPacketLoss(from output: String) -> Double {
        let pattern = "([0-9.]+)% packet loss"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let lossRange = Range(match.range(at: 1), in: output) else {
            return 0.0
        }

        return (Double(output[lossRange]) ?? 0.0) / 100.0
    }

    func updateSettings(interval: TimeInterval, timeout: TimeInterval) {
        self.pingInterval = interval
        self.timeout = timeout

        if let host = currentHost, isRunning {
            startPinging(host: host, interval: interval)
        }
    }
}