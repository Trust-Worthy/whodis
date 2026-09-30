import Foundation

/// The kinds of Messages handle whodis can resolve. Everything else (short codes,
/// Business Chat `urn:biz:` ids, etc.) is ignored.
public enum HandleKind: String, Codable, Equatable {
    case phone
    case email

    public static func classify(_ handle: String) -> HandleKind? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") { return .email }
        let allowed = CharacterSet(charactersIn: "+0123456789 ()-.")
        guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return PhoneKey.significantDigits(trimmed).count >= PhoneKey.minimumLength ? .phone : nil
    }
}

public enum PhoneKey {
    /// Shorter than this is a short code or junk, never matched.
    public static let minimumLength = 7

    /// Non-exact matches must share at least this many trailing digits. Keeps a
    /// 7-digit local number from an old contact from grabbing a full international number.
    public static let minimumSuffixOverlap = 8

    /// ASCII digits only, with leading zeros stripped. That removes both the trunk
    /// prefix ("030 …", "07700 …") and the "00" international prefix, so local and
    /// international spellings of a number end in the same digits.
    public static func significantDigits(_ raw: String) -> String {
        let digits = raw.filter { $0.isASCII && $0.isNumber }
        return String(digits.drop(while: { $0 == "0" }))
    }
}
