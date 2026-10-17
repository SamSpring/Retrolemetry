import Foundation
import CryptoKit

// Isolated QA only: never imports/exports a production Keychain key.
let key = Curve25519.Signing.PrivateKey()
let path = URL(fileURLWithPath: CommandLine.arguments[1])
FileManager.default.createFile(atPath: path.path, contents: nil, attributes: [.posixPermissions: 0o600])
try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: path)
print(key.publicKey.rawRepresentation.base64EncodedString())
