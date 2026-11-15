import SceneKit

private struct Face {
    let dx: Int, dy: Int, dz: Int
    let n: SCNVector3
    let c: [(Float, Float, Float)]
    let shade: Float
}

// Corners are counter-clockwise seen from outside; corners 1 and 2 are the "top" edge for side faces.
private let faces: [Face] = [
    Face(dx: 1, dy: 0, dz: 0, n: SCNVector3(1, 0, 0), c: [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)], shade: 0.8),
    Face(dx: -1, dy: 0, dz: 0, n: SCNVector3(-1, 0, 0), c: [(0, 0, 1), (0, 1, 1), (0, 1, 0), (0, 0, 0)], shade: 0.8),
    Face(dx: 0, dy: 1, dz: 0, n: SCNVector3(0, 1, 0), c: [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)], shade: 1.0),
    Face(dx: 0, dy: -1, dz: 0, n: SCNVector3(0, -1, 0), c: [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)], shade: 0.55),
    Face(dx: 0, dy: 0, dz: 1, n: SCNVector3(0, 0, 1), c: [(1, 0, 1), (1, 1, 1), (0, 1, 1), (0, 0, 1)], shade: 0.7),
    Face(dx: 0, dy: 0, dz: -1, n: SCNVector3(0, 0, -1), c: [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)], shade: 0.7),
]

private struct MeshData {
    var verts: [SCNVector3] = []
    var norms: [SCNVector3] = []
    var uvs: [CGPoint] = []
    var cols: [Float] = []
    var idx: [Int32] = []

    func geometry(_ material: SCNMaterial) -> SCNGeometry? {
        if idx.isEmpty { return nil }
        let colData = cols.withUnsafeBufferPointer { Data(buffer: $0) }
        let colSrc = SCNGeometrySource(data: colData, semantic: .color, vectorCount: verts.count,
                                       usesFloatComponents: true, componentsPerVector: 3,
                                       bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                       dataStride: MemoryLayout<Float>.size * 3)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms),
                                      SCNGeometrySource(textureCoordinates: uvs), colSrc],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        g.materials = [material]
        return g
    }
}

enum Mesher {
    /// Builds the opaque and the see-through (glass/water) mesh for one 16x16 chunk column.
    static func build(world: World, cx: Int, cz: Int, opaque: SCNMaterial, blend: SCNMaterial) -> (SCNGeometry?, SCNGeometry?) {
        var o = MeshData(), t = MeshData()
        o.verts.reserveCapacity(16000)
        for y in 0..<WY {
            for z in (cz * CS)..<(cz * CS + CS) {
                for x in (cx * CS)..<(cx * CS + CS) {
                    let b = world.get(x, y, z)
                    if b == .air { continue }
                    let waterTop = b == .water && world.get(x, y + 1, z) != .water
                    for (fi, f) in faces.enumerated() {
                        let nb = world.get(x + f.dx, y + f.dy, z + f.dz)
                        if !(nb.isTransparent && nb != b) { continue }
                        if b == .water && nb != .air { continue }
                        if b.usesBlend { addFace(&t, f, fi, b, x, y, z, waterTop) } else { addFace(&o, f, fi, b, x, y, z, waterTop) }
                    }
                }
            }
        }
        return (o.geometry(opaque), t.geometry(blend))
    }

    private static func addFace(_ m: inout MeshData, _ f: Face, _ fi: Int, _ b: Block, _ x: Int, _ y: Int, _ z: Int, _ waterTop: Bool) {
        let (u0, u1) = Atlas.u(b.tile(fi))
        let base = Int32(m.verts.count)
        for (k, c) in f.c.enumerated() {
            let cy: Float = (c.1 == 1 && waterTop) ? 0.88 : c.1
            m.verts.append(SCNVector3(Float(x) + c.0, Float(y) + cy, Float(z) + c.2))
            m.norms.append(f.n)
            let u = (k == 2 || k == 3) ? u1 : u0
            let v: Float = (k == 1 || k == 2) ? 0 : 1
            m.uvs.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
            m.cols.append(f.shade); m.cols.append(f.shade); m.cols.append(f.shade)
        }
        m.idx.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
    }
}
