// GarmentProcessor.swift
import Foundation
import UIKit
import Vision

@MainActor
final class GarmentProcessor {
    
    static let shared = GarmentProcessor()
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePending(_:)),
            name: .pendingGarmentReady,
            object: nil
        )
    }
    
    // MARK: – Step B entry‑point
    @objc private func handlePending(_ note: Notification) {
        guard let g = note.object as? PendingGarment else { return }
        Task.detached(priority: .utility) {
            if let processed = await self.process(g) {
                NotificationCenter.default.post(name: .garmentTexturesReady,
                                                object: processed)
            }
        }
    }
    
    // MARK: – Pipeline
    private func process(_ g: PendingGarment) async -> ProcessedGarment? {
        do {
            let (frontJPEG, backJPEG) = try await download(front: g.frontURL,
                                                           back:  g.backURL)
            let frontPNG = try await cutMat(from: frontJPEG)
            let backPNG  = try await cutMat(from: backJPEG)
            let ready = ProcessedGarment(asin: g.asin,
                                         kind: g.kind,
                                         frontPNG: frontPNG,
                                         backPNG:  backPNG)
            await MainActor.run {
                NotificationCenter.default.post(name: .garmentTexturesReady,
                                                object: ready)
            }
            return ready          // return value isn’t used, but keeps signature

        } catch {
            print("❌ Step B failed for \(g.asin):", error)
            return nil
        }
    }
}

private func download(front: URL, back: URL) async throws -> (URL,URL) {
    try await withThrowingTaskGroup(of: URL.self) { group in
        var urls: [URL] = []
        for src in [front, back] {
            group.addTask { try await fetch(src) }
        }
        for try await local in group { urls.append(local) }
        guard urls.count == 2 else { throw URLError(.badServerResponse) }
        return (urls[0], urls[1])
    }
}

private func fetch(_ remote: URL) async throws -> URL {
    let (data,_) = try await URLSession.shared.data(from: remote)
    let name = remote.lastPathComponent
    let dst  = FileManager.default.cachesDirectory
                .appendingPathComponent("FitCheck_Raw")
                .appendingPathComponent(name)
    try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try data.write(to: dst); return dst
}

private func cutMat(from jpegURL: URL) async throws -> URL {

    guard let srcImg = UIImage(contentsOfFile: jpegURL.path),
          let cg     = srcImg.cgImage else {
        throw CocoaError(.fileReadCorruptFile)
    }
    
    // ---------- 1. try Vision foreground mask (iOS 17+) ----------
    // 1. Vision first
    var alphaMask: CIImage?
    if #available(iOS 17, *),
       let mask = try? generateVisionMask(for: cg) {
        alphaMask = mask
    }

    // 2. fallback – white key tuned for Amazon images
    if alphaMask == nil {
        alphaMask = whiteBGMask(from: cg)
    }
    
    // ---------- 3. composite & write PNG -------------------------
    let ciSrc = CIImage(cgImage: cg).oriented(forExifOrientation: 1)
    let ciOut: CIImage

    if let mask = alphaMask {
        // ❶ make the mask an alpha channel
        let alpha = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])

        // ❷ transparent background with same extent
        let blank = CIImage(color: .clear).cropped(to: ciSrc.extent)

        // ❸ blend src over transparent bg using the alpha mask
        ciOut = ciSrc.applyingFilter("CIBlendWithAlphaMask",
                                     parameters: ["inputBackgroundImage": blank,
                                                  "inputMaskImage":       alpha])
    } else {
        // last‑ditch: opaque pass‑through
        ciOut = ciSrc
        print("⚠️  No alpha mask produced – saving opaque PNG")
    }

    let ctx = CIContext()
    guard let png = ctx.pngRepresentation(of: ciOut,
                                          format: .RGBA8,
                                          colorSpace: CGColorSpaceCreateDeviceRGB())
    else { throw NSError(domain: "PNGEncoding", code: -2) }
    
    let dst = FileManager.default.cachesDirectory
        .appendingPathComponent("FitCheck_Textures")
        .appendingPathComponent(UUID().uuidString + ".png")
    try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try png.write(to: dst)
    
    return dst
}

//  GarmentProcessor.swift
@available(iOS 17, *)
private func generateVisionMask(for cg: CGImage) throws -> CIImage? {

    let req = VNGenerateForegroundInstanceMaskRequest()
    req.revision = VNGenerateForegroundInstanceMaskRequestRevision1
    try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])

    guard let obs = req.results?.first else { return nil }
    let obj = obs as AnyObject

    // try every getter method Apple has used
    for selName in ["allInstancesMaskPixelBuffer",
                    "maskPixelBuffer",
                    "pixelBuffer"] {
        let sel = NSSelectorFromString(selName)
        if obj.responds(to: sel),
           let unret = obj.perform(sel) {
            let buf = unret.takeUnretainedValue() as! CVPixelBuffer
            return CIImage(cvPixelBuffer: buf)
        }
    }
    return nil                     // Vision mask unavailable
}

private func whiteBGMask(from cg: CGImage) -> CIImage {
    let ci = CIImage(cgImage: cg)

    // Convert to luminance   (sRGB → Y)
    let y   = ci.applyingFilter("CIColorControls",
                                parameters:[kCIInputSaturationKey: 0])

    // Threshold ≈ 0.93 picks pure / near‑pure white
    let thr = y.applyingFilter("CIThresholdToAlpha",
                               parameters:["inputThreshold": 0.93])

    // Invert so white → 0, shirt → 1
    return thr.applyingFilter("CIColorInvert")
}

private func quickWhiteKeyMask(from cg: CGImage) -> CIImage? {
    let ci = CIImage(cgImage: cg)
    
    // 1. convert to linear RGB & grab luminance + saturation
    let sat = ci.applyingFilter("CIColorControls", parameters: [
        kCIInputSaturationKey: 0.0          // grayscale
    ])
    
    // 2. threshold:  white = luma > 0.9  AND  sat < 0.05
    let thresh = sat.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputBiasVector": CIVector(x: -0.9, y: -0.9, z: -0.9, w: 0)
    ]).applyingFilter("CIThresholdToAlpha")
    
    // invert so foreground = opaque (1), background = 0
    return thresh.applyingFilter("CIColorInvert")
}

extension FileManager {
    /// User‑cache folder:  ~/Library/Caches
    var cachesDirectory: URL {
        urls(for: .cachesDirectory, in: .userDomainMask).first!
    }
}
