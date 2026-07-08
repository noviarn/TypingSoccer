//
//  TypingSoccerApp.swift
//  TypingSoccer
//
//  App entry point. Authenticates Game Center and preloads textures on
//  launch, then shows the main menu / match container.
//

import SwiftUI
import SpriteKit

@main
struct TypingSoccerApp: App {

    @StateObject private var coordinator = GameCoordinator()

    init() {
        GameCenterManager.shared.authenticate()
        AssetPreloader.preloadAll()
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

/// Uploads game textures to the GPU once at launch, off the main thread,
/// so the first match doesn't hitch when an asset is drawn for the first
/// time. Add new asset-catalog image names here as art is added.
enum AssetPreloader {

    private static let textureNames = [
        "game-main-bg",
    ]

    private static var preloaded: [SKTexture] = []   // keep them alive

    static func preloadAll() {
        let textures = textureNames.map { SKTexture(imageNamed: $0) }
        preloaded = textures
        SKTexture.preload(textures) {
            NSLog("Preloaded %d game textures", textures.count)
        }
    }
}
