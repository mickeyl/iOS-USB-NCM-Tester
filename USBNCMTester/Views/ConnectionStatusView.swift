import SwiftUI

struct ConnectionStatusView: View {
    @ObservedObject var connectionManager: ConnectionManager
    let ethernetInterface: NetworkInterface?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader
            statsView
            connectionControls
            logSection
        }
    }

    private var statusHeader: some View {
        HStack {
            Label("Connection Status", systemImage: "link")
                .font(.headline)

            Spacer()

            statusBadge
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(connectionManager.state.description)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch connectionManager.state {
            case .disconnected:
                return .gray
            case .connecting:
                return .orange
            case .connected:
                return .green
            case .failed:
                return .red
        }
    }

    private var statsView: some View {
        HStack(spacing: 20) {
            StatItem(
                title: "Requests",
                value: "\(connectionManager.requestCount)"
            )

            if let lastResponse = connectionManager.lastResponseTime {
                StatItem(
                    title: "Last Response",
                    value: dateFormatter.string(from: lastResponse)
                )
            }

            if connectionManager.lastResponseSize > 0 {
                StatItem(
                    title: "Size",
                    value: formatBytes(connectionManager.lastResponseSize)
                )
            }
        }
        .padding(.vertical, 8)
    }

    private var connectionControls: some View {
        HStack {
            if case .connected = connectionManager.state {
                Button(action: { connectionManager.disconnect() }) {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else if let iface = ethernetInterface {
                Button(action: {
                    connectionManager.connect(usingInterface: iface.name, interfaceIP: iface.ipAddress)
                }) {
                    Label("Connect", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(connectionManager.state == .connecting)
            } else {
                Text("Waiting for Ethernet interface…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { connectionManager.clearLogs() }) {
                Label("Clear Logs", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(connectionManager.logs.isEmpty)
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection Log")
                .font(.subheadline)
                .fontWeight(.medium)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(connectionManager.logs) { log in
                        LogRow(log: log)
                    }
                }
            }
            .frame(maxHeight: 200)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}

struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .monospaced()
        }
    }
}

struct LogRow: View {
    let log: ConnectionManager.ConnectionLog

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeFormatter.string(from: log.timestamp))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospaced()

            Text(log.message)
                .font(.caption)
                .foregroundStyle(log.isError ? .red : .primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

#Preview {
    ConnectionStatusView(
        connectionManager: ConnectionManager(),
        ethernetInterface: NetworkInterface(
            id: "en2-10.0.0.5",
            name: "en2",
            ipAddress: "10.0.0.5",
            netmask: "255.255.255.0",
            isUp: true,
            isLoopback: false,
            isEthernet: true
        )
    )
    .padding()
}
