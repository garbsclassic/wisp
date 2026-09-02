import AppKit
import ServiceManagement

// `SMAppService.mainApp` identifies the login item by the *running* bundle, so
// only the app itself can withdraw its own registration. This flag gives
// uninstall.sh a way to do that before the bundle is deleted — removing the app
// first would leave a dangling login item behind.
if CommandLine.arguments.contains("--unregister-login-item") {
    let service = SMAppService.mainApp
    if service.status == .enabled {
        do {
            try service.unregister()
            print("Launch at Login removed.")
        } catch {
            print("Couldn't remove Launch at Login: \(error.localizedDescription)")
            exit(1)
        }
    } else {
        print("Launch at Login wasn't enabled.")
    }
    exit(0)
}

// AppKit's own initial tooltip delay is long enough to read as "no tooltip"
// on a panel you are only passing through. Registered rather than written:
// this seeds the default for this process only, so it neither persists nor
// overrides a value the user has set for themselves.
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 1000])

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
