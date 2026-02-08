import Foundation

struct FitAdvisor {
    static func bestSize(for item: ClothingItem,
                         user: AvatarMeasurements) -> ClothingItem.SizeSpec? {
        for s in item.availableSizes {
            if let c = s.chest, !(c.contains(user.chest)) { continue }
            if let w = s.waist, !(w.contains(user.waist)) { continue }
            if let h = s.hip,   !(h.contains(user.hip))   { continue }
            return s
        }
        return nil
    }
}
    struct Entry {
        let assetURL: String
        let sizes:    [ClothingItem.SizeSpec]
    }
    
    private let table: [String : Entry] = [:
    ]
    
    func lookupAsset(forASIN asin: String) -> Entry? { table[asin] }


extension Notification.Name {
    static let pendingGarmentReady   = Notification.Name("pendingGarmentReady")
    static let garmentTexturesReady  = Notification.Name("garmentTexturesReady")
}


/// Produced by Step A (you already have this)
struct PendingGarment {
    let asin:     String
    let kind:     GarmentKind        // .top / .bottom / .shoes / .other
    let frontURL: URL                // guaranteed JPEG
    let backURL:  URL
}

/// Produced by Step B → consumed by Step C
struct ProcessedGarment {
    let asin:     String
    let kind:     GarmentKind
    let frontPNG: URL                // local transparent PNG
    let backPNG:  URL
}
