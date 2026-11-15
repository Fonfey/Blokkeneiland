import SwiftUI
import MultipeerConnectivity

struct SkyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.68, blue: 0.98), Color(red: 0.74, green: 0.9, blue: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                Spacer()
                Rectangle().fill(Color(red: 0.38, green: 0.68, blue: 0.26)).frame(height: 36)
                Rectangle().fill(Color(red: 0.53, green: 0.38, blue: 0.26)).frame(height: 70)
            }
        }
        .ignoresSafeArea()
    }
}

struct BigButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 15)
                .frame(minWidth: 280)
                .background(RoundedRectangle(cornerRadius: 16).fill(color))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.25), lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 5)
        }
    }
}

struct AvatarPreview: View {
    let shirt: Int, pants: Int, skin: Int
    var body: some View {
        let s = Color(uiColor: Palette.shirt(shirt)), p = Color(uiColor: Palette.pant(pants)), k = Color(uiColor: Palette.skin(skin))
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(k).frame(width: 78, height: 78)
                HStack(spacing: 20) {
                    Rectangle().fill(.black).frame(width: 10, height: 13)
                    Rectangle().fill(.black).frame(width: 10, height: 13)
                }.offset(y: -4)
                Rectangle().fill(Color.black.opacity(0.75)).frame(width: 24, height: 4).offset(y: 18)
            }
            HStack(spacing: 0) {
                VStack(spacing: 0) { Rectangle().fill(s).frame(width: 28, height: 82); Rectangle().fill(k).frame(width: 28, height: 16) }
                Rectangle().fill(s).frame(width: 84, height: 98)
                VStack(spacing: 0) { Rectangle().fill(s).frame(width: 28, height: 82); Rectangle().fill(k).frame(width: 28, height: 16) }
            }
            HStack(spacing: 4) {
                Rectangle().fill(p).frame(width: 40, height: 104)
                Rectangle().fill(p).frame(width: 40, height: 104)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 6)
    }
}

struct ColorRow: View {
    let title: String
    let colors: [UIColor]
    @Binding var sel: Int
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 18, weight: .bold, design: .rounded)).frame(width: 70, alignment: .leading)
            ForEach(colors.indices, id: \.self) { i in
                Circle()
                    .fill(Color(uiColor: colors[i]))
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(Color.white, lineWidth: sel == i ? 4 : 0))
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .onTapGesture { sel = i }
            }
        }
    }
}

struct MenuView: View {
    @ObservedObject var app: AppState
    var body: some View {
        ZStack {
            SkyBackground()
            HStack(spacing: 50) {
                AvatarPreview(shirt: app.shirt, pants: app.pants, skin: app.skin)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Blokkeneiland")
                        .font(.system(size: 60, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: Color(red: 0.2, green: 0.3, blue: 0.5), radius: 0, x: 4, y: 4)
                    TextField("Je naam", text: $app.name)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.9)))
                        .frame(maxWidth: 360)
                        .submitLabel(.done)
                    VStack(alignment: .leading, spacing: 8) {
                        ColorRow(title: "Shirt", colors: Palette.shirts, sel: $app.shirt)
                        ColorRow(title: "Broek", colors: Palette.pants, sel: $app.pants)
                        ColorRow(title: "Huid", colors: Palette.skins, sel: $app.skin)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55)))
                    HStack(spacing: 14) {
                        BigButton(title: "Nieuw eiland", icon: "sparkles", color: Color(red: 0.25, green: 0.65, blue: 0.25)) { app.play(new: true) }
                        if app.hasSave {
                            BigButton(title: "Verder bouwen", icon: "hammer.fill", color: Color(red: 0.95, green: 0.55, blue: 0.1)) { app.play(new: false) }
                        }
                    }
                    BigButton(title: "Meedoen met een vriend", icon: "person.2.fill", color: Color(red: 0.2, green: 0.45, blue: 0.9)) { app.browse() }
                    if let e = app.error {
                        Text(e).font(.system(size: 16, weight: .semibold)).foregroundColor(.red)
                            .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.9)))
                    }
                }
            }
            .padding(40)
        }
    }
}

struct BrowseView: View {
    @ObservedObject var app: AppState
    @ObservedObject var net: Net
    var body: some View {
        ZStack {
            SkyBackground()
            VStack(spacing: 20) {
                Text("Meedoen met een vriend")
                    .font(.system(size: 44, weight: .black, design: .rounded)).foregroundColor(.white)
                    .shadow(color: Color(red: 0.2, green: 0.3, blue: 0.5), radius: 0, x: 3, y: 3)
                Text("Laat je vriend op zijn iPad een eiland openen. Het verschijnt hieronder zodra jullie bij elkaar in de buurt zijn.")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center).frame(maxWidth: 560)
                if net.found.isEmpty {
                    HStack(spacing: 12) { ProgressView(); Text("Zoeken naar eilanden…").font(.title3.bold()) }
                        .padding(22).background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.8)))
                } else {
                    VStack(spacing: 12) {
                        ForEach(net.found, id: \.self) { p in
                            BigButton(title: net.worldName(p), icon: "globe.europe.africa.fill", color: Color(red: 0.25, green: 0.65, blue: 0.25)) { app.join(p) }
                        }
                    }
                }
                Button("Terug") { app.leave() }
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
            }
            .padding(40)
        }
    }
}

struct WaitingView: View {
    @ObservedObject var app: AppState
    var body: some View {
        ZStack {
            SkyBackground()
            VStack(spacing: 18) {
                ProgressView().scaleEffect(1.8)
                Text("Verbinden met het eiland…").font(.system(size: 30, weight: .black, design: .rounded)).foregroundColor(.white)
                Button("Annuleren") { app.leave() }
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
            }
        }
    }
}
