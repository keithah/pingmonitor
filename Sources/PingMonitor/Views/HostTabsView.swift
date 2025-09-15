import SwiftUI

struct HostTabsView: View {
    let hosts: [Host]
    @Binding var selectedHost: Host?
    let onSelectHost: (Host) -> Void
    let onAddHost: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(hosts.filter { $0.enabled }) { host in
                    HostTab(
                        host: host,
                        isSelected: selectedHost?.id == host.id,
                        onSelect: {
                            onSelectHost(host)
                        }
                    )
                }

                Button(action: onAddHost) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 8)
            }
        }
    }
}

struct HostTab: View {
    let host: Host
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(host.name)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color(NSColor.controlColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var statusColor: Color {
        Color.green
    }
}