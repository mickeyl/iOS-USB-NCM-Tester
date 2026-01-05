import ActivityKit
import SwiftUI
import WidgetKit

struct ConnectionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConnectionActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: context.state.isConnected ? "cable.connector" : "cable.connector.slash")
                            .foregroundStyle(context.state.isConnected ? .green : .red)
                        Text(context.state.interfaceName ?? "—")
                            .font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("#\(context.state.requestCount)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.targetHost)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let lastResponse = context.state.lastResponseTime {
                            Text(lastResponse, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isConnected ? "cable.connector" : "cable.connector.slash")
                    .foregroundStyle(context.state.isConnected ? .green : .red)
            } compactTrailing: {
                Text("\(context.state.requestCount)")
                    .monospacedDigit()
                    .fontWeight(.semibold)
            } minimal: {
                Image(systemName: context.state.isConnected ? "cable.connector" : "cable.connector.slash")
                    .foregroundStyle(context.state.isConnected ? .green : .red)
            }
        }
    }
}

struct LockScreenView: View {
    let context: ActivityViewContext<ConnectionActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: context.state.isConnected ? "cable.connector" : "cable.connector.slash")
                .font(.title)
                .foregroundStyle(context.state.isConnected ? .green : .red)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(context.state.isConnected ? "Connected" : "Disconnected")
                        .font(.headline)
                    if let iface = context.state.interfaceName {
                        Text("via \(iface)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(context.attributes.targetHost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("#\(context.state.requestCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                if let lastResponse = context.state.lastResponseTime {
                    Text(lastResponse, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
