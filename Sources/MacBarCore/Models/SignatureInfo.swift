import Foundation

/// Identity of the running code signature, as far as the UI needs to know.
///
/// TCC grants are matched against the caller's designated requirement. Ad-hoc
/// signatures embed the CDHash, which changes on every rebuild, so a grant made
/// for one build silently stops applying to the next one even though System
/// Settings still shows the app as enabled. Certificate-signed builds use the
/// team identifier and remain stable.
public struct SignatureInfo: Sendable, Equatable {
    public var cdhash: String
    public var teamIdentifier: String
    public var isAdHoc: Bool
    public var fingerprint: String

    public init(cdhash: String, teamIdentifier: String, isAdHoc: Bool, fingerprint: String) {
        self.cdhash = cdhash
        self.teamIdentifier = teamIdentifier
        self.isAdHoc = isAdHoc
        self.fingerprint = fingerprint
    }

    public static let unknown = SignatureInfo(cdhash: "", teamIdentifier: "", isAdHoc: true, fingerprint: "unknown")

    public var summary: String {
        isAdHoc
            ? "ad-hoc 签名（每次重新构建都会失效，需要重新授权）"
            : "证书签名（team \(teamIdentifier)）"
    }

    public var shortFingerprint: String {
        fingerprint.count > 12 ? String(fingerprint.prefix(12)) : fingerprint
    }
}
