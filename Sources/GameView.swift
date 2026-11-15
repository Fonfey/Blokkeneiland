import SwiftUI
import SceneKit

struct SceneContainer: UIViewRepresentable {
    let view: SCNView
    func makeUIView(context: Context) -> SCNView { view }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

struct GameView: View {
    @ObservedObject var game: GameController
    let onLeave: () -> Void
    @State private var menu = false

    var body: some View {
        ZStack {
            SceneContainer(view: game.scnView).ignoresSafeArea()
            if game.underwater {
                Color(red: 0.1, green: 0.3, blue: 0.8).opacity(0.35).ignoresSafeArea().allowsHitTesting(false)
            }
            LookPad(game: game).ignoresSafeArea()
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 1)
                .allowsHitTesting(false)

            VStack {
                HStack(alignment: .top, spacing: 12) {
                    PlayerChips(players: game.roster)
                    Spacer()
                    if let t = game.tagText {
                        Text(t)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(Color.red.opacity(0.85)))
                    }
                    Spacer()
                    RoundIcon(icon: game.thirdPerson ? "eye.fill" : "person.fill") { game.thirdPerson.toggle() }
                    RoundIcon(icon: "pause.fill") { menu = true }
                }
                .padding(.horizontal, 20).padding(.top, 14)
                Spacer()
                HStack(alignment: .bottom) {
                    Joystick(game: game).padding(.leading, 34).padding(.bottom, 30)
                    Spacer(minLength: 10)
                    Hotbar(game: game).padding(.bottom, 14)
                    Spacer(minLength: 10)
                    ActionPad(game: game).padding(.trailing, 30).padding(.bottom, 24)
                }
            }

            if let t = game.toast {
                VStack {
                    Text(t)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(.top, 74)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if menu {
                PauseMenu(game: game, close: { menu = false }, leave: onLeave)
            }
        }
    }
}

struct LookPad: View {
    let game: GameController
    @State private var lastT: CGSize = .zero
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let dx = v.translation.width - lastT.width
                        let dy = v.translation.height - lastT.height
                        lastT = v.translation
                        game.look(dx: Float(dx), dy: Float(dy))
                    }
                    .onEnded { _ in lastT = .zero }
            )
    }
}

struct Joystick: View {
    let game: GameController
    @State private var knob: CGSize = .zero
    private let size: CGFloat = 170
    private let reach: CGFloat = 58
    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.25))
                .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 3))
            Circle().fill(Color.white.opacity(0.9)).frame(width: 70, height: 70).offset(knob)
                .shadow(radius: 3)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    var d = CGSize(width: v.location.x - size / 2, height: v.location.y - size / 2)
                    let l = (d.width * d.width + d.height * d.height).squareRoot()
                    if l > reach {
                        d.width *= reach / l
                        d.height *= reach / l
                    }
                    knob = d
                    game.move = SIMD2<Float>(Float(d.width / reach), Float(-d.height / reach))
                }
                .onEnded { _ in
                    knob = .zero
                    game.move = SIMD2<Float>(0, 0)
                }
        )
    }
}

struct ActionPad: View {
    let game: GameController
    @State private var jumping = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            HStack(spacing: 16) {
                ActionButton(icon: "hammer.fill", label: "Breek", color: Color(red: 0.85, green: 0.25, blue: 0.2)) { game.breakBlock() }
                ActionButton(icon: "cube.fill", label: "Bouw", color: Color(red: 0.25, green: 0.65, blue: 0.25)) { game.placeBlock() }
            }
            ZStack {
                Circle().fill(jumping ? Color.yellow : Color.orange)
                VStack(spacing: 0) {
                    Image(systemName: "arrow.up").font(.system(size: 36, weight: .heavy))
                    Text("Spring").font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
            }
            .frame(width: 104, height: 104)
            .shadow(color: .black.opacity(0.3), radius: 4)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !jumping {
                            jumping = true
                            game.jumpHeld = true
                        }
                    }
                    .onEnded { _ in
                        jumping = false
                        game.jumpHeld = false
                    }
            )
        }
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 30, weight: .bold))
                Text(label).font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(width: 90, height: 90)
            .background(Circle().fill(color))
            .shadow(color: .black.opacity(0.3), radius: 4)
        }
    }
}

struct Hotbar: View {
    @ObservedObject var game: GameController
    var body: some View {
        VStack(spacing: 6) {
            Text(Block.placeable[game.selected].name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.45)))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Block.placeable.indices, id: \.self) { i in
                        Image(uiImage: Atlas.tileImages[Block.placeable[i].tile(4)])
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 46, height: 46)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(game.selected == i ? 0.6 : 0.3)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(game.selected == i ? Color.white : Color.clear, lineWidth: 3))
                            .onTapGesture { game.selected = i }
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: 470)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.25)))
        }
    }
}

struct PlayerChips: View {
    let players: [PlayerInfo]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(players, id: \.id) { p in
                HStack(spacing: 6) {
                    Circle().fill(Color(uiColor: Palette.shirt(p.shirt))).frame(width: 14, height: 14)
                    Text(p.name).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.4)))
            }
        }
    }
}

struct RoundIcon: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.black.opacity(0.4)))
        }
    }
}

struct PauseMenu: View {
    @ObservedObject var game: GameController
    let close: () -> Void
    let leave: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture(perform: close)
            VStack(spacing: 14) {
                Text("Pauze").font(.system(size: 40, weight: .black, design: .rounded))
                Text(game.isHost
                     ? "Andere iPads in de buurt kunnen meedoen via ‘Meedoen met een vriend’."
                     : "Je speelt op het eiland van een vriend.")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                if game.isHost {
                    MenuRow(title: "Start tikkertje", icon: "figure.run", color: .orange, disabled: !game.canStartTag) {
                        game.startTag()
                        close()
                    }
                }
                MenuRow(title: game.thirdPerson ? "Camera: achter je" : "Camera: door je ogen", icon: "camera.fill", color: .blue, disabled: false) {
                    game.thirdPerson.toggle()
                }
                MenuRow(title: "Terug naar het begin", icon: "house.fill", color: .green, disabled: false) {
                    game.spawn()
                    close()
                }
                MenuRow(title: "Stoppen", icon: "xmark", color: .red, disabled: false, action: leave)
                Text("Links: lopen · Sleep over het scherm: rondkijken · Richt het plusje op een blok en tik op Breek of Bouw")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding(30)
            .frame(maxWidth: 480)
            .background(RoundedRectangle(cornerRadius: 26).fill(.regularMaterial))
        }
    }
}

struct MenuRow: View {
    let title: String
    let icon: String
    let color: Color
    let disabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 14).fill(color))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}
