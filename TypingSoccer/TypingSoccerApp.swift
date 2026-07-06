//
//  TypingSoccerApp.swift
//  TypingSoccer
//
//  App entry point. Authenticates Game Center on launch and shows the
//  main menu / match container.
//

import SwiftUI

@main
struct TypingSoccerApp: App {

    @StateObject private var coordinator = GameCoordinator()

    init() {
        GameCenterManager.shared.authenticate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowResizability(.contentSize)
    }
}
