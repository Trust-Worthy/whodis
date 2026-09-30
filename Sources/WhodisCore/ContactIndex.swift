import Foundation

public enum MatchResult: Equatable {
    case noMatch
    case unique(PersonName)
    /// Two or more different people claim this handle. whodis skips these rather than guess.
    case ambiguous([String])
}

/// Lookup table built from the iPhone's vCard export.
///
/// Phone matching: exact on significant digits first; otherwise the longest shared
/// digit suffix (at least `PhoneKey.minimumSuffixOverlap`). So "+1 555 123 4567"
/// matches "(555) 123-4567", "+44 7700 900123" matches "07700 900123", and
/// "+49 30 1234567" matches "030 1234567".
public struct ContactIndex {
    private var phoneEntries: [(key: String, name: PersonName)] = []
    private var phonesByKey: [String: Set<PersonName>] = [:]
    private var emailsByKey: [String: Set<PersonName>] = [:]

    public init() {}

    public var phoneCount: Int { phonesByKey.count }
    public var emailCount: Int { emailsByKey.count }

    public mutating func addPhone(_ raw: String, name: PersonName) {
        guard !name.isEmpty else { return }
        let key = PhoneKey.significantDigits(raw)
        guard key.count >= PhoneKey.minimumLength else { return }
        if phonesByKey[key, default: []].insert(name).inserted {
            phoneEntries.append((key, name))
        }
    }

    public mutating func addEmail(_ raw: String, name: PersonName) {
        guard !name.isEmpty else { return }
        let key = Self.emailKey(raw)
        guard key.contains("@") else { return }
        emailsByKey[key, default: []].insert(name)
    }

    public func match(_ handle: String) -> MatchResult {
        switch HandleKind.classify(handle) {
        case .email?: return resolve(emailsByKey[Self.emailKey(handle)] ?? [])
        case .phone?: return resolve(phoneCandidates(handle))
        case nil: return .noMatch
        }
    }

    private static func emailKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func phoneCandidates(_ raw: String) -> Set<PersonName> {
        let key = PhoneKey.significantDigits(raw)
        guard key.count >= PhoneKey.minimumLength else { return [] }
        if let exact = phonesByKey[key] { return exact }

        var best = 0
        var hits: Set<PersonName> = []
        for entry in phoneEntries {
            let overlap: Int
            if key.hasSuffix(entry.key) {
                overlap = entry.key.count
            } else if entry.key.hasSuffix(key) {
                overlap = key.count
            } else {
                continue
            }
            guard overlap >= PhoneKey.minimumSuffixOverlap else { continue }
            if overlap > best {
                best = overlap
                hits = [entry.name]
            } else if overlap == best {
                hits.insert(entry.name)
            }
        }
        return hits
    }

    /// The same person often appears on several cards (iCloud + Google + Exchange).
    /// If every candidate has the same display name, that's one person: keep the fullest
    /// card. Different display names mean a genuine conflict.
    private func resolve(_ names: Set<PersonName>) -> MatchResult {
        guard !names.isEmpty else { return .noMatch }
        let displayNames = Set(names.map(\.displayName))
        guard displayNames.count == 1 else { return .ambiguous(displayNames.sorted()) }
        let best = names.sorted {
            $0.richness != $1.richness ? $0.richness > $1.richness : $0.sortKey < $1.sortKey
        }[0]
        return .unique(best)
    }
}
