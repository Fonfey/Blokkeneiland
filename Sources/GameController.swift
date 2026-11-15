import SceneKit
import UIKit
import MultipeerConnectivity
import simd

struct IV: Hashable {
    var x: Int, y: Int, z: Int
}

struct SavedWorld: Codable {
    var seed: UInt32
    var edits: [Edit]
}

final class RemotePlayer {
    var info: PlayerInfo
    let node: AvatarNode
    var target = SIMD3<Float>(repeating: 0)
    var cur = SIMD3<Float>(repeating: 0)
    var yaw: Float = 0
    var hasPos = false
    init(info: PlayerInfo) {
        self.info = info
        node = AvatarNode(info: info)
    }
}

/// Owns the 3D scene, the local player and the multiplayer sync.
final class GameController: NSObject, ObservableObject {
    let scnView = SCNView(frame: .zero)
    let scene = SCNScene()
    let isHost: Bool
    let me: PlayerInfo
    let net: Net

    @Published var selected = 0
    @Published var thirdPerson = false { didSet { myAvatar.isHidden = !thirdPerson } }
    @Published var roster: [PlayerInfo] = []
    @Published var toast: String?
    @Published var tagText: String?
    @Published var underwater = false

    var onReady: (() -> Void)?
    var onDisconnected: (() -> Void)?

    // input
    var move = SIMD2<Float>(0, 0)
    var jumpHeld = false

    private(set) var world: World?
    private var opaqueNodes: [Int: SCNNode] = [:]
    private var blendNodes: [Int: SCNNode] = [:]
    private let camNode = SCNNode()
    private let highlight = SCNNode()
    private let sun = SCNNode(), amb = SCNNode()
    private let opaqueMat = SCNMaterial(), blendMat = SCNMaterial()
    private let myAvatar: AvatarNode
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var sendTimer: Float = 0
    private var saveTimer: Float = 0
    private let startTime = CACurrentMediaTime()
    private var dayOffset: Double = 120

    private var pos = SIMD3<Float>(48, 30, 48)
    private var vel = SIMD3<Float>(repeating: 0)
    private var yaw: Float = 0
    private var pitch: Float = -0.25
    private var onGround = false
    private var target: (hit: IV, prev: IV)?

    private var remotes: [String: RemotePlayer] = [:]
    private var peerIds: [MCPeerID: String] = [:]
    private var tagIt: String?
    private var tagEnd: CFTimeInterval = 0
    private var tagImmune: CFTimeInterval = 0
    private var localTagCooldown: CFTimeInterval = 0
    private var toastWork: DispatchWorkItem?

    init(me: PlayerInfo, net: Net, isHost: Bool) {
        self.me = me
        self.net = net
        self.isHost = isHost
        myAvatar = AvatarNode(info: me)
        super.init()
        setupScene()
        roster = [me]
        net.onMessage = { [weak self] m, p in self?.handle(m, from: p) }
        net.onPeerChange = { [weak self] p, s in self?.peerChanged(p, s) }
    }

    // MARK: setup

    private func setupScene() {
        for m in [opaqueMat, blendMat] {
            m.diffuse.contents = Atlas.image
            m.diffuse.magnificationFilter = .nearest
            m.diffuse.minificationFilter = .nearest
            m.diffuse.mipFilter = .none
            m.diffuse.wrapS = .clamp
            m.diffuse.wrapT = .clamp
            m.lightingModel = .constant
        }
        blendMat.blendMode = .alpha
        blendMat.transparencyMode = .aOne
        blendMat.writesToDepthBuffer = false
        blendMat.isDoubleSided = true

        let cam = SCNCamera()
        cam.fieldOfView = 72
        cam.zNear = 0.05
        cam.zFar = 220
        camNode.camera = cam
        scene.rootNode.addChildNode(camNode)

        let sl = SCNLight()
        sl.type = .directional
        sun.light = sl
        sun.eulerAngles = SCNVector3(-0.9, 0.6, 0)
        scene.rootNode.addChildNode(sun)
        let al = SCNLight()
        al.type = .ambient
        al.intensity = 500
        amb.light = al
        scene.rootNode.addChildNode(amb)

        let hb = SCNBox(width: 1.01, height: 1.01, length: 1.01, chamferRadius: 0)
        let hm = SCNMaterial()
        hm.diffuse.contents = UIColor(white: 0, alpha: 0.75)
        hm.lightingModel = .constant
        hm.fillMode = .lines
        hb.materials = [hm]
        highlight.geometry = hb
        highlight.isHidden = true
        scene.rootNode.addChildNode(highlight)

        myAvatar.isHidden = true
        scene.rootNode.addChildNode(myAvatar)

        scene.fogStartDistance = 38
        scene.fogEndDistance = 80
        scnView.scene = scene
        scnView.pointOfView = camNode
        scnView.allowsCameraControl = false
        scnView.preferredFramesPerSecond = 60
        scnView.antialiasingMode = .multisampling2X
        scnView.isPlaying = true
        scnView.backgroundColor = .black
        dayNight()
    }

    func startNew(seed: UInt32, edits: [Edit]) {
        load(seed: seed, edits: edits)
    }

    private func load(seed: UInt32, edits: [Edit]) {
        let w = World(seed: seed)
        w.apply(edits)
        world = w
        for cz in 0..<(WZ / CS) {
            for cx in 0..<(WX / CS) { rebuild(cx, cz) }
        }
        spawn()
        last = CACurrentMediaTime()
        link?.invalidate()
        let l = CADisplayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        onReady?()
    }

    func stop() {
        saveWorld()
        link?.invalidate()
        link = nil
        scnView.isPlaying = false
    }

    func spawn() {
        guard let w = world else { return }
        var best = IV(x: WX / 2, y: w.top(WX / 2, WZ / 2), z: WZ / 2)
        search: for r in 0..<40 {
            for dz in -r...r {
                for dx in -r...r where abs(dx) == r || abs(dz) == r {
                    let x = WX / 2 + dx, z = WZ / 2 + dz
                    let y = w.top(x, z)
                    if w.get(x, y, z) != .water && w.get(x, y, z) != .leaves {
                        best = IV(x: x, y: y, z: z)
                        break search
                    }
                }
            }
        }
        pos = SIMD3<Float>(Float(best.x) + 0.5, Float(best.y) + 1.05, Float(best.z) + 0.5)
        vel = SIMD3<Float>(repeating: 0)
    }

    // MARK: chunks & blocks

    private func rebuild(_ cx: Int, _ cz: Int) {
        guard let w = world, cx >= 0, cz >= 0, cx < WX / CS, cz < WZ / CS else { return }
        let key = cz * 100 + cx
        let (og, bg) = Mesher.build(world: w, cx: cx, cz: cz, opaque: opaqueMat, blend: blendMat)
        update(&opaqueNodes, key, og, order: 0)
        update(&blendNodes, key, bg, order: 10)
    }

    private func update(_ dict: inout [Int: SCNNode], _ key: Int, _ g: SCNGeometry?, order: Int) {
        if let g = g {
            if let n = dict[key] {
                n.geometry = g
            } else {
                let n = SCNNode(geometry: g)
                n.renderingOrder = order
                scene.rootNode.addChildNode(n)
                dict[key] = n
            }
        } else if let n = dict[key] {
            n.removeFromParentNode()
            dict[key] = nil
        }
    }

    func setBlock(_ x: Int, _ y: Int, _ z: Int, _ b: Block, broadcast: Bool) {
        guard let w = world, w.inside(x, y, z) else { return }
        if w.get(x, y, z) == b { return }
        w.set(x, y, z, b)
        let cx = x / CS, cz = z / CS
        rebuild(cx, cz)
        if x % CS == 0 { rebuild(cx - 1, cz) }
        if x % CS == CS - 1 { rebuild(cx + 1, cz) }
        if z % CS == 0 { rebuild(cx, cz - 1) }
        if z % CS == CS - 1 { rebuild(cx, cz + 1) }
        if broadcast { net.send(.edit(Edit(x: x, y: y, z: z, b: b.rawValue))) }
    }

    func breakBlock() {
        guard let t = target, t.hit.y > 0 else { return }
        setBlock(t.hit.x, t.hit.y, t.hit.z, .air, broadcast: true)
    }

    func placeBlock() {
        guard let t = target else { return }
        let p = t.prev
        let b = Block.placeable[selected]
        if b.isSolid {
            if overlaps(p, pos) { return }
            for r in remotes.values where overlaps(p, r.cur) { return }
        }
        setBlock(p.x, p.y, p.z, b, broadcast: true)
    }

    private func overlaps(_ c: IV, _ p: SIMD3<Float>) -> Bool {
        Float(c.x) < p.x + 0.3 && Float(c.x + 1) > p.x - 0.3 &&
            Float(c.z) < p.z + 0.3 && Float(c.z + 1) > p.z - 0.3 &&
            Float(c.y) < p.y + 1.7 && Float(c.y + 1) > p.y
    }

    // MARK: input

    func look(dx: Float, dy: Float) {
        yaw -= dx * 0.006
        pitch = max(-1.5, min(1.5, pitch - dy * 0.006))
    }

    // MARK: frame loop

    @objc private func step(_ l: CADisplayLink) {
        let now = l.timestamp
        let dt = min(Float(now - last), 0.1)
        last = now
        guard let w = world else { return }
        var rem = dt
        while rem > 0 {
            let s = min(rem, 1 / 60)
            physics(s, w)
            rem -= s
        }
        if pos.y < -10 { spawn() }
        updateCamera(w)

        for r in remotes.values where r.hasPos {
            let prev = r.cur
            r.cur += (r.target - r.cur) * min(1, dt * 10)
            let sp = simd_length(SIMD2<Float>(r.cur.x - prev.x, r.cur.z - prev.z)) / max(dt, 0.001)
            r.node.simdPosition = r.cur
            r.node.eulerAngles.y = r.yaw
            r.node.animate(speed: sp, dt: dt)
        }
        myAvatar.simdPosition = pos
        myAvatar.eulerAngles.y = yaw
        myAvatar.animate(speed: simd_length(SIMD2<Float>(vel.x, vel.z)), dt: dt)

        sendTimer += dt
        if sendTimer > 0.1 {
            sendTimer = 0
            net.send(.state(id: me.id, x: pos.x, y: pos.y, z: pos.z, yaw: yaw), reliable: false)
        }
        saveTimer += dt
        if saveTimer > 30 {
            saveTimer = 0
            saveWorld()
        }
        dayNight()
        tagStep()
    }

    private func collides(_ p: SIMD3<Float>, _ w: World) -> Bool {
        let r: Float = 0.3
        let x0 = Int(floor(p.x - r)), x1 = Int(floor(p.x + r - 0.001))
        let y0 = Int(floor(p.y)), y1 = Int(floor(p.y + 1.7 - 0.001))
        let z0 = Int(floor(p.z - r)), z1 = Int(floor(p.z + r - 0.001))
        for y in y0...y1 {
            for z in z0...z1 {
                for x in x0...x1 where w.solid(x, y, z) { return true }
            }
        }
        return false
    }

    private func physics(_ dt: Float, _ w: World) {
        let inWater = w.get(Int(floor(pos.x)), Int(floor(pos.y + 0.4)), Int(floor(pos.z))) == .water
        let speed: Float = inWater ? 2.6 : 4.6
        let fwd = SIMD2<Float>(-sin(yaw), -cos(yaw)), right = SIMD2<Float>(cos(yaw), -sin(yaw))
        var m = fwd * move.y + right * move.x
        let ml = simd_length(m)
        if ml > 1 { m /= ml }
        vel.x = m.x * speed
        vel.z = m.y * speed
        if inWater {
            vel.y = max(vel.y - 9 * dt, -3)
            if jumpHeld { vel.y = 3.4 }
        } else {
            vel.y = max(vel.y - 26 * dt, -30)
            if jumpHeld && onGround {
                vel.y = 8.4
                onGround = false
            }
        }
        var p = pos
        for axis in [0, 2] {
            var q = p
            q[axis] += (axis == 0 ? vel.x : vel.z) * dt
            if collides(q, w) {
                var up = q
                up.y += 1.0
                var head = p
                head.y += 1.0
                if onGround && !collides(up, w) && !collides(head, w) { q = up } else { continue }
            }
            p = q
        }
        var q = p
        q.y += vel.y * dt
        if collides(q, w) {
            if vel.y < 0 {
                q.y = floor(q.y) + 1
                onGround = true
                if collides(q, w) { q.y = p.y }
            } else {
                q.y = p.y
            }
            vel.y = 0
        } else {
            onGround = false
        }
        pos = q
    }

    private func updateCamera(_ w: World) {
        let dir = SIMD3<Float>(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
        let eye = pos + SIMD3<Float>(0, 1.6, 0)
        camNode.simdOrientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        if thirdPerson {
            var dist: Float = 0.5
            while dist < 4.2 {
                let c = eye - dir * dist
                if w.solid(Int(floor(c.x)), Int(floor(c.y)), Int(floor(c.z))) { dist -= 0.3; break }
                dist += 0.25
            }
            camNode.simdPosition = eye - dir * max(0.3, dist) + SIMD3<Float>(0, 0.3, 0)
        } else {
            camNode.simdPosition = eye
        }
        target = raycast(eye, dir, 6, w)
        if let t = target {
            highlight.isHidden = false
            highlight.simdPosition = SIMD3<Float>(Float(t.hit.x) + 0.5, Float(t.hit.y) + 0.5, Float(t.hit.z) + 0.5)
        } else {
            highlight.isHidden = true
        }
        let c = camNode.simdPosition
        let uw = w.get(Int(floor(c.x)), Int(floor(c.y)), Int(floor(c.z))) == .water
        if uw != underwater { underwater = uw }
    }

    private func raycast(_ o: SIMD3<Float>, _ d: SIMD3<Float>, _ maxD: Float, _ w: World) -> (hit: IV, prev: IV)? {
        var x = Int(floor(o.x)), y = Int(floor(o.y)), z = Int(floor(o.z))
        let sx = d.x > 0 ? 1 : -1, sy = d.y > 0 ? 1 : -1, sz = d.z > 0 ? 1 : -1
        let ddx: Float = d.x == 0 ? .infinity : abs(1 / d.x)
        let ddy: Float = d.y == 0 ? .infinity : abs(1 / d.y)
        let ddz: Float = d.z == 0 ? .infinity : abs(1 / d.z)
        var tx: Float = d.x == 0 ? .infinity : (d.x > 0 ? Float(x + 1) - o.x : o.x - Float(x)) * ddx
        var ty: Float = d.y == 0 ? .infinity : (d.y > 0 ? Float(y + 1) - o.y : o.y - Float(y)) * ddy
        var tz: Float = d.z == 0 ? .infinity : (d.z > 0 ? Float(z + 1) - o.z : o.z - Float(z)) * ddz
        var prev = IV(x: x, y: y, z: z)
        var t: Float = 0
        while t <= maxD {
            let b = w.get(x, y, z)
            if b != .air && b != .water { return (IV(x: x, y: y, z: z), prev) }
            prev = IV(x: x, y: y, z: z)
            if tx < ty && tx < tz {
                x += sx; t = tx; tx += ddx
            } else if ty < tz {
                y += sy; t = ty; ty += ddy
            } else {
                z += sz; t = tz; tz += ddz
            }
        }
        return nil
    }

    private func dayNow() -> Double { CACurrentMediaTime() - startTime + dayOffset }

    private func dayNight() {
        let t = dayNow() / 480.0
        let s = Float(sin(t * 2 * Double.pi))
        let light = 0.62 + 0.38 * max(-0.2, s)
        let k = CGFloat(max(0, min(1, (s + 0.3) / 0.6)))
        let sky = UIColor(red: 0.07 + 0.46 * k, green: 0.09 + 0.69 * k, blue: 0.22 + 0.76 * k, alpha: 1)
        scene.background.contents = sky
        scene.fogColor = sky
        let mc = UIColor(white: CGFloat(light), alpha: 1)
        opaqueMat.multiply.contents = mc
        blendMat.multiply.contents = mc
        sun.light?.intensity = CGFloat(250 + 750 * max(0, s))
        amb.light?.intensity = CGFloat(250 + 350 * light)
    }

    // MARK: networking

    private func peerChanged(_ peer: MCPeerID, _ state: MCSessionState) {
        if state == .connected && !isHost && peer == net.joining {
            net.send(.hello(me), to: [peer])
        }
        if state == .notConnected {
            if isHost, let id = peerIds[peer] {
                let n = name(of: id)
                removeRemote(id)
                peerIds[peer] = nil
                net.send(.leave(id: id))
                showToast("\(n) is weggegaan")
            } else if !isHost && peer == net.joining {
                if world == nil {
                    onDisconnected?()
                } else {
                    showToast("Verbinding met het eiland verbroken")
                    for id in Array(remotes.keys) { removeRemote(id) }
                }
            }
        }
    }

    private func handle(_ m: Msg, from peer: MCPeerID) {
        switch m {
        case .hello(let info):
            guard info.id != me.id else { return }
            if isHost {
                peerIds[peer] = info.id
                let others = remotes.values.map { $0.info }.filter { $0.id != info.id }
                addRemote(info)
                net.send(.welcome(seed: world?.seed ?? 1, edits: world?.editList ?? [], players: [me] + others, dayTime: dayNow()), to: [peer])
                net.send(.hello(info), except: peer)
                if let it = tagIt {
                    net.send(.tag(itId: it, secondsLeft: tagEnd - CACurrentMediaTime(), message: ""), to: [peer])
                }
            } else {
                addRemote(info)
            }
            showToast("\(info.name) doet mee!")
        case let .welcome(seed, edits, players, dayTime):
            guard !isHost, world == nil else { return }
            dayOffset = dayTime - (CACurrentMediaTime() - startTime)
            for p in players where p.id != me.id { addRemote(p) }
            load(seed: seed, edits: edits)
        case let .state(id, x, y, z, yaw):
            if let r = remotes[id] {
                r.target = SIMD3<Float>(x, y, z)
                r.yaw = yaw
                if !r.hasPos {
                    r.hasPos = true
                    r.cur = r.target
                    r.node.isHidden = false
                }
            }
            if isHost { net.send(m, reliable: false, except: peer) }
        case .edit(let e):
            setBlock(e.x, e.y, e.z, Block(rawValue: e.b) ?? .air, broadcast: false)
            if isHost { net.send(m, except: peer) }
        case .leave(let id):
            if id == me.id { return }
            let n = name(of: id)
            removeRemote(id)
            showToast("\(n) is weggegaan")
        case let .tag(itId, secondsLeft, message):
            guard !isHost else { return }
            tagIt = itId
            tagEnd = CACurrentMediaTime() + secondsLeft
            updateTagMarks()
            if !message.isEmpty { showToast(message) }
        case let .tagged(by, target):
            if isHost { tagTransfer(by: by, to: target) }
        }
    }

    private func addRemote(_ info: PlayerInfo) {
        if remotes[info.id] == nil {
            let r = RemotePlayer(info: info)
            r.node.isHidden = true
            scene.rootNode.addChildNode(r.node)
            remotes[info.id] = r
        }
        refreshRoster()
        updateTagMarks()
    }

    private func removeRemote(_ id: String) {
        remotes[id]?.node.removeFromParentNode()
        remotes[id] = nil
        refreshRoster()
        if isHost && tagIt == id {
            let ids = [me.id] + Array(remotes.keys)
            if ids.count >= 2, let next = ids.randomElement() {
                tagIt = next
                let msg = "\(name(of: next)) is nu de tikker"
                net.send(.tag(itId: next, secondsLeft: tagEnd - CACurrentMediaTime(), message: msg))
                showToast(msg)
            } else {
                tagIt = nil
                net.send(.tag(itId: nil, secondsLeft: 0, message: ""))
            }
            updateTagMarks()
        }
    }

    private func refreshRoster() {
        roster = [me] + remotes.values.map { $0.info }.sorted { $0.name < $1.name }
    }

    private func name(of id: String) -> String {
        id == me.id ? me.name : (remotes[id]?.info.name ?? "Iemand")
    }

    // MARK: tag (tikkertje)

    var canStartTag: Bool { isHost && !remotes.isEmpty }

    func startTag() {
        guard isHost else { return }
        let ids = [me.id] + Array(remotes.keys)
        guard ids.count >= 2, let it = ids.randomElement() else {
            showToast("Voor tikkertje heb je minstens 2 spelers nodig")
            return
        }
        let now = CACurrentMediaTime()
        tagIt = it
        tagEnd = now + 120
        tagImmune = now + 3
        let msg = "Tikkertje! \(name(of: it)) is de tikker"
        net.send(.tag(itId: it, secondsLeft: 120, message: msg))
        showToast(msg)
        updateTagMarks()
    }

    private func tagTransfer(by: String, to: String) {
        let now = CACurrentMediaTime()
        guard tagIt == by, now >= tagImmune, by != to else { return }
        tagIt = to
        tagImmune = now + 3
        let msg = "\(name(of: by)) tikte \(name(of: to))!"
        net.send(.tag(itId: to, secondsLeft: tagEnd - now, message: msg))
        showToast(msg)
        updateTagMarks()
    }

    private func tagStep() {
        guard let it = tagIt else {
            if tagText != nil { tagText = nil }
            return
        }
        let now = CACurrentMediaTime()
        let left = tagEnd - now
        if left <= 0 {
            if isHost {
                let msg = "Tijd om! \(name(of: it)) was de tikker"
                tagIt = nil
                net.send(.tag(itId: nil, secondsLeft: 0, message: msg))
                showToast(msg)
                updateTagMarks()
            }
            return
        }
        let secs = Int(left.rounded(.up))
        let clock = String(format: "%d:%02d", secs / 60, secs % 60)
        let txt = (it == me.id ? "Jij bent de tikker! " : "\(name(of: it)) is de tikker · ") + clock
        if txt != tagText { tagText = txt }
        if it == me.id && now >= localTagCooldown {
            for r in remotes.values where r.hasPos && simd_distance(r.cur, pos) < 1.4 {
                localTagCooldown = now + 1
                if isHost {
                    tagTransfer(by: me.id, to: r.info.id)
                } else if let host = net.joining {
                    net.send(.tagged(by: me.id, target: r.info.id), to: [host])
                }
                break
            }
        }
    }

    private func updateTagMarks() {
        for r in remotes.values { r.node.setTagged(r.info.id == tagIt) }
        myAvatar.setTagged(me.id == tagIt)
    }

    // MARK: misc

    func showToast(_ s: String) {
        toast = s
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: w)
    }

    private static var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("eiland.json")
    }

    func saveWorld() {
        guard isHost, let w = world else { return }
        if let data = try? JSONEncoder().encode(SavedWorld(seed: w.seed, edits: w.editList)) {
            try? data.write(to: GameController.saveURL, options: .atomic)
        }
    }

    static func loadSaved() -> SavedWorld? {
        guard let data = try? Data(contentsOf: saveURL) else { return nil }
        return try? JSONDecoder().decode(SavedWorld.self, from: data)
    }
}
