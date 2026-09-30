import AppKit
import ServiceManagement

// Only the running bundle can withdraw its own login item, so uninstall.sh calls this before
// deleting the app.
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
