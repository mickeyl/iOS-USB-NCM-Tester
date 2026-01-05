import ActivityKit
import Foundation

final class ActivityManager: ObservableObject {
    @Published private(set) var activityRunning = false

    private var activity: Activity<ConnectionActivityAttributes>?
    private let targetHost: String

    init(targetHost: String = "www.google.de") {
        self.targetHost = targetHost
    }

    func startActivity(interfaceName: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("DEBUG: [ACTIVITY] Live Activities not enabled")
            return
        }

        let attributes = ConnectionActivityAttributes(targetHost: targetHost)
        let state = ConnectionActivityAttributes.ContentState(
            isConnected: false,
            requestCount: 0,
            lastResponseTime: nil,
            interfaceName: interfaceName
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            activityRunning = true
            print("DEBUG: [ACTIVITY] Started Live Activity")
        } catch {
            print("DEBUG: [ACTIVITY] Failed to start: \(error.localizedDescription)")
        }
    }

    func updateActivity(
        isConnected: Bool,
        requestCount: Int,
        lastResponseTime: Date?,
        interfaceName: String?
    ) {
        guard let activity = activity else { return }

        let state = ConnectionActivityAttributes.ContentState(
            isConnected: isConnected,
            requestCount: requestCount,
            lastResponseTime: lastResponseTime,
            interfaceName: interfaceName
        )

        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: nil)
            )
        }
    }

    func endActivity() {
        guard let activity = activity else { return }

        let finalState = ConnectionActivityAttributes.ContentState(
            isConnected: false,
            requestCount: 0,
            lastResponseTime: nil,
            interfaceName: nil
        )

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            await MainActor.run {
                self.activity = nil
                self.activityRunning = false
                print("DEBUG: [ACTIVITY] Ended Live Activity")
            }
        }
    }
}
