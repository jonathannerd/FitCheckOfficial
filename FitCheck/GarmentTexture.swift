import Foundation
import SceneKit
import UIKit

/// Step C: listens to the processed‑textures notification and asks SceneKit to apply them.
@MainActor
final class GarmentTextureApplier {
    
    static let shared = GarmentTextureApplier()
    private init() {                // start listening
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onTextures(_:)),
            name: .garmentTexturesReady,
            object: nil
        )
    }
    
    /// Weak table: every live scene controller that can dress an avatar registers here.
    private var targets = NSHashTable<AnyObject>.weakObjects()
    
    func register(_ vc: GLBSceneViewController) {
        targets.add(vc)
    }
    
    // ————————————————————————————
    
    @objc private func onTextures(_ note: Notification) {
        guard let g = note.object as? ProcessedGarment else { return }
        Task { @MainActor in
            for case let vc as GLBSceneViewController in targets.allObjects {
                vc.applyProcessedGarment(g)
            }
        }
    }
}
