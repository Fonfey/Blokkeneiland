import UIKit

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
}

enum Block: UInt8, CaseIterable, Codable {
    case air = 0, grass, dirt, stone, sand, log, leaves, planks, glass, brick, water, gold, snow, red, blue, yellow, bedrock

    var name: String {
        switch self {
        case .air: return "Lucht"
        case .grass: return "Gras"
        case .dirt: return "Aarde"
        case .stone: return "Steen"
        case .sand: return "Zand"
        case .log: return "Boomstam"
        case .leaves: return "Bladeren"
        case .planks: return "Planken"
        case .glass: return "Glas"
        case .brick: return "Baksteen"
        case .water: return "Water"
        case .gold: return "Goud"
        case .snow: return "Sneeuw"
        case .red: return "Rood"
        case .blue: return "Blauw"
        case .yellow: return "Geel"
        case .bedrock: return "Bodemsteen"
        }
    }

    var isSolid: Bool { self != .air && self != .water }
    var isTransparent: Bool { self == .air || self == .glass || self == .water || self == .leaves }
    var usesBlend: Bool { self == .glass || self == .water }

    static let placeable: [Block] = [.grass, .dirt, .stone, .planks, .log, .brick, .glass, .sand, .leaves, .gold, .snow, .red, .blue, .yellow, .water]

    /// Atlas tile for a face direction (0:+X 1:-X 2:+Y 3:-Y 4:+Z 5:-Z)
    func tile(_ dir: Int) -> Int {
        switch self {
        case .grass: return dir == 2 ? 0 : (dir == 3 ? 2 : 1)
        case .dirt: return 2
        case .stone: return 3
        case .sand: return 4
        case .log: return (dir == 2 || dir == 3) ? 6 : 5
        case .leaves: return 7
        case .planks: return 8
        case .glass: return 9
        case .brick: return 10
        case .water: return 11
        case .gold: return 12
        case .snow: return 13
        case .red: return 14
        case .blue: return 15
        case .yellow: return 16
        case .bedrock: return 17
        case .air: return 0
        }
    }
}

/// Procedurally drawn pixel-art texture atlas: one row of 16x16 tiles.
enum Atlas {
    static let count = 18
    static let px = 16
    static let cgImage: CGImage = build()
    static let image: UIImage = UIImage(cgImage: cgImage)
    static let tileImages: [UIImage] = (0..<count).map { t in
        if let c = cgImage.cropping(to: CGRect(x: t * px, y: 0, width: px, height: px)) { return UIImage(cgImage: c) }
        return UIImage()
    }

    static func u(_ t: Int) -> (Float, Float) {
        let w = Float(count * px)
        return ((Float(t * px) + 0.08) / w, (Float(t * px + px) - 0.08) / w)
    }

    private static func build() -> CGImage {
        let w = count * px, h = px
        var data = [UInt8](repeating: 0, count: w * h * 4)
        var rng = SplitMix(seed: 42)
        for t in 0..<count {
            for y in 0..<h {
                for x in 0..<px {
                    let n = Int(rng.next() % 25) - 12
                    let r = rng.unit()
                    let (c, a) = color(t, x, y, n, r)
                    let i = (y * w + t * px + x) * 4
                    data[i] = UInt8(max(0, min(255, c.0)))
                    data[i + 1] = UInt8(max(0, min(255, c.1)))
                    data[i + 2] = UInt8(max(0, min(255, c.2)))
                    data[i + 3] = UInt8(a)
                }
            }
        }
        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func color(_ t: Int, _ x: Int, _ y: Int, _ n: Int, _ r: Double) -> ((Int, Int, Int), Int) {
        func g(_ cr: Int, _ cg: Int, _ cb: Int) -> (Int, Int, Int) { (cr + n, cg + n, cb + n) }
        switch t {
        case 0: return (g(96, 168, 64), 255)
        case 1: return (y < 3 || (y == 3 && x % 3 != 1)) ? (g(96, 168, 64), 255) : (g(134, 96, 67), 255)
        case 2: return (g(134, 96, 67), 255)
        case 3: return (r < 0.08 ? g(92, 92, 96) : g(128, 128, 130), 255)
        case 4: return (g(220, 208, 152), 255)
        case 5: return (x % 4 == 0 ? g(84, 60, 36) : g(110, 80, 50), 255)
        case 6:
            let dx = Double(x) - 7.5, dy = Double(y) - 7.5
            let d = Int((dx * dx + dy * dy).squareRoot())
            return (d % 3 == 0 ? g(120, 88, 54) : g(168, 132, 86), 255)
        case 7: return (r < 0.2 ? g(40, 96, 36) : g(64, 138, 52), 255)
        case 8:
            let seam = (y / 4) % 2 == 0 ? 0 : 8
            return ((y % 4 == 3 || x == seam) ? g(128, 96, 58) : g(186, 146, 94), 255)
        case 9:
            let edge = x == 0 || y == 0 || x == 15 || y == 15
            let shine = (x + y == 10 || x + y == 12) && x > 2 && x < 10
            if edge { return ((222, 238, 250), 235) }
            return shine ? ((250, 252, 255), 150) : ((200, 228, 250), 55)
        case 10:
            let row = y / 4
            let mortar = y % 4 == 3 || (x + (row % 2) * 4) % 8 == 7
            return (mortar ? (204, 198, 188) : g(170, 70, 52), 255)
        case 11: return (g(52, 112, 206), 175)
        case 12: return (r < 0.1 ? (255, 245, 170) : g(236, 194, 52), 255)
        case 13: return ((240 + n / 3, 246 + n / 3, 252 + n / 3), 255)
        case 14: return (g(196, 52, 46), 255)
        case 15: return (g(52, 92, 196), 255)
        case 16: return (g(232, 200, 52), 255)
        default: return (g(52, 52, 56), 255)
        }
    }
}
