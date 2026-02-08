import SceneKit

extension SCNGeometryElement {
    /// Returns the *i‑th* index as `UInt32`, handling 1‑, 2‑ or 4‑byte index formats.
    func index(_ i: Int) -> UInt32 {
        let stride = bytesPerIndex
        return data.withUnsafeBytes { raw in
            let offset = i * stride
            switch stride {
            case 1:
                let val = raw.load(fromByteOffset: offset, as: UInt8.self)
                return UInt32(val)
            case 2:
                let val = raw.load(fromByteOffset: offset, as: UInt16.self)
                return UInt32(val)
            default:            // 4 bytes (SceneKit won’t emit 8‑byte indices)
                return raw.load(fromByteOffset: offset, as: UInt32.self)
            }
        }
    }
}
