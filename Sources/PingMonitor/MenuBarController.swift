import SwiftUI
import AppKit
import Combine

class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var pingService: PingService
    private var cancellables = Set<AnyCancellable>()

    @Published var currentStatus: PingStatus = .good
    @Published var currentPingTime: Double? = nil
    @Published var hosts: [Host] = Host.defaultHosts
    @Published var selectedHost: Host?
    @Published var pingHistory: [PingResult] = []

    init() {
        self.pingService = PingService()
        setupMenuBar()
        setupBindings()
        startMonitoring()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateStatusItemDisplay()
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.contentSize = NSSize(width: 500, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView().environmentObject(self))
    }

    private func setupBindings() {
        pingService.$latestResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self = self, let result = result else { return }
                self.currentPingTime = result.pingTime
                self.currentStatus = result.status
                self.pingHistory.insert(result, at: 0)
                if self.pingHistory.count > 100 {
                    self.pingHistory.removeLast()
                }
                self.updateStatusItemDisplay()
            }
            .store(in: &cancellables)
    }

    private func updateStatusItemDisplay() {
        guard let button = statusItem?.button else { return }

        DispatchQueue.main.async {
            let statusDot = self.getStatusDot()
            let pingText = self.currentPingTime != nil ? String(format: " %.0fms", self.currentPingTime!) : " --"

            let attributedString = NSMutableAttributedString()

            let dotAttachment = NSTextAttachment()
            dotAttachment.image = self.createDotImage(color: self.getStatusColor())
            dotAttachment.bounds = CGRect(x: 0, y: -2, width: 10, height: 10)
            attributedString.append(NSAttributedString(attachment: dotAttachment))

            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
            attributedString.append(NSAttributedString(string: pingText, attributes: textAttributes))

            button.attributedTitle = attributedString
        }
    }

    private func createDotImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()

        color.setFill()
        let path = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 8, height: 8))
        path.fill()

        image.unlockFocus()
        return image
    }

    private func getStatusColor() -> NSColor {
        switch currentStatus {
        case .good: return .systemGreen
        case .warning: return .systemYellow
        case .error: return .systemRed
        case .timeout: return .systemGray
        }
    }

    private func getStatusDot() -> String {
        switch currentStatus {
        case .good: return "🟢"
        case .warning: return "🟡"
        case .error: return "🔴"
        case .timeout: return "⚫"
        }
    }

    func startMonitoring() {
        if let firstHost = hosts.first(where: { $0.enabled }) {
            selectedHost = firstHost
            pingService.startPinging(host: firstHost)
        }
    }

    func selectHost(_ host: Host) {
        selectedHost = host
        if host.enabled {
            pingService.startPinging(host: host)
        }
    }

    func addHost(_ host: Host) {
        hosts.append(host)
        DataManager.shared.saveHosts(hosts)
    }

    func removeHost(_ host: Host) {
        hosts.removeAll { $0.id == host.id }
        DataManager.shared.saveHosts(hosts)

        if selectedHost?.id == host.id {
            startMonitoring()
        }
    }

    func updateHost(_ host: Host) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
            DataManager.shared.saveHosts(hosts)

            if selectedHost?.id == host.id {
                selectHost(host)
            }
        }
    }

    @objc private func togglePopover() {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    func exportHistory() {
        DataManager.shared.exportPingHistory(pingHistory)
    }

    func clearHistory() {
        pingHistory.removeAll()
    }
}