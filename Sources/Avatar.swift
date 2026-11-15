import SceneKit
import UIKit

struct PlayerInfo: Codable, Hashable {
    var id: String
    var name: String
    var shirt: Int
    var pants: Int
    var skin: Int
}

enum Palette {
    static func c(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    static let shirts: [UIColor] = [0xE53935, 0x1E88E5, 0x43A047, 0xFDD835, 0x8E24AA, 0xFB8C00, 0x00ACC1, 0xEC407A].map(Palette.c)
    static let pants: [UIColor] = [0x283593, 0x37474F, 0x4E342E, 0x2E7D32, 0x212121, 0x6D4C41].map(Palette.c)
    static let skins: [UIColor] = [0xFFDBB5, 0xF1C27D, 0xE0AC69, 0xC68642, 0x8D5524].map(Palette.c)
    static func shirt(_ i: Int) -> UIColor { shirts[abs(i) % shirts.count] }
    static func pant(_ i: Int) -> UIColor { pants[abs(i) % pants.count] }
    static func skin(_ i: Int) -> UIColor { skins[abs(i) % skins.count] }
}

/// Blocky character with swinging arms and legs and a floating name tag.
final class AvatarNode: SCNNode {
    let info: PlayerInfo
    private let legL = SCNNode(), legR = SCNNode(), armL = SCNNode(), armR = SCNNode()
    private let plate = SCNNode()
    private var phase: Float = 0
    private var swing: Float = 0

    init(info: PlayerInfo) {
        self.info = info
        super.init()
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func mat(_ c: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = c
        m.lightingModel = .lambert
        return m
    }

    private func part(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ c: UIColor) -> SCNNode {
        let b = SCNBox(width: w, height: h, length: l, chamferRadius: 0.02)
        b.materials = [mat(c)]
        return SCNNode(geometry: b)
    }

    private func build() {
        let shirt = Palette.shirt(info.shirt), pants = Palette.pant(info.pants), skin = Palette.skin(info.skin)
        for (node, x) in [(legL, Float(-0.13)), (legR, Float(0.13))] {
            node.position = SCNVector3(x, 0.7, 0)
            let p = part(0.24, 0.7, 0.26, pants)
            p.position = SCNVector3(0, -0.35, 0)
            node.addChildNode(p)
            addChildNode(node)
        }
        let body = part(0.56, 0.66, 0.3, shirt)
        body.position = SCNVector3(0, 1.03, 0)
        addChildNode(body)
        for (node, x) in [(armL, Float(-0.39)), (armR, Float(0.39))] {
            node.position = SCNVector3(x, 1.33, 0)
            let p = part(0.2, 0.56, 0.22, shirt)
            p.position = SCNVector3(0, -0.26, 0)
            node.addChildNode(p)
            let hand = part(0.19, 0.12, 0.2, skin)
            hand.position = SCNVector3(0, -0.6, 0)
            node.addChildNode(hand)
            addChildNode(node)
        }
        let head = part(0.46, 0.46, 0.46, skin)
        head.position = SCNVector3(0, 1.6, 0)
        addChildNode(head)
        for x in [Float(-0.1), Float(0.1)] {
            let e = part(0.07, 0.09, 0.02, .black)
            e.position = SCNVector3(x, 0.05, -0.235)
            head.addChildNode(e)
        }
        let mouth = part(0.16, 0.03, 0.02, UIColor(white: 0.15, alpha: 1))
        mouth.position = SCNVector3(0, -0.1, -0.235)
        head.addChildNode(mouth)
        plate.position = SCNVector3(0, 2.15, 0)
        plate.constraints = [SCNBillboardConstraint()]
        addChildNode(plate)
        setTagged(false)
    }

    func setTagged(_ it: Bool) {
        let img = AvatarNode.label(it ? "\(info.name) · TIKKER" : info.name,
                                   it ? UIColor.systemRed : UIColor(white: 0, alpha: 0.55))
        let p = SCNPlane(width: img.size.width / img.size.height * 0.32, height: 0.32)
        let m = SCNMaterial()
        m.diffuse.contents = img
        m.lightingModel = .constant
        m.isDoubleSided = true
        p.materials = [m]
        plate.geometry = p
    }

    func animate(speed: Float, dt: Float) {
        let target = min(speed / 4, 1)
        swing += (target - swing) * min(1, dt * 8)
        phase += dt * 9 * max(swing, 0.15)
        let a = sin(phase) * 0.7 * swing
        legL.eulerAngles.x = a
        legR.eulerAngles.x = -a
        armL.eulerAngles.x = -a
        armR.eulerAngles.x = a
    }

    static func label(_ text: String, _ bg: UIColor) -> UIImage {
        let font = UIFont.systemFont(ofSize: 40, weight: .heavy)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let w = ceil(size.width) + 40, h: CGFloat = 64
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { _ in
            bg.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 18).fill()
            (text as NSString).draw(at: CGPoint(x: 20, y: (h - size.height) / 2),
                                    withAttributes: [.font: font, .foregroundColor: UIColor.white])
        }
    }
}
