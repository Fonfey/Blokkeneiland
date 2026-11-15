import Foundation

let WX = 96, WY = 40, WZ = 96, CS = 16

struct Edit: Codable, Hashable {
    var x: Int
    var y: Int
    var z: Int
    var b: UInt8
}

final class World {
    let seed: UInt32
    private(set) var blocks: [UInt8]
    private(set) var edits: [Int: UInt8] = [:]
    let water = 11

    init(seed: UInt32) {
        self.seed = seed
        blocks = [UInt8](repeating: 0, count: WX * WY * WZ)
        generate()
    }

    @inline(__always) func index(_ x: Int, _ y: Int, _ z: Int) -> Int { (y * WZ + z) * WX + x }
    @inline(__always) func inside(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        x >= 0 && y >= 0 && z >= 0 && x < WX && y < WY && z < WZ
    }

    func get(_ x: Int, _ y: Int, _ z: Int) -> Block {
        guard inside(x, y, z) else { return .air }
        return Block(rawValue: blocks[index(x, y, z)]) ?? .air
    }

    /// Solid for collisions; the world edge acts as an invisible wall.
    func solid(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        if x < 0 || z < 0 || x >= WX || z >= WZ || y < 0 { return true }
        if y >= WY { return false }
        return get(x, y, z).isSolid
    }

    func set(_ x: Int, _ y: Int, _ z: Int, _ b: Block, record: Bool = true) {
        guard inside(x, y, z) else { return }
        let i = index(x, y, z)
        blocks[i] = b.rawValue
        if record { edits[i] = b.rawValue }
    }

    func apply(_ list: [Edit]) {
        for e in list { set(e.x, e.y, e.z, Block(rawValue: e.b) ?? .air) }
    }

    var editList: [Edit] {
        edits.map { item in
            let i = item.key
            return Edit(x: i % WX, y: i / (WX * WZ), z: (i / WX) % WZ, b: item.value)
        }
    }

    /// Highest non-air block (water counts) in a column.
    func top(_ x: Int, _ z: Int) -> Int {
        var y = WY - 1
        while y > 0 && get(x, y, z) == .air { y -= 1 }
        return y
    }

    // MARK: noise

    private func hash(_ x: Int, _ z: Int, _ salt: UInt32 = 0) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 374761393 &+ z &* 668265263) &+ (seed &+ salt) &* 2246822519
        h = (h ^ (h >> 13)) &* 1274126177
        h ^= h >> 16
        return Float(h) / 4294967295.0
    }

    private func noise(_ x: Float, _ z: Float, _ salt: UInt32) -> Float {
        let xi = Int(floor(x)), zi = Int(floor(z))
        let fx = x - Float(xi), fz = z - Float(zi)
        let sx = fx * fx * (3 - 2 * fx), sz = fz * fz * (3 - 2 * fz)
        let a = hash(xi, zi, salt), b = hash(xi + 1, zi, salt)
        let c = hash(xi, zi + 1, salt), d = hash(xi + 1, zi + 1, salt)
        let top = a + (b - a) * sx
        let bottom = c + (d - c) * sx
        return top + (bottom - top) * sz
    }

    private func fbm(_ x: Float, _ z: Float) -> Float {
        var amp: Float = 0.5, f: Float = 1, sum: Float = 0
        for o in 0..<4 {
            sum += noise(x * f, z * f, UInt32(o) * 101) * amp
            amp *= 0.5
            f *= 2
        }
        return sum / 0.9375
    }

    private func generate() {
        var heights = [Int](repeating: 0, count: WX * WZ)
        for z in 0..<WZ {
            for x in 0..<WX {
                let n = fbm(Float(x) / 26, Float(z) / 26)
                let dx = Float(x - WX / 2) / Float(WX / 2), dz = Float(z - WZ / 2) / Float(WZ / 2)
                let d = min(1.2, (dx * dx + dz * dz).squareRoot())
                var h = Int(6 + n * 22 - d * d * 12)
                h = max(2, min(WY - 8, h))
                heights[z * WX + x] = h
                for y in 0...max(h, water) {
                    let b: Block
                    if y == 0 { b = .bedrock }
                    else if y < h - 3 { b = hash(x * 7 + y, z * 13 - y, 77) > 0.985 ? .gold : .stone }
                    else if y < h { b = h <= water + 1 ? .sand : .dirt }
                    else if y == h { b = h <= water + 1 ? .sand : (h >= 26 ? .snow : .grass) }
                    else { b = .water }
                    set(x, y, z, b, record: false)
                }
            }
        }
        // trees
        for z in 3..<(WZ - 3) {
            for x in 3..<(WX - 3) {
                let h = heights[z * WX + x]
                guard get(x, h, z) == .grass, hash(x, z, 999) > 0.982 else { continue }
                let th = 4 + Int(hash(z, x, 5) * 2)
                for y in 1...th { set(x, h + y, z, .log, record: false) }
                let top = h + th
                for ly in (top - 2)...(top + 1) {
                    let r = ly > top ? 1 : 2
                    for lz in -r...r {
                        for lx in -r...r {
                            if abs(lx) == r && abs(lz) == r && hash(x + lx, z + lz + ly, 3) > 0.4 { continue }
                            if get(x + lx, ly, z + lz) == .air { set(x + lx, ly, z + lz, .leaves, record: false) }
                        }
                    }
                }
            }
        }
    }
}
