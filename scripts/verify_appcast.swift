import Foundation
import CryptoKit

// Match Sparkle 2.10's signed-feed framing, and use only the committed PUBLIC key.
// Signing and native acceptance are also checked with official Sparkle tools.
let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), format: nil) as! [String: Any]
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: info["SUPublicEDKey"] as! String)!)
let xml = String(decoding: data, as: UTF8.self)
let pattern = #"<!-- sparkle-signatures:\s*edSignature: ([A-Za-z0-9+/=]+)\s*length: ([0-9]+)\s*-->\s*$"#
let regex = try NSRegularExpression(pattern: pattern)
guard let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
      let signatureRange = Range(match.range(at: 1), in: xml),
      let markerRange = Range(match.range, in: xml),
      let signature = Data(base64Encoded: String(xml[signatureRange])) else {
    fatalError("Missing signed-feed framing")
}
let unsigned = Data(xml[..<markerRange.lowerBound].utf8)
guard let lengthRange = Range(match.range(at: 2), in: xml),
      Int(xml[lengthRange]) == unsigned.count else { fatalError("Signed-feed length mismatch") }
guard key.isValidSignature(signature, for: unsigned) else { fatalError("Feed signature verification failed") }
print("Feed verified using the committed Retrolemetry public key.")
