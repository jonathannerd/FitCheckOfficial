import Foundation
import CryptoKit

// MARK: – PA‑API Sig‑V4 (us‑east‑1)
func amazonSigV4Headers(
    url       : URL,
    body      : Data,
    accessKey : String,
    secretKey : String
) -> [String:String] {

    // 1.  timestamps ----------------------------------------------------
    let now        = Date()
    let amzDate    = DateFormatter.sigV4DateTime.string(from: now) // 20250526T145415Z
    let dateStamp  = DateFormatter.sigV4Date.string(from: now)     // 20250526

    // 2. canonical request -------------------------------------------------
    let payloadHash = SHA256.hash(data: body).hex
    
    let canonicalHeadersLines = [
        "content-encoding:amz-1.0",
        "content-type:application/json; charset=UTF-8",
        "host:\(url.host!)",
        "x-amz-content-sha256:\(payloadHash)",
        "x-amz-date:\(amzDate)",
        "x-amz-target:com.amazon.paapi5.v1.ProductAdvertisingAPIv1.SearchItems",
        ""            // <‑‑ empty line required before the signed‑headers list
    ]
    let canonicalHeaders = canonicalHeadersLines.joined(separator: "\n")
    let signedHeaders = """
    content-encoding;content-type;host;x-amz-content-sha256;x-amz-date;x-amz-target
    """
    
    let canonicalRequest = [
        "POST",
        url.path.isEmpty ? "/" : url.path,
        "",                       // no query string
        canonicalHeaders,
        signedHeaders,
        payloadHash
    ].joined(separator: "\n")

    // 3.  string‑to‑sign -----------------------------------------------
    let region   = "us-east-1"
    let service  = "ProductAdvertisingAPI"
    let scope    = "\(dateStamp)/\(region)/\(service)/aws4_request"
    let stringToSign = [
        "AWS4-HMAC-SHA256",
        amzDate,
        scope,
        SHA256.hash(data: canonicalRequest.data(using: .utf8)!).hex
    ].joined(separator: "\n")

    // 4.  derive signing key -------------------------------------------
    func hmac(_ key: Data, _ string: String) -> Data {
        let k = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: Data(string.utf8), using: k))
    }
    let kSecret = Data(("AWS4" + secretKey).utf8)
    let kDate   = hmac(kSecret, dateStamp)
    let kRegion = hmac(kDate , region )
    let kServ   = hmac(kRegion, service)
    let kSign   = hmac(kServ , "aws4_request")
    let signature = hmac(kSign, stringToSign).hex

    // 5.  build auth header --------------------------------------------
    let authorization = """
AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), \
SignedHeaders=\(signedHeaders), \
Signature=\(signature)
"""

    return [
        "x-amz-date"           : amzDate,
        "x-amz-content-sha256" : payloadHash,
        "Authorization"        : authorization
    ]
}

// helpers
private extension SHA256.Digest { var hex: String { map { String(format:"%02x",$0) }.joined() } }
private extension Data           { var hex: String { map { String(format:"%02x",$0) }.joined() } }
private extension DateFormatter  {
    static let sigV4Date: DateFormatter = { let f = DateFormatter(); f.timeZone = .utc; f.dateFormat = "yyyyMMdd";              return f }()
    static let sigV4DateTime: DateFormatter = { let f = DateFormatter(); f.timeZone = .utc; f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; return f }()
}
private extension TimeZone { static let utc = TimeZone(secondsFromGMT: 0)! }
