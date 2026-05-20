import Foundation
import ServiceManagement

final class LaunchAtLoginController {
    enum LaunchAtLoginError: LocalizedError {
        case requiresAppBundle

        var errorDescription: String? {
            switch self {
            case .requiresAppBundle:
                return "开机自动启动需要从 PixelFlow.app 运行。请先执行 ./Scripts/build-app.sh 并打开 .build/PixelFlow.app。"
            }
        }
    }

    var isAvailable: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    var isEnabled: Bool {
        guard isAvailable else {
            return false
        }

        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard isAvailable else {
            throw LaunchAtLoginError.requiresAppBundle
        }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
