import SwiftUI
import MultipeerConnectivity

@main
struct BlokkeneilandApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

enum Screen { case menu, browse, waiting, game }

final class AppState: ObservableObject {
    @Published var screen: Screen = .menu
    @Published var name: String = ""
    @Published var shirt: Int = 0
    @Published var pants: Int = 0
    @Published var skin: Int = 0
    @Published var net: Net? = nil
    @Published var game: GameController? = nil
    @Published var error: String? = nil
    @Published var hasSave = false
    private var playerId = ""

    init() {
        let d = UserDefaults.standard
        name = d.string(forKey: "name") ?? "Speler\(Int.random(in: 10...99))"
        shirt = d.integer(forKey: "shirt")
        pants = d.integer(forKey: "pants")
        skin = d.integer(forKey: "skin")
        if let s = d.string(forKey: "pid") {
            playerId = s
        } else {
            playerId = UUID().uuidString
            d.set(playerId, forKey: "pid")
        }
        hasSave = GameController.loadSaved() != nil
    }

    var cleanName: String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Speler" : String(t.prefix(16))
    }

    var info: PlayerInfo { PlayerInfo(id: playerId, name: cleanName, shirt: shirt, pants: pants, skin: skin) }

    private func saveProfile() {
        let d = UserDefaults.standard
        d.set(cleanName, forKey: "name")
        d.set(shirt, forKey: "shirt")
        d.set(pants, forKey: "pants")
        d.set(skin, forKey: "skin")
        error = nil
    }

    func play(new: Bool) {
        saveProfile()
        let n = Net(name: cleanName)
        n.host(worldName: "Eiland van \(cleanName)")
        let g = GameController(me: info, net: n, isHost: true)
        let saved = new ? nil : GameController.loadSaved()
        g.startNew(seed: saved?.seed ?? UInt32.random(in: 1...UInt32.max), edits: saved?.edits ?? [])
        net = n
        game = g
        screen = .game
    }

    func browse() {
        saveProfile()
        let n = Net(name: cleanName)
        n.browse()
        net = n
        screen = .browse
    }

    func join(_ p: MCPeerID) {
        guard let n = net else { return }
        let g = GameController(me: info, net: n, isHost: false)
        g.onReady = { [weak self] in self?.screen = .game }
        g.onDisconnected = { [weak self] in
            self?.leave()
            self?.error = "Verbinden lukte niet. Staan beide iPads op hetzelfde wifi-netwerk en is het eiland nog open?"
        }
        game = g
        n.join(p)
        screen = .waiting
    }

    func leave() {
        game?.stop()
        net?.stop()
        game = nil
        net = nil
        hasSave = GameController.loadSaved() != nil
        screen = .menu
    }
}

struct RootView: View {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            switch app.screen {
            case .menu:
                MenuView(app: app)
            case .browse:
                if let n = app.net { BrowseView(app: app, net: n) } else { MenuView(app: app) }
            case .waiting:
                WaitingView(app: app)
            case .game:
                if let g = app.game { GameView(game: g, onLeave: { app.leave() }) } else { MenuView(app: app) }
            }
        }
        .onChange(of: phase) { p in
            if p != .active { app.game?.saveWorld() }
        }
    }
}
