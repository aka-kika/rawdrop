import Foundation
import ServiceManagement

/// Open at Login via SMAppService (macOS 13+).
enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Opens when you log in"
        case .notRegistered:
            return "Not registered"
        case .notFound:
            return "App not found for login items (install to /Applications for best results)"
        case .requiresApproval:
            return "Waiting for approval in System Settings → General → Login Items"
        @unknown default:
            return "Unknown status"
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> SMAppService.Status {
        if enabled {
            if SMAppService.mainApp.status == .enabled {
                return .enabled
            }
            try SMAppService.mainApp.register()
        } else {
            if SMAppService.mainApp.status == .notRegistered {
                return .notRegistered
            }
            try SMAppService.mainApp.unregister()
        }
        return SMAppService.mainApp.status
    }
}
