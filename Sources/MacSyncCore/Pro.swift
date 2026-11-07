import Foundation

/// The single switch for Pro. Flip `enforced` to true when licensing exists, and make
/// `licenseIsValid()` check it. Until then every feature is unlocked and nothing asks for a key.
public enum ProLicense {
    public static let enforced = false

    public static func licenseIsValid() -> Bool { false }

    public static var isUnlocked: Bool { !enforced || licenseIsValid() }
}
