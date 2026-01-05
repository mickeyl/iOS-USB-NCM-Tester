import SwiftUI

struct InterfaceListView: View {
    let interfaces: [NetworkInterface]
    let lastScanTime: Date?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView

            if interfaces.isEmpty {
                emptyStateView
            } else {
                interfaceList
            }
        }
    }

    private var headerView: some View {
        HStack {
            Label("Network Interfaces", systemImage: "network")
                .font(.headline)

            Spacer()

            if let scanTime = lastScanTime {
                Text(dateFormatter.string(from: scanTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Interfaces Found",
            systemImage: "network.slash",
            description: Text("Scanning for network interfaces…")
        )
    }

    private var interfaceList: some View {
        ForEach(interfaces) { interface in
            InterfaceRow(interface: interface)
        }
    }
}

struct InterfaceRow: View {
    let interface: NetworkInterface

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 30, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(interface.displayName)
                    .font(.subheadline)
                    .fontWeight(interface.isEthernet ? .semibold : .regular)

                Text(interface.ipAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }

            Spacer()

            if interface.isEthernet {
                Text("USB")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }

            Circle()
                .fill(interface.isUp ? .green : .red)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch interface.type {
            case .loopback:
                return "arrow.triangle.2.circlepath"
            case .ethernet:
                return "cable.connector"
            case .ipsec:
                return "lock.fill"
            case .wifi:
                return "wifi"
            case .cellular:
                return "antenna.radiowaves.left.and.right"
            case .other:
                return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch interface.type {
            case .loopback:
                return .gray
            case .ethernet:
                return .green
            case .ipsec:
                return .purple
            case .wifi:
                return .blue
            case .cellular:
                return .orange
            case .other:
                return .secondary
        }
    }
}

#Preview {
    InterfaceListView(
        interfaces: [
            NetworkInterface(
                id: "lo0-127.0.0.1",
                name: "lo0",
                ipAddress: "127.0.0.1",
                netmask: "255.0.0.0",
                isUp: true,
                isLoopback: true,
                isEthernet: false
            ),
            NetworkInterface(
                id: "en0-192.168.1.100",
                name: "en0",
                ipAddress: "192.168.1.100",
                netmask: "255.255.255.0",
                isUp: true,
                isLoopback: false,
                isEthernet: false
            ),
            NetworkInterface(
                id: "en2-10.0.0.5",
                name: "en2",
                ipAddress: "10.0.0.5",
                netmask: "255.255.255.0",
                isUp: true,
                isLoopback: false,
                isEthernet: true
            )
        ],
        lastScanTime: Date()
    )
    .padding()
}
