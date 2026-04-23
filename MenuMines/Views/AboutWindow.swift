import AppKit
import SwiftUI

enum AboutWindow {
    /// Singleton window controller to maintain About window across show/hide cycles.
    /// Window is kept in memory (isReleasedWhenClosed = false) to preserve state
    /// and avoid repeated allocations. This is intentional for the About window.
    private static var windowController: NSWindowController?

    static func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let existingController = windowController, existingController.window?.isVisible == true {
            existingController.window?.makeKeyAndOrderFront(nil)
            return
        }

        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "about_menu_item")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
    }
}

private struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(String(localized: "about_title"))
                    .font(.title)
                    .fontWeight(.semibold)

                Text(String(format: String(localized: "about_version"), appVersion))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(String(localized: "about_description"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let supportURL = URL(string: "mailto:support@merimerimeri.com") {
                Link(String(localized: "about_support_email"), destination: supportURL)
                    .font(.caption)
            }

            Text(String(localized: "about_copyright"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 300)
    }
}

#Preview {
    AboutView()
}
