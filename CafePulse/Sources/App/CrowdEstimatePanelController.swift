import AppKit
import SwiftUI

final class CrowdEstimatePanelController {
    private weak var model: AppModel?
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    func present() {
        guard let model else {
            return
        }

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
                styleMask: [.titled, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Crowd Estimate"
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.center()
            panel.contentView = NSHostingView(
                rootView: CrowdEstimatePromptView()
                    .environmentObject(model)
                    .frame(width: 360, height: 280)
            )
            self.panel = panel
        }

        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }
}
