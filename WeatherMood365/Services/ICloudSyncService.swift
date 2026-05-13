import Foundation

@MainActor
final class ICloudSyncService: ObservableObject {
    static let shared = ICloudSyncService()

    static let enabledKey = "icloudSyncEnabled"

    private init() {}
}
