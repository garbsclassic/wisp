import ServiceManagement

/// Registering needs the bundled .app from scripts/build.sh; under `swift run` it fails.
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return }
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // No UI for this: the menu's checkmark just doesn't flip.
            print("LaunchAtLogin: \(enabled ? "register" : "unregister") failed: \(error)")
        }
    }
}
