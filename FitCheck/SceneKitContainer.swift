import SwiftUI
import SceneKit
import GLTFKit2
import ObjectiveC
import simd
import CoreImage

// MARK: — SwiftUI wrapper
struct SceneKitContainer: UIViewControllerRepresentable {
    let avatarURL: String
    let environment: String
    @ObservedObject var measurements: AvatarMeasurements
    @Binding var avatarGender: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }
     class Coordinator {
         var parent: SceneKitContainer
         init(_ parent: SceneKitContainer) { self.parent = parent }
     }
    
    func makeUIViewController(context: Context) -> GLBSceneViewController {
       let vc = GLBSceneViewController(
            avatarURL:    avatarURL,
            environment:  environment,
            measurements: measurements
        )
        vc.onGenderDetermined = { gender in
                    DispatchQueue.main.async {
                        context.coordinator.parent.avatarGender = gender
                    }
                }
                return vc
    }

    func updateUIViewController(_ vc: GLBSceneViewController, context: Context) {
        vc.update(environment: environment, measurements: measurements)
    }
}

// MARK: — store bind‑pose scales
private var kOrigScaleKey: UInt8 = 0
extension SCNNode {
    /// Persistent copy of the node’s bind‑pose scale (used for measurement resets).
    var origScale: SCNVector3 {
        get {
            (objc_getAssociatedObject(self, &kOrigScaleKey) as? NSValue)?
                .scnVector3Value ?? scale
        }
        set {
            objc_setAssociatedObject(
                self,
                &kOrigScaleKey,
                NSValue(scnVector3: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

/// Returns the first descendant that carries a geometry (or the node itself if it already has one).
private func firstGeomNode(in root: SCNNode) -> SCNNode? {
    if root.geometry != nil { return root }
    for child in root.childNodes {
        if let hit = firstGeomNode(in: child) { return hit }
    }
    return nil
}


// MARK: — Main view‑controller
final class GLBSceneViewController: UIViewController, SCNSceneRendererDelegate {
    // inputs
    private var worn: [GarmentKind: SCNNode] = [:]
    private let avatarURL: String
    private var environment: String
    private var measurements: AvatarMeasurements
    var onGenderDetermined: ((String) -> Void)?

    // SceneKit
    private let scnView = SCNView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var armatureNode: SCNNode?

    init(avatarURL: String, environment: String, measurements: AvatarMeasurements) {
        self.avatarURL    = avatarURL
        self.environment  = environment
        self.measurements = measurements
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureSceneView()
        configureSpinner()
        loadAvatar()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playRuntimeAnimation(_:)),
            name: .animationSelected,
            object: nil
        )
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(onClothingSelected(_:)),
          name: .clothingSelected,
          object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onResetAvatar),
            name: .resetAvatar,           // ← new
            object: nil)

        // STEP C – textures
        GarmentTextureApplier.shared.register(self)

        // 🆕 listen for Wear taps
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onClothingSelected(_:)),
            name: .clothingSelected,
            object: nil
        )
    }

    /* -------------------------------------------------------------------- */
    @objc private func onClothingSelected(_ note: Notification) {
        print("📥 clothingSelected notification received:", note.object as Any)
        guard let item = note.object as? ClothingItem else {
          print("⚠️ clothingSelected payload was not a ClothingItem")
          return
        }
        applyClothing(item)
    }

    func update(environment: String, measurements: AvatarMeasurements) {
        self.environment  = environment
        self.measurements = measurements
        applyEnvironment()
        applyMeasurements()
    }

    // MARK: — scene + lighting
    private func configureSceneView() {
        scnView.frame = view.bounds
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.isPlaying = true                // ← keep SceneKit ticking
        scnView.delegate = self
        view.addSubview(scnView)

        let scene = SCNScene()
        scnView.scene = scene

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.position = SCNVector3(0,0,10)
        scene.rootNode.addChildNode(cam)

        [SCNLight.LightType.ambient, .directional].forEach { type in
            let ln = SCNNode()
            let l  = SCNLight()
            l.type      = type
            l.intensity = 1_000
            ln.light    = l
            if type == .directional {
                ln.eulerAngles.x = -.pi/4
            }
            scene.rootNode.addChildNode(ln)
        }
    }

    private func configureSpinner() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        spinner.startAnimating()
    }

    var avatarGender = "female"
    
    private func loadAvatar() {
        guard let url = URL(string: avatarURL) else { return }
        GLTFAsset.load(with: url, options: [:]) { [weak self] _, _, asset, err, _ in
            guard let self = self, let asset = asset else {
                print("❌ Avatar load failed:", err ?? "unknown")
                return
            }

            let scene    = SCNScene(gltfAsset: asset)
            let meshRoot = scene.rootNode.childNodes.first ?? scene.rootNode

            // 1️⃣ orientation wrapper (+π/2 around X)
            let orient = SCNNode()
            orient.position       = meshRoot.position
            meshRoot.position     = SCNVector3Zero
            orient.addChildNode(meshRoot)

            // 2️⃣ alias “Armature”
            let arm = SCNNode()
            arm.name = "Armature"
            arm.addChildNode(orient)

            // 3️⃣ retarget skinner → alias
            if let sk = meshRoot.skinner {
                sk.skeleton = arm
            }

            // 4️⃣ capture bind‑pose scales on alias
            self.captureBindPose(on: arm)
            self.armatureNode = arm

            // 5️⃣ dispatch back to main thread for SceneKit updates
            DispatchQueue.main.async {
                self.scnView.scene = scene
                scene.rootNode.addChildNode(arm)
                self.applyEnvironment()
                self.applyMeasurements()
                self.spinner.stopAnimating()

                // ─── DETECT GENDER BY BBOX RATIO ────────────────────────────
                let (bbMin, bbMax) = arm.boundingBox
                let width  = bbMax.x - bbMin.x    // shoulder‑width
                let height = bbMax.y - bbMin.y    // total avatar height
                let ratio  = width / height
                self.avatarGender = (ratio > 0.55) ? "male" : "female"
                print("🔍 inferred gender (w/h = \(ratio)) →", self.avatarGender)
                // ────────────────────────────────────────────────────────────
                
                self.onGenderDetermined?(self.avatarGender)
                
                self.playIdleAnimation()
            }
            //  after the avatar is finished loading  (inside loadAvatar → DispatchQueue.main.async)
            if let saved = UserDefaults.standard.dictionary(forKey: savedOutfitKey) as? [String:String] {
                for (k, asset) in saved {
                    guard
                        let kind = GarmentKind(rawValue: k),
                        !asset.isEmpty
                    else { continue }
                    
                    // spin up a *minimal* ClothingItem that only carries what applyClothing needs
                    let stub = ClothingItem(
                        id: UUID().uuidString,
                        title: asset,
                        imageUrl: "",
                        colorHex:"",
                        frontURL: nil,
                        backURL: nil,
                        assetURL: asset,
                        kind: kind,
                        availableSizes: [])
                    
                    applyClothing(stub)          // reuse your existing logic 🔄
                }
            }
        }
    }

    private func captureBindPose(on node: SCNNode) {
        node.origScale = node.scale
        node.childNodes.forEach(captureBindPose)
    }

    // MARK: — background
    private func applyEnvironment() {
        guard let scene = scnView.scene else { return }
        switch environment {
        case "Office": scene.setBackground(named: "office.jpg")
        case "School": scene.setBackground(named: "school.jpg")
        default:       scene.background.contents = UIColor.white
        }
    }


//    private func color(from hex: String?) -> UIColor? {
//        guard var h = hex?.trimmingCharacters(in: .whitespacesAndNewlines)
//                           .replacingOccurrences(of: "#", with: "")
//              else { return nil }
//
//        switch h.count {
//        case 3:   // expand #RGB ➜ #RRGGBB
//            h = h.map { "\($0)\($0)" }.joined()
//        case 8:   // ignore alpha ➜ drop last two characters
//            h = String(h.prefix(6))
//        case 6:   break                        // OK
//        default:  return nil                   // unsupported
//        }
//
//        guard let v = Int(h, radix: 16) else { return nil }
//
//        return UIColor(
//            red:   CGFloat((v >> 16) & 0xFF) / 255,
//            green: CGFloat((v >>  8) & 0xFF) / 255,
//            blue:  CGFloat( v        & 0xFF) / 255,
//            alpha: 1
//        )
//    }

    
    // ------------------------------------------------------------------
    //  helper : return this node + every descendant that owns a geometry
    // ------------------------------------------------------------------
    private func meshes(in n: SCNNode) -> [SCNNode] {
        var m: [SCNNode] = []
        if n.geometry != nil { m.append(n) }
        n.childNodes.forEach { m.append(contentsOf: meshes(in:$0)) }
        return m
    }

    private let savedOutfitKey = "SavedOutfit"
    
    // ------------------------------------------------------------------
    //  applyClothing – swaps every ReadyPlayerMe mesh in the outfit slot
    //  with the corresponding mesh from the selected GLB.  The GLB mesh
    //  keeps its own skinner, but all bone references are re‑wired (and
    //  kept in the *same order*) to the live Armature so animation works.
    // ------------------------------------------------------------------
    private func applyClothing(_ item: ClothingItem) {

        guard let rig = armatureNode else { return }

        // 1️⃣ which slot?
        let slotName: String = {
            switch item.kind {
            case .top, .other:  return "Wolf3D_Outfit_Top"
            case .bottom:       return "Wolf3D_Outfit_Bottom"
            case .shoes:        return "Wolf3D_Outfit_Footwear"
            }
        }()
        guard let slot = rig.childNode(withName: slotName, recursively: true) else {
            print("❌ slot \(slotName) not found"); return
        }
        slot.isHidden = false

        // 2️⃣ RPM meshes we’ll replace
        let rpmMeshes = meshes(in: slot)
        guard !rpmMeshes.isEmpty else {
            print("⚠️ \(slotName) has no meshes"); return
        }

        // 3️⃣ load GLB
        guard
            let p      = item.assetURL,
            let url    = p.contains("://")
                         ? URL(string: p)
                         : Bundle.main.url(forResource: p.deletingPathExtension,
                                           withExtension: p.pathExtension),
            let asset  = try? GLTFAsset(url: url),
            let root   = SCNScene(gltfAsset: asset).rootNode.childNodes.first
        else { print("❌ could not load", item.assetURL ?? "<nil>"); return }

        let glbMeshes = meshes(in: root)
        print("— GLB inspection —")
        for m in glbMeshes {
            let geo      = m.geometry
            let vCount   = geo?.sources(for: .vertex).first?.vectorCount ?? 0
            let skinned  = m.skinner != nil
            print(" • \(m.name ?? "<no‑name>")  verts:", vCount,
                  "skinned:", skinned)
        }
        print("────────────────────")

        guard !glbMeshes.isEmpty else {
            print("⚠️ \(url.lastPathComponent) has no meshes"); return
        }

        // 4️⃣ pair up
        let pairs = min(rpmMeshes.count, glbMeshes.count)
        guard pairs > 0 else {
            print("⚠️ mesh count mismatch (RPM \(rpmMeshes.count) ≠ GLB \(glbMeshes.count))")
            return
        }

        // 5️⃣ swap
        for i in 0 ..< pairs {

            let dst = rpmMeshes[i]          // RPM node (already animated)
            let src = glbMeshes[i]          // GLB mesh to graft in

            //---------------- geometry ---------------------------
            dst.geometry            = src.geometry?.copy() as? SCNGeometry
            dst.geometry?.materials = src.geometry?.materials ?? []

//            if let base = color(from: item.colorHex) {
//
//                // 1️⃣ boost saturation (×1.5 capped at 1.0)
//                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
//                base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
//                let boosted = UIColor(hue: h,
//                                      saturation: min(1.0, s * 1.5),
//                                      brightness: b,
//                                      alpha: 1.0)          // keep α = 1, we’ll dial strength below
//
//                // 2️⃣ how “strong” the overlay should be (0 = none, 1 = full)
//                let strength: CGFloat = 1              // ✏️ tweak this until it looks right
//
//                for mat in dst.geometry?.materials ?? [] {
//
//                    // textured meshes → Multiply overlay keeps texture detail
//                    if mat.diffuse.contents is UIImage {
//                        mat.multiply.contents  = boosted
//                        mat.multiply.intensity = strength   // < 1 ⇒ not opaque
//                    }
//
//                    // un‑textured meshes → tint via diffuse with reduced alpha
//                    else {
//                        mat.diffuse.contents = boosted.withAlphaComponent(strength)
//                    }
//                }
//            }

            //---------------- fresh skinner ----------------------
            if let srcSkin = src.skinner?.copy() as? SCNSkinner {

                srcSkin.skeleton = rig       // live Armature

                // **keep bone list length & order**
                if let oldBones = srcSkin.value(forKey: "bones") as? [SCNNode] {
                    var newBones: [SCNNode] = []
                    newBones.reserveCapacity(oldBones.count)

                    for b in oldBones {
                        if let name = b.name,
                           let live = rig.childNode(withName: name, recursively: true)
                        {
                            newBones.append(live)
                        } else {
                            // fallback: keep original so index count stays identical
                            newBones.append(b)
                        }
                    }
                    srcSkin.setValue(newBones, forKey: "bones")
                }

                dst.skinner = srcSkin
            } else {
                dst.skinner = nil    // shouldn’t happen, but avoids crash
            }
        }

        // remove leftovers if GLB had fewer meshes
        if rpmMeshes.count > glbMeshes.count {
            for idx in glbMeshes.count ..< rpmMeshes.count {
                rpmMeshes[idx].removeFromParentNode()
            }
        }

        print("✅ \(slotName) replaced with", url.lastPathComponent)
        
        if let asset = item.assetURL {
            var dict = UserDefaults.standard.dictionary(forKey: savedOutfitKey) as? [String:String] ?? [:]
            dict[item.kind.rawValue] = asset
            UserDefaults.standard.setValue(dict, forKey: savedOutfitKey)
        }
    }


    // MARK: – safe SIMD3 loader (12‑byte vertices)
    @inline(__always)
    private func readSIMD3(from raw: UnsafeRawPointer,
                           dataStride: Int,
                           dataOffset: Int) -> SIMD3<Float> {
        let x = raw.load(fromByteOffset: dataOffset,               as: Float.self)
        let y = raw.load(fromByteOffset: dataOffset + 4,           as: Float.self)
        let z = raw.load(fromByteOffset: dataOffset + 8,           as: Float.self)
        return SIMD3<Float>(x, y, z)
    }
    
    @objc private func onResetAvatar() {
        resetOutfit()
        // if you also need to download a brand‑new avatar, call loadAvatar() here
    }
    
    func resetOutfit() {
        // 1. forget what was stored in UserDefaults
        UserDefaults.standard.removeObject(forKey: savedOutfitKey)

        // 2. delete every garment we previously grafted on
        worn.values.forEach { $0.removeFromParentNode() }
        worn.removeAll()
    }
    
    func applyProcessedGarment(_ g: ProcessedGarment) {
      guard let rig = armatureNode else { return }

      // 0) remove last one of this kind
      if let old = worn[g.kind] {
        old.removeFromParentNode()
        worn[g.kind] = nil
      }

      // 1) build front/back materials
      let matF = SCNMaterial()
      matF.diffuse.contents = UIImage(contentsOfFile: g.frontPNG.path)
      let matB = SCNMaterial()
      matB.diffuse.contents = UIImage(contentsOfFile: g.backPNG.path)
      [matF, matB].forEach {
        $0.isDoubleSided = false
        $0.readsFromDepthBuffer = false
        $0.writesToDepthBuffer  = false
      }

      // 2) pick the right “container” node name for this kind
      let outfitName: String
      switch g.kind {
        case .top:    outfitName = "Wolf3D_Outfit_Top"
        case .bottom: outfitName = "Wolf3D_Outfit_Bottom"
        case .shoes:  outfitName = "Wolf3D_Outfit_Footwear"
        default:      outfitName = ""
      }

      // 3) if the real mesh exists, override it in place
      if !outfitName.isEmpty,
         let outfitContainer = rig.childNode(withName: outfitName, recursively: true) {
        
        // make sure the container is visible
        outfitContainer.isHidden = false

        // swap every geometry under that container
        outfitContainer.enumerateChildNodes { node, _ in
          guard let geom = node.geometry else { return }
          // front/back only matters for top & bottom; for shoes we just use front
          let newMat = (g.kind == .bottom) ? matB : matF
          geom.materials = [ newMat ]
          node.renderingOrder = 10
        }

        // remember so we can remove or replace it next time
        worn[g.kind] = outfitContainer
        return
      }

      // 4) FALLBACK → paint cylinders on the Wolf3D_Body
      guard let body = rig
              .childNode(withName: "Wolf3D_Body", recursively: true),
            let baseGeomNode = firstGeomNode(in: body),
            let baseGeo     = baseGeomNode.geometry
      else {
        return
      }

      // hide the underlying body so our cylinder shows through
      baseGeomNode.isHidden = true

      let clipY = (g.kind == .bottom)
      let (geoF, geoB) = buildCylindricalGeometries(from: baseGeo, clipY: clipY)
      geoF.materials = [matF]
      geoB.materials = [matB]

      // clone two cylinder meshes
      let frontNode = clone(baseGeomNode, with: geoF)
      let backNode  = clone(baseGeomNode, with: geoB)
      frontNode.renderingOrder = 10
      backNode.renderingOrder  = 10

      rig.addChildNode(frontNode)
      rig.addChildNode(backNode)

      // remember the front node so we can remove it later
      worn[g.kind] = frontNode
    }



    /// Hide just the original Wolf3D_<Kind> that you’ve over-painted
    private func hideRPMClothes(kind: GarmentKind) {
        guard let rig = armatureNode else { return }
        let nameToHide: String
        switch kind {
        case .top:    nameToHide = "Wolf3D_Outfit_Top"
        case .bottom: nameToHide = "Wolf3D_Outfit_Bottom"
        case .shoes:  nameToHide = "Wolf3D_Outfit_Footwear"
        default:      return
        }
        rig.childNode(withName: nameToHide, recursively: true)?
            .isHidden = true
    }
    
    private func buildCylindricalGeometries(from src: SCNGeometry, clipY: Bool = false)
    -> (front: SCNGeometry, back: SCNGeometry)
    {
        // fetch sources
        guard let vSrc = src.sources(for: .vertex).first,
              let nSrc = src.sources(for: .normal).first,
              let idx  = src.elements.first else { return (src,src) }

        let vStride = vSrc.dataStride
        let vOffset = vSrc.dataOffset
        let nStride = nSrc.dataStride
        let nOffset = nSrc.dataOffset

        let verts  = vSrc.data as NSData
        let norms  = nSrc.data as NSData

        // bounding box → cylinder radius & height
        var bbMin = SIMD3<Float>( repeating:  .greatestFiniteMagnitude)
        var bbMax = SIMD3<Float>( repeating: -.greatestFiniteMagnitude)   // <-- fix
        
        for i in 0..<vSrc.vectorCount {
            let base = i * vStride + vOffset
            let v = readSIMD3(from: verts.bytes, dataStride: vStride, dataOffset: base)
            bbMin = min(bbMin, v)
            bbMax = max(bbMax, v)
        }
        
        let halfWidth    = (bbMax.x - bbMin.x) * 0.5         // shoulder span / 2
        let torsoRadius  = halfWidth * 0.8
        
        let centerXZ = SIMD2<Float>((bbMin.x + bbMax.x)/2,
                                    (bbMin.z + bbMax.z)/2)
        var height = bbMax.y - bbMin.y
        
        let yMin = bbMin.y
            let yMax = clipY ? min(bbMax.y, bbMin.y + height*0.55)   // crop at ~55 % of body
                             : bbMax.y
            height = yMax - yMin

        // storage
        var fUVs: [simd_float2] = Array(repeating: .zero, count: vSrc.vectorCount)
        var bUVs: [simd_float2] = Array(repeating: .zero, count: vSrc.vectorCount)
        var fIndices: [UInt32]  = []
        var bIndices: [UInt32]  = []

        // iterate triangles
        let triCount = idx.primitiveCount
        for t in 0..<triCount {
            let base = t * 3
            var fKeep = false, bKeep = false
            var tri: [UInt32] = []
            for j in 0..<3 {
                let vid = idx.index(base + j)
                tri.append(vid)

                // decide front/back from normal.z (model space)
                let nPtr = norms.bytes.advanced(by: Int(vid)*nStride + nOffset)
                let nz   = nPtr.load(as: Float.self)

                // torso gate: ignore vertices that are too far out in X → they belong to sleeves
                // for each vertex of the triangle
                let vPtr = verts.bytes.advanced(by: Int(vid)*vStride + vOffset)
                let vx   = vPtr.load(as: Float.self)
                let vz   = vPtr.load(fromByteOffset: 8, as: Float.self)   // z component
                let vy = vPtr.load(fromByteOffset: 4, as: Float.self)
                
                // cylindrical coords
                let dx = vx - centerXZ.x
                let dz = vz - centerXZ.y
                let angle = atan2(dx, dz)          //  −π … π   0 ≡ front

                let torso = abs(vx - centerXZ.x) < torsoRadius       // 18 cm side‑radius
                let isFront = (angle > -.pi/2 && angle < .pi/2)
                let inWaistBand = !clipY || vy <= yMax
                
                fKeep = fKeep || ( isFront &&  torso && inWaistBand)
                bKeep = bKeep || (!isFront &&  torso && inWaistBand)

                // compute UV once
                if fUVs[Int(vid)] == .zero && bUVs[Int(vid)] == .zero {
                    let _ = verts.bytes.advanced(by: Int(vid)*vStride + vOffset)
                    let v = readSIMD3(from: verts.bytes,
                                      dataStride: vStride,
                                      dataOffset: Int(vid) * vStride + vOffset)
                    // cylindrical coords
                    let dx = v.x - centerXZ.x, dz = v.z - centerXZ.y
                    let angle = atan2(dx, dz)   // −π … π (0 = front)
                    let uCyl = (angle + .pi) / (2 * .pi)   // 0 … 1
                    let vCyl = 1 - (v.y - yMin) / height
                    if nz >= 0 {
                        fUVs[Int(vid)] = simd_float2(uCyl, vCyl)
                    } else {
                        bUVs[Int(vid)] = simd_float2(1 - uCyl, vCyl) // flip
                    }
                }
            }
            if fKeep { fIndices.append(contentsOf: tri) }
            if bKeep { bIndices.append(contentsOf: tri) }
        }
        print("🔷 front tris:", fIndices.count/3,
              "back tris:",    bIndices.count/3)

        func makeGeo(indices: [UInt32], uvs: [simd_float2]) -> SCNGeometry {
            let uvData = Data(bytes: uvs, count: uvs.count * MemoryLayout<simd_float2>.size)
            let uvSrc  = SCNGeometrySource(data: uvData,
                                           semantic: .texcoord,
                                           vectorCount: uvs.count,
                                           usesFloatComponents: true,
                                           componentsPerVector: 2,
                                           bytesPerComponent: MemoryLayout<Float>.size,
                                           dataOffset: 0,
                                           dataStride: MemoryLayout<simd_float2>.size)

            let idxData = Data(bytes: indices, count: indices.count * 4)
            let elm = SCNGeometryElement(data: idxData,
                                         primitiveType: .triangles,
                                         primitiveCount: indices.count/3,
                                         bytesPerIndex: 4)
            var sources = src.sources     // copy position/normal/skin
            sources.append(uvSrc)         // add texcoord
            return SCNGeometry(sources: sources, elements: [elm])
        }

        return ( makeGeo(indices: fIndices, uvs: fUVs),
                 makeGeo(indices: bIndices, uvs: bUVs) )
    }
    
    // MARK: – avatar sizing
    private func applyMeasurements() {
        guard let rig = armatureNode else { return }
        resetScales(rig)

        func softenedScale(_ raw: Float) -> Float {
            let clamped = max(0.8, min(raw, 1.2))
            return 1 + (clamped - 1) * 0.25        }

        func factor(value: Float, base: Float) -> Float {
            softenedScale(value / base)
        }

        func walk(_ node: SCNNode) {
            // skip the wrapper alias itself
            if node.name?.lowercased() == "armature" { node.childNodes.forEach(walk); return }

            let name = node.name?.lowercased() ?? ""
            var scaleFactor: Float = 1        // default – no change

            switch true {
            case name == "hips":
                scaleFactor = factor(value: measurements.hip,    base: 100)

            case name.contains("spine2"):          // upper‑torso / chest
                scaleFactor = factor(value: measurements.chest,  base:  95)

            case name.contains("spine1"):          // mid‑torso / waist
                scaleFactor = factor(value: measurements.waist,  base:  85)

            case name.contains("spine"):           // fallback for any other spine piece
                let avg = (measurements.chest + measurements.waist + measurements.hip) / 3
                scaleFactor = factor(value: avg,   base:  90)

            case name.contains("arm"),
                 name.contains("forearm"),
                 name.contains("shoulder"),
                 name.contains("hand"):
                scaleFactor = factor(value: measurements.sleeveLength, base: 60)

            case name.contains("leg"),
                 name.contains("foot"),
                 name.contains("toe"):
                scaleFactor = factor(value: measurements.inseam, base: 80)

            default:
                break
            }

            // apply factor uniformly on xyz
            let o = node.origScale
            node.scale = SCNVector3(o.x * scaleFactor,
                                    o.y * scaleFactor,
                                    o.z * scaleFactor)

            node.childNodes.forEach(walk)
        }

        walk(rig)
    }


    private func resetScales(_ node: SCNNode) {
        node.scale = node.origScale
        node.childNodes.forEach(resetScales)
    }

    // MARK: — animation
    private func playIdleAnimation() {
        print("gender is:",avatarGender)
      let clip = (avatarGender == "female")
        ? "Idle_female"
        : "Idle_male"
      loadAnimation(named: clip, ext: "dae", prefix: "idle")
    }

    @objc private func playRuntimeAnimation(_ note: Notification) {
        guard let url = note.object as? URL else { return }
        loadAnimation(from: url, prefix: "run")
    }

    private func loadAnimation(named name: String,
                               ext:   String,
                               prefix: String)
    {
        guard let _ = armatureNode,
              let url = Bundle.main.url(forResource: name, withExtension: ext)
        else { return }
        loadAnimation(from: url, prefix: prefix)
    }
    
    private func targetNodes(for kind: GarmentKind, in rig: SCNNode) -> [SCNNode] {
        // grab the body first (for your cylindrical fallback)
        let body = rig.childNode(withName: "Wolf3D_Body", recursively: true)!
        
        switch kind {
        case .top:
          if let outfitTop = rig
            .childNode(withName: "Wolf3D_Outfit_Top", recursively: true)
          {
            return [outfitTop]
          } else {
            return [body]
          }
            
        case .bottom:
          // try to find the built-in pants node, and only fall back to body if it isn’t there:
          if let outfitBot = rig
            .childNode(withName: "Wolf3D_Outfit_Bottom", recursively: true)
          {
            return [outfitBot]
          } else {
            // no real pants mesh? then paint the body-cylinder
            return [body]
          }
            
        case .shoes:
            // footwear node
            let outfitShoe = rig
              .childNode(withName: "Wolf3D_Outfit_Footwear", recursively: true)
            return outfitShoe.map { [$0] } ?? []
            
        default:
            return []
        }
    }

    private func clone(_ src: SCNNode, with geo: SCNGeometry) -> SCNNode {
        let n = SCNNode(geometry: geo)
        n.transform = src.transform      // ← copy position/rotation/scale
        if let sk = src.skinner?.copy() as? SCNSkinner {
            n.skinner = sk
        }
        return n
    }

    private func loadAnimation(from url: URL, prefix: String) {
        guard let rig = armatureNode else { return }
        resetScales(rig)

        // **only DAE** → raw CAAnimations
        guard url.pathExtension.lowercased() == "dae",
              let src = SCNSceneSource(url: url, options: nil)
        else { return }

        let ids = src.identifiersOfEntries(withClass: CAAnimation.self)
        rig.removeAllAnimations()
        for id in ids {
            guard let ca = src.entryWithIdentifier(id, withClass: CAAnimation.self)
            else { continue }
            ca.repeatCount = .infinity
            let player = SCNAnimationPlayer(animation: SCNAnimation(caAnimation: ca))
            player.animation.repeatCount = .infinity
            rig.addAnimationPlayer(player, forKey: "\(prefix)_\(id)")
            player.play()
        }
        applyMeasurements()
    }
}

// MARK: — background helper
extension SCNScene {
    func setBackground(named name: String) {
        if let img = UIImage(named: name) {
            lightingEnvironment.contents = img
            background.contents         = img
        }
    }
    func firstNodeWithAnimation() -> SCNNode? {
        func walk(_ n: SCNNode) -> SCNNode? {
            if !n.animationKeys.isEmpty { return n }
            for c in n.childNodes {
                if let r = walk(c) { return r }
            }
            return nil
        }
        return walk(rootNode)
    }
}

extension GLBSceneViewController{
    func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
        applyMeasurements()
    }
}

extension UIImage {

    /// Finds the dominant colour (not average) of the centre patch of a remote image.
    /// Calls `done` on the **main queue** with the detected colour or `nil` on failure.
    static func dominantColor(
        from urlString: String,
        done: @escaping (UIColor?) -> Void)
    {
        guard let url = URL(string: urlString) else { return done(nil) }

        DispatchQueue.global(qos: .userInitiated).async {
            guard
                let data = try? Data(contentsOf: url),
                let ui   = UIImage(data: data),
                let cg   = ui.cgImage
            else { return DispatchQueue.main.async { done(nil) } }

            // ── centre crop (40 % × 40 %) ────────────────────────────────
            let w = cg.width, h = cg.height
            let cropRect = CGRect(x: Int(Double(w) * 0.30),
                                  y: Int(Double(h) * 0.30),
                                  width:  Int(Double(w) * 0.40),
                                  height: Int(Double(h) * 0.40))
            guard let cgCrop = cg.cropping(to: cropRect)            else {
                return DispatchQueue.main.async { done(nil) }
            }

            // ── scale to 64×64 px into a raw RGBA buffer ────────────────
            let side = 64
            let bytesPerRow = side * 4
            guard
                let ctx = CGContext(data: nil,
                                    width: side,
                                    height: side,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return DispatchQueue.main.async { done(nil) } }

            ctx.interpolationQuality = .low
            ctx.draw(cgCrop, in: CGRect(x: 0, y: 0, width: side, height: side))

            guard let buf = ctx.data else { return DispatchQueue.main.async { done(nil) } }
            let pix = buf.bindMemory(to: UInt8.self, capacity: side * side * 4)

            // ── 5‑bit‑per‑channel histogram (32 K buckets) ──────────────
            var hist: [UInt32 : Int] = [:]
            hist.reserveCapacity(4096)

            for i in 0 ..< side*side {
                let o  = i << 2
                let r5 = pix[o]     >> 3           // 0…31
                let g5 = pix[o + 1] >> 3
                let b5 = pix[o + 2] >> 3
                let key = (UInt32(r5) << 10) | (UInt32(g5) << 5) | UInt32(b5)
                hist[key, default: 0] += 1
            }

            guard let (key, _) = hist.max(by: { $0.value < $1.value }) else {
                return DispatchQueue.main.async { done(nil) }
            }

            // expand 5‑bit back to 8‑bit  (x << 3 | x >> 2)
            func up(_ v: UInt32) -> UInt8 { UInt8((v << 3) | (v >> 2)) }

            let r8 = up((key >> 10) & 0x1F)
            let g8 = up((key >>  5) & 0x1F)
            let b8 = up( key        & 0x1F)

            let col = UIColor(red:   CGFloat(r8) / 255.0,
                              green: CGFloat(g8) / 255.0,
                              blue:  CGFloat(b8) / 255.0,
                              alpha: 1)

            DispatchQueue.main.async { done(col) }
        }
    }
}

private extension String {
    var pathExtension: String {
        (self as NSString).pathExtension
    }
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}
private extension SCNVector3 {
    static var zero: SCNVector3 { SCNVector3(0,0,0) }
    static func +(l:SCNVector3, r:SCNVector3) -> SCNVector3 {
        SCNVector3(l.x+r.x, l.y+r.y, l.z+r.z)
    }
    static func *(v:SCNVector3, s:Float) -> SCNVector3 {
        SCNVector3(v.x*s, v.y*s, v.z*s)
    }
}
