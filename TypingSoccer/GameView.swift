//
//  GameView.swift
//  TypingSoccer
//
//  SwiftUI menu + SpriteKit host view + the coordinator that ties the
//  scene together with Multipeer, GameKit and Foundation Models feedback.
//

import SwiftUI
import SpriteKit
import MultipeerConnectivity

// MARK: - Coordinator

@MainActor
final class GameCoordinator: ObservableObject {
    
    enum Screen { case menu, playing, results }
    
    @Published var screen: Screen = .menu
    @Published var feedbackText: String = ""
    @Published var finalHome = 0
    @Published var finalAway = 0
    @Published var peerConnected = false
    @Published var isGeneratingFeedback = false
    
    private(set) var scene: GameScene?
    private let multipeer = MultipeerManager()
    
    func startSinglePlayer() {
        multipeer.stop()
        launch(mode: .singlePlayer)
    }
    
    func startHosting() {
        multipeer.delegate = self
        multipeer.host()
        launch(mode: .multipeer)
    }
    
    func startJoining() {
        multipeer.delegate = self
        multipeer.join()
        launch(mode: .multipeer)
    }
    
    private func launch(mode: MatchMode) {
        let s = GameScene(size: GameConfig.sceneSize)
        s.mode = mode
        s.gameDelegate = self
        scene = s
        feedbackText = ""
        screen = .playing
    }
    
    func returnToMenu() {
        multipeer.stop()
        scene = nil
        screen = .menu
    }
}

extension GameCoordinator: GameSceneDelegate {
    nonisolated func matchDidFinish(homeStats: PlayerStats, homeScore: Int, awayScore: Int) {
        Task { @MainActor in
            self.finalHome = homeScore
            self.finalAway = awayScore
            self.isGeneratingFeedback = true
            self.screen = .results
            GameCenterManager.shared.submit(score: Int(homeStats.averageWPM.rounded()))
            let text = await MatchFeedback.generate(stats: homeStats,
                                                    homeScore: homeScore,
                                                    awayScore: awayScore)
            self.feedbackText = text
            self.isGeneratingFeedback = false
        }
    }
    
    nonisolated func localPlayerCompletedWord() {
        Task { @MainActor in self.multipeer.send(.wordCompleted) }
    }
}

extension GameCoordinator: MultipeerManagerDelegate {
    nonisolated func peerConnectionChanged(connected: Bool) {
        Task { @MainActor in self.peerConnected = connected }
    }
    nonisolated func didReceive(_ message: PeerMessage, from peer: MCPeerID) {
        Task { @MainActor in
            switch message {
            case .wordCompleted: self.scene?.remotePlayerCompletedWord()
            default: break
            }
        }
    }
}

// MARK: - SpriteKit host (NSViewRepresentable so we control first responder)

struct SpriteHostView: NSViewRepresentable {
    let scene: GameScene
    
    func makeNSView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.ignoresSiblingOrder = true
        view.presentScene(scene)
        return view
    }
    
    func updateNSView(_ nsView: SKView, context: Context) {
        if nsView.scene !== scene { nsView.presentScene(scene) }
        // Grab keyboard focus so the scene receives keyDown events.
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

// MARK: - Root UI

struct ContentView: View {
    @EnvironmentObject var coordinator: GameCoordinator
    
    var body: some View {
        ZStack {
            Image("game-main-bg")
                .resizable()
            //                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
            Color.black.opacity(scrimOpacity)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: coordinator.screen)
            switch coordinator.screen {
            case .menu:    MenuView()
            case .playing: PlayingView()
            case .results: ResultsView()
            }
            if coordinator.screen == .menu {
                VStack {
                    TopBar()
                    Spacer()
                }
            }
        }
    }
    
    private var scrimOpacity: Double {
        switch coordinator.screen {
        case .menu:    0.25
        case .playing: 0.75
        case .results: 0.55
        }
    }
}

struct TopBar: View {
    var body: some View {
        HStack {
            HStack(alignment: .center, spacing: 5) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 24))
                Text("Guest")
                    .font(.custom("Silom", size: 16))
            }
            .foregroundStyle(
                Color(red: 203/255, green: 197/255, blue: 197/255) // #CBC5C5
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Color(red: 109/255, green: 112/255, blue: 116/255) // #6D7074
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Spacer()
            Button(action: {
                //
            }) {
                Circle()
                    .fill(Color(red: 109/255, green: 112/255, blue: 116/255)) // #6D7074
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(
                                Color(red: 238/255, green: 170/255, blue: 82/255) // #EEAA52
                            )
                    )
            }
            .buttonStyle(.plain)
            Button(action: {
                //
            }) {
                Circle()
                    .fill(Color(red: 109/255, green: 112/255, blue: 116/255)) // #6D7074
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(
                                Color(red: 203/255, green: 197/255, blue: 197/255) // #CBC5C5
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct MenuView: View {
    @EnvironmentObject var coordinator: GameCoordinator
    
    var body: some View {
        VStack(spacing: 22) {
            Text("Typer Cup")
                .font(.system(size: 44, weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow)
                .textCase(.uppercase)
            Text("Type fast. Win the ball. Score.")
                .font(.system(.title3, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 2)
            VStack(spacing: 14) {
                menuButton("SINGLE PLAYER (vs AI)") { coordinator.startSinglePlayer() }
                menuButton("MULTIPLAYER — HOST") { coordinator.startHosting() }
                menuButton("MULTIPLAYER — JOIN") { coordinator.startJoining() }
            }
            .padding(.top, 12)
            
            Text("Countdown whistle → type the word → first to finish gets the ball.\nCarriers auto-run to goal; defenders intercept with new words.")
                .multilineTextAlignment(.center)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))   .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 2)
                .padding(.top, 8)
        }
        .padding(40)
    }
    
    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .frame(width: 320, height: 46)
                .background(Color.yellow.opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 1.5))
                .foregroundColor(.yellow)
        }
        .buttonStyle(.plain)
    }
}

struct PlayingView: View {
    @EnvironmentObject var coordinator: GameCoordinator
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let scene = coordinator.scene {
                SpriteHostView(scene: scene)
                    .aspectRatio(GameConfig.sceneSize.width / GameConfig.sceneSize.height, contentMode: .fit)
            }
            if coordinator.scene?.mode == .multipeer {
                Text(coordinator.peerConnected ? "● connected" : "○ waiting for peer…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(coordinator.peerConnected ? .green : .orange)
                    .padding(10)
            }
        }
    }
}

struct ResultsView: View {
    @EnvironmentObject var coordinator: GameCoordinator
    
    var body: some View {
        VStack(spacing: 20) {
            Text("FULL TIME")
                .font(.system(size: 36, weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow)
            Text("\(coordinator.finalHome)  –  \(coordinator.finalAway)")
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            Group {
                if coordinator.isGeneratingFeedback {
                    ProgressView("Your coach is reviewing the match…")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                } else {
                    Text(coordinator.feedbackText)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
            }
            .padding(.vertical, 8)
            
            Button(action: { coordinator.returnToMenu() }) {
                Text("BACK TO MENU")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .frame(width: 240, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 1.5))
                    .foregroundColor(.yellow)
            }
            .buttonStyle(.plain)
        }
        .padding(40)
    }
}

#Preview {
    ContentView()
        .environmentObject(GameCoordinator())
}
