import SwiftUI

@main
struct CafePulseApp: App {
    @StateObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private let crowdEstimatePanelController: CrowdEstimatePanelController

    init() {
        let appModel = AppModel()
        _model = StateObject(wrappedValue: appModel)

        let panelController = CrowdEstimatePanelController(model: appModel)
        crowdEstimatePanelController = panelController

        appModel.presentCrowdPrompt = {
            panelController.present()
        }

        appModel.dismissCrowdPrompt = {
            panelController.close()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.isSampling ? "cup.and.saucer.fill" : "cup.and.saucer")
                if model.pendingCrowdPrompt {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(model.isSampling ? .green : .primary)
        }
        .menuBarExtraStyle(.window)

        Window("CafePulse", id: "main-window") {
            MainWindowView()
                .environmentObject(model)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                }
                .onDisappear {
                    // Go back to menu-bar-only when window closes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if !model.isMainWindowVisible {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                }
        }
        .defaultSize(width: 520, height: 600)
    }
}
