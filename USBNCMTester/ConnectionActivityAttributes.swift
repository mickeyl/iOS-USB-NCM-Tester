import ActivityKit
import Foundation

struct ConnectionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isConnected: Bool
        var requestCount: Int
        var lastResponseTime: Date?
        var interfaceName: String?
    }

    var targetHost: String
}
