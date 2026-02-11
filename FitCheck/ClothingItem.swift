import Foundation
import Combine
import UIKit

// ── Amazon PA‑API models ────────────────────────────────────────────────

struct AmazonSearchResponse: Codable {
    struct SearchResult: Codable { let Items: [AmazonItem]? }
    let SearchResult: SearchResult?
}

// MARK: - Images branch that matches CA payload
struct AmazonItem: Codable {
    let ASIN: String

    struct ItemInfo: Codable {
        struct Title: Codable { let DisplayValue: String }
        let Title: Title
    }
    let ItemInfo: ItemInfo

    struct Images: Codable {

        struct Primary: Codable {
            struct Medium: Codable { let URL: String }
            let Medium: Medium         // ← always present
        }
        let Primary: Primary

        // Variants is an *array* (index 0,1,2…) that carries Large images
        struct Variant: Codable {
            struct Large: Codable { let URL: String }
            let Large: Large
        }
        let Variants: [Variant]?
    }
    let Images: Images
}

extension AmazonItem {
    /// Try to pull two distinct Large images from Variants (index‑0 = front,
    /// index‑1 = back on most listings). Returns nil if we have < 2 pictures.
    func frontBackURLs() -> (URL, URL)? {
        guard let vars = self.Images.Variants, vars.count >= 2 else { return nil }
        if let f = URL(string: vars[0].Large.URL),
           let b = URL(string: vars[1].Large.URL) {
            return (f, b)
        }
        return nil
    }
}

// ── Local catalog for ready‑made 3‑D garments ────────────────

enum GarmentKind: String, Codable { case top, bottom, shoes, other }

struct ClothingItem: Identifiable, Codable {
    let id:       String
    let title:    String
    let imageUrl: String
    var colorHex: String?

    let frontURL: String?
    let backURL:  String?

    let assetURL: String?
    let kind:     GarmentKind
    let availableSizes: [SizeSpec]
    
    struct SizeSpec: Codable {
        let label: String
        let chest: ClosedRange<Float>?
        let waist: ClosedRange<Float>?
        let hip:   ClosedRange<Float>?
    }
}

//  LocalCatalog.swift
struct LocalCatalog {
    static let shared = LocalCatalog()

    struct Entry {
        let asset : String
        let kind  : GarmentKind
        let sizes : [ClothingItem.SizeSpec]
    }

    /// Each keyword bucket maps *many* synonyms to one GLB file
    private let buckets: [(synonyms: [String], entry: Entry)] = [

        // ---------- TOPS ----------
        (["t‑shirt", "tee", "t shirt"],
            Entry(asset: "tshirt.glb",
                  kind:  .top,
                  sizes: [])),
        (["sweater", "pullover", "jumper", "hoodie","sweatshirt"],
            Entry(asset: "sweater.glb",
                  kind:  .top,
                  sizes: [])),
        (["jacket", "blazer", "suit"],           // suits, blazers, etc.
            Entry(asset: "suit.glb",
                  kind:  .top,
                  sizes: [])),
        (["coat", "overcoat", "parka"],          // COAT
            Entry(asset: "coat.glb",
                  kind:  .top,
                  sizes: [])),

        // ---------- BOTTOMS ----------
        (["jean", "denim"],
            Entry(asset: "jeans.glb",
                  kind:  .bottom,
                  sizes: [])),
        (["slim jean", "skinny jean"],
            Entry(asset: "slim_jeans.glb",
                  kind:  .bottom,
                  sizes: [])),
        (["dress pant", "chino", "trouser"],
            Entry(asset: "dress_pants.glb",
                  kind:  .bottom,
                  sizes: [])),
        (["cargo pant", "cargo pants", "cargo"],  // CARGO PANTS
            Entry(asset: "cargo_pants.glb",
                  kind:  .bottom,
                  sizes: [])),

        // ---------- SHOES ----------
        (["sneaker", "runner", "trainer"],
            Entry(asset: "sneakers.glb",
                  kind:  .shoes,
                  sizes: [])),
        (["running shoe", "running sneaker", "running"],  // RUNNING SHOES
            Entry(asset: "running_shoes.glb",
                  kind:  .shoes,
                  sizes: [])),
        (["boot"],
            Entry(asset: "boots.glb",
                  kind:  .shoes,
                  sizes: [])),
        (["dress shoe", "oxford", "loafer"],
            Entry(asset: "dress_shoes.glb",
                  kind:  .shoes,
                  sizes: []))
    ]

    func lookup(by title: String) -> Entry? {

        let needles = tokens(from: title)
        guard !needles.isEmpty else { return nil }

        return buckets.first { bucket in
            bucket.synonyms.contains { syn in
                let key = tokens(from: syn).first!
                return needles.contains(key) ||
                       needles.contains(key + "s")
            }
        }?.entry
    }
}

// 1️⃣ lowercase, strip diacritics
private func normalise(_ s: String) -> String {
    s.lowercased()
     .folding(options: .diacriticInsensitive, locale: .current)
}

// 2️⃣ break a string into clean word tokens
private func tokens(from s: String) -> [String] {
    normalise(s)
        .components(separatedBy: CharacterSet.alphanumerics.inverted) // <‑ splits at .,‑/…
        .filter { !$0.isEmpty }
}

//  MARK: dominant colour (centre 30 % × 30 %) – keeps black & white,
//        ignores greys, no saturation/brightness “help”.
func dominantHexSync(from urlString: String) -> String? {

    guard let url  = URL(string: urlString),
          let data = try? Data(contentsOf: url, options: .mappedIfSafe),
          let ui   = UIImage(data: data),
          let cg   = ui.cgImage
    else { return nil }

    // ── centre crop (30 % × 30 %) ──────────────────────────────
    let w = cg.width, h = cg.height
    let crop = cg.cropping(to: CGRect(x: Int(Double(w)*0.35),
                                      y: Int(Double(h)*0.35),
                                      width:  Int(Double(w)*0.30),
                                      height: Int(Double(h)*0.30))) ?? cg

    // ── 48 × 48 down‑sampling ─────────────────────────────────
    let side = 48, bytesPerRow = side*4
    guard let ctx = CGContext(data: nil,
                              width: side, height: side,
                              bitsPerComponent: 8,
                              bytesPerRow: bytesPerRow,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    ctx.interpolationQuality = .low
    ctx.draw(crop, in: CGRect(x:0, y:0, width:side, height:side))

    guard let buf = ctx.data else { return nil }
    let pix = buf.bindMemory(to: UInt8.self, capacity: side*side*4)

    // ── histogram on *valid* pixels only ──────────────────────
    var hist: [UInt32:Int] = [:]
    hist.reserveCapacity(2048)

    for i in 0 ..< side*side {
        let o = i<<2
        let r = CGFloat(pix[o  ]) / 255.0
        let g = CGFloat(pix[o+1]) / 255.0
        let b = CGFloat(pix[o+2]) / 255.0
        
        // RGB → HSV
        var h:CGFloat = 0, s:CGFloat = 0, v:CGFloat = 0
        UIColor(red:r, green:g, blue:b, alpha:1).getHue(&h, saturation:&s, brightness:&v, alpha:nil)
        
        // accept:
        //   • pure dark (v ≤ 0.25)              → black
        //   • pure light (v ≥ 0.85)             → white
        //   • coloured  (s ≥ 0.20)              → vivid colours
        guard v <= 0.25 || v >= 0.85 || s >= 0.20 else { continue }
        
        // 5‑bit histogram key (r5 g5 b5)
        // inside the pixel loop
        let r5 = UInt32(pix[o    ] >> 3)   // 0…31
        let g5 = UInt32(pix[o + 1] >> 3)
        let b5 = UInt32(pix[o + 2] >> 3)
        
        let key = (r5 << 10) | (g5 << 5) | b5   // 5‑bit RGB packed into 15 bits
        hist[key, default: 0] += 1
    }
    
    

    guard let (key, _) = hist.max(by: {$0.value < $1.value}) else { return nil }

    func up(_ v: UInt32) -> UInt8 { UInt8((v<<3)|(v>>2)) }
    let r8 = up((key>>10)&0x1F), g8 = up((key>>5)&0x1F), b8 = up(key&0x1F)

    return String(format:"#%02X%02X%02X", r8, g8, b8)
}

// ---------------------------------------------------------------
//  Quick, synchronous average‑colour sampler ->  #RRGGBB string
// ---------------------------------------------------------------
func dominantHex(
    from urlString: String,
    completion: @escaping (String?) -> Void
) {
    // ---------- validate URL ----------
    guard let url = URL(string: urlString) else {
        DispatchQueue.main.async { completion(nil) }
        return
    }

    // ---------- grab data off‑thread ----------
    URLSession.shared.dataTask(with: url) { data, _, _ in
        guard
            let bytes = data,
            let uiImg = UIImage(data: bytes),
            let cgImg = uiImg.cgImage
        else {
            return DispatchQueue.main.async { completion(nil) }
        }

        // ---------- 1 × 1 average via CoreImage ----------
        let ciImg = CIImage(cgImage: cgImg)
        let extent = ciImg.extent
        let area = CIVector(cgRect: extent)

        let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [kCIInputImageKey : ciImg,
                         kCIInputExtentKey: area]
        )!

        let ctx = CIContext()
        guard
            let output = filter.outputImage,
            let bmp = ctx.createCGImage(output,
                                        from: CGRect(x:0, y:0, width:1, height:1)),
            let px = bmp.dataProvider?.data
        else {
            return DispatchQueue.main.async { completion(nil) }
        }

        let p = CFDataGetBytePtr(px)!       // RGBA
        let hex = String(format:"#%02X%02X%02X", p[0], p[1], p[2])

        // ---------- back to UI thread ----------
        DispatchQueue.main.async { completion(hex) }

    }.resume()
}


// ── Amazon search view‑model ────────────────────────────────────────────
/// When PA‑API replies with an error the JSON looks like { "Errors":[ … ] }
private struct PAErrorResponse: Codable {
    struct PAError: Codable { let Code: String; let Message: String }
    let Errors: [PAError]
}


@MainActor
final class ClothingSearchViewModel: ObservableObject {
    @Published var items: [ClothingItem] = []
    
    // MARK: creds
    private let partnerTag = "partnerTag"
    private let accessKey  = "accessKey"
    private let secretKey  = "secretKey"
    private let lastQueryKey = "LastSearchQuery"
    
    init() {
        if let q = UserDefaults.standard.string(forKey: lastQueryKey) {
            // trigger a search once we’re on the main run‑loop
            Task { await MainActor.run { self.search(for: q) } }
        }
    }
    
    // MARK: public API
    func search(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
        
        guard let body = buildRequestBody(for: query),
              var req  = makeSignedRequest(body: body)          else { return }
        
        req.httpBody = body
        
        URLSession.shared.dataTask(with: req) { [weak self] data, response, err in
            guard let self else { return }
            
            if let http = response as? HTTPURLResponse {
                print("HTTP", http.statusCode)
                if let reqID = http.allHeaderFields["x-amzn-RequestId"] {
                    print("x-amzn-RequestId:", reqID)
                }
            }
            if let err { print("PA‑API network error:", err); return }
            guard let data else { return }
            
            do {
                let ok = try JSONDecoder().decode(AmazonSearchResponse.self, from: data)
                
                // ✅ got items
                if let items = ok.SearchResult?.Items, !items.isEmpty {
                    Task { @MainActor in self.items = self.mapItems(items) }
                    return
                }
                
                // 🟡 empty list  → dump payload once for debugging
                print("🟡 PA‑API empty list – raw payload follows ↓↓↓")
                if let pretty = try? JSONSerialization.jsonObject(with: data) {
                    print(pretty)
                }
                
            } catch {
                // try to read structured Errors first
                if let errPayload = try? JSONDecoder().decode(PAErrorResponse.self, from: data) {
                    errPayload.Errors.forEach {
                        print("❌ PA‑API error: \($0.Code) – \($0.Message)")
                    }
                } else {
                    print("❌ JSON decode failed:", error,
                          "\nRaw payload:", String(decoding: data, as: UTF8.self))
                }
            }
        }.resume()
        UserDefaults.standard.setValue(trimmed, forKey: lastQueryKey)
    }
    
    private func buildRequestBody(for query: String) -> Data? {
        let obj: [String: Any] = [
            "Keywords"    : query,
            "SearchIndex" : "Apparel",          // ← specific CA index
            "ItemCount"   : 10,
            "PartnerTag"  : partnerTag,
            "PartnerType" : "Associates",
            "Marketplace" : "www.amazon.ca",
            "Resources"   : [
                "Images.Primary.Medium",
                "ItemInfo.Title"
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: obj)
    }
    
    private func makeSignedRequest(body: Data) -> URLRequest? {
        guard let url = URL(string: "https://webservices.amazon.ca/paapi5/searchitems")
        else { return nil }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody   = body
        
        // headers that must be present *and* signed
        req.setValue("amz-1.0", forHTTPHeaderField: "Content-Encoding")
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(url.host!, forHTTPHeaderField: "Host")
        req.setValue("com.amazon.paapi5.v1.ProductAdvertisingAPIv1.SearchItems",
                     forHTTPHeaderField: "x-amz-target")
        
        // add x‑amz‑date, x‑amz‑content‑sha256 & Authorization
        amazonSigV4Headers(url: url,
                           body: body,
                           accessKey: accessKey,
                           secretKey: secretKey)
        .forEach { key, value in
            req.setValue(value, forHTTPHeaderField: key)
        }
        
        return req
    }
    
    // MARK: - broad kind detection  (replace the whole method with this)
    nonisolated private func mapItems(_ src: [AmazonItem]) -> [ClothingItem] {
        
        // ── keyword buckets used only when we have no local asset ──────────
        let shoeWords   = ["shoe","sneaker","runner","trainer","boot","loafer",
                           "oxford","heel","sandal","slipper","moccasin",
                           "flip flop","flip‑flop","slides","pump","cleat",
                           "football boot","basketball shoe","skate shoe",
                           "espadrille"]
        let bottomWords = ["pant","pants","trouser","chino","denim","jean",
                           "skinny","slim","short","shorts","skirt","legging",
                           "jogger","cargo","sweatpant","track pant","culotte",
                           "capri","overall","slacks","bottom"]
        let topWords    = ["shirt","t‑shirt","tee","top","sweater","jumper",
                           "hoodie","pullover","jacket","coat","blazer","suit",
                           "cardigan","tank","sweatshirt","polo","vest",
                           "bodysuit","tunic","crop","henley","jersey","hooded"]
        
        func containsAny(_ haystack: String, _ words: [String]) -> Bool {
            words.first { haystack.contains($0) } != nil
        }
        
        // ───────────────────────────────────────────────────────────────────

            return src.compactMap { it in
                let thumb  = it.Images.Primary.Medium.URL
                let title  = it.ItemInfo.Title.DisplayValue
                let lower  = title.lowercased()

                let local  = LocalCatalog.shared.lookup(by: title)
                let kind   = local?.kind ?? {
                    switch true {
                    case containsAny(lower, shoeWords):   return .shoes
                    case containsAny(lower, bottomWords): return .bottom
                    case containsAny(lower, topWords):    return .top
                    default:                              return .other
                    }
                }()

                let (front, back) = it.frontBackURLs() ?? (nil, nil)
                let hex = dominantHexSync(from: front?.absoluteString ?? thumb)

                return ClothingItem(id: it.ASIN,
                                    title: title,
                                    imageUrl: thumb,
                                    colorHex: hex,
                                    frontURL: front?.absoluteString,
                                    backURL:  back?.absoluteString,
                                    assetURL: local?.asset,
                                    kind: kind,
                                    availableSizes: local?.sizes ?? [])
            }
        }

    
    private func generateAmazonSignature(for request: URLRequest,
                                         body: Data,
                                         accessKey: String,
                                         secretKey: String) -> [String:String] {
        
        amazonSigV4Headers(
            url        : request.url!,
            body       : body,
            accessKey  : accessKey,
            secretKey  : secretKey
        )
    }
}
extension UIColor {
    /// #RRGGBB (no alpha) – safe for Codable structs
    var hexRGB: String {
        let (r,g,b,_) = getComponents()
        return String(format:"#%02X%02X%02X",
                      Int(r*255), Int(g*255), Int(b*255))
    }
    private func getComponents() -> (CGFloat,CGFloat,CGFloat,CGFloat) {
        var r:CGFloat=0, g:CGFloat=0, b:CGFloat=0, a:CGFloat=0
        getRed(&r, green:&g, blue:&b, alpha:&a)
        return (r,g,b,a)
    }
}
