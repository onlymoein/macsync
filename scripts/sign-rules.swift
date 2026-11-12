#!/usr/bin/env swift
// Signs docs/rules.json, the fixes every MacSync picks up from the website without an update.
//
//   swift scripts/sign-rules.swift            signs docs/rules.json into docs/rules.json.sig
//
// The private key lives in ~/.macsync-signing/rules-key and never in this repository. MacSync
// ignores a file whose signature doesn't match, or whose "version" is lower than one it already has,
// so raise "version" every time. Then commit and push docs/: GitHub Pages serves both files.
import CryptoKit
import Foundation

let rules = URL(fileURLWithPath: "docs/rules.json")
let keyFile = URL(fileURLWithPath: NSHomeDirectory() + "/.macsync-signing/rules-key")
let publicKey = "emqJDnYxcACvg4Lt0lQ8K8wcgmkLkWCK8SxHYEOqvzY="

func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }

guard let data = try? Data(contentsOf: rules) else { fail("No docs/rules.json here. Run this from the repository's top folder.") }
guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let version = json["version"] as? Int
else { fail("docs/rules.json isn't valid JSON with a whole-number \"version\".") }
guard let keyText = try? String(contentsOf: keyFile, encoding: .utf8),
      let raw = Data(base64Encoded: keyText.trimmingCharacters(in: .whitespacesAndNewlines)),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("Can't read the key in \(keyFile.path).") }
guard key.publicKey.rawRepresentation.base64EncodedString() == publicKey else {
    fail("That key isn't the one MacSync trusts (CloudRulesStore.publicKey).")
}
// The published copy, so a lower or equal version isn't signed by mistake.
if let live = try? Data(contentsOf: URL(string: "https://onlymoein.github.io/macsync/rules.json")!),
   let published = (try? JSONSerialization.jsonObject(with: live) as? [String: Any])?["version"] as? Int, version <= published,
   live != data {
    fail("version \(version) isn't higher than the published \(published). Raise it.")
}
let signature = try key.signature(for: data).base64EncodedString()
try Data((signature + "\n").utf8).write(to: rules.appendingPathExtension("sig"))
print("Signed docs/rules.json, version \(version).")
