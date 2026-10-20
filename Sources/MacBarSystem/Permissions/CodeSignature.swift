import Foundation
import MacBarCore
import Security

/// Identity of the running code signature.
///
/// TCC grants are stored against the caller's *designated requirement*. For an
/// ad-hoc signature that requirement embeds the CDHash, so every rebuild creates
/// a new identity and the Accessibility grant stops applying even though the app
/// still appears checked in System Settings. Signing with a certificate makes the
/// requirement reference the certificate instead, which stays stable across
/// rebuilds. This helper lets the app detect the ad-hoc case and guide the user
/// instead of looping on a permission that will never take effect.
public enum CodeSignature {
    public static func current() -> SignatureInfo {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return .unknown
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return .unknown
        }
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let info = information as? [String: Any] else {
            return .unknown
        }

        let cdhash = (info[kSecCodeInfoUnique as String] as? Data)?
            .map { String(format: "%02x", $0) }
            .joined() ?? ""
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String ?? ""
        let isAdHoc = team.isEmpty
        // Certificate-signed builds keep a stable fingerprint across rebuilds;
        // ad-hoc builds get a new one because their CDHash changes.
        let fingerprint = isAdHoc ? cdhash : "team:\(team)"
        return SignatureInfo(cdhash: cdhash, teamIdentifier: team, isAdHoc: isAdHoc, fingerprint: fingerprint)
    }
}
