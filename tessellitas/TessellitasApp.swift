//
//  TessellitasApp.swift
//  tessellitas
//
//  Created by sovrin on 01.10.26.
//

import SwiftUI

@main
struct TessellitasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: AppModel.shared)
        } label: {
            Image(nsImage: MenuBarGlyph.image)
        }
        .menuBarExtraStyle(.window)

        Window("tessellitas", id: "settings") {
            SettingsView(model: AppModel.shared)
        }
        .defaultLaunchBehavior(.suppressed)   // only open when asked for from the menu
        .defaultSize(width: 880, height: 640)
        .windowResizability(.contentMinSize)
    }
}

/// Hotkeys must be live from launch, not from the first time the menu is opened.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
    }
}
