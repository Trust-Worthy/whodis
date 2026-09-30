import Foundation

/// A contact name kept as structured fields. whodis copies these field-by-field from the
/// vCard and never re-splits a display string (so "Mary Ann Smith" stays intact).
public struct PersonName: Hashable, Codable {
    public var givenName: String
    public var middleName: String
    public var familyName: String
    public var organizationName: String

    public init(givenName: String = "", middleName: String = "", familyName: String = "", organizationName: String = "") {
        self.givenName = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.middleName = middleName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.familyName = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.organizationName = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Roughly what Messages shows: the person's name, or the company for business-only cards.
    public var displayName: String {
        let person = [givenName, middleName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return person.isEmpty ? organizationName : person
    }

    public var isEmpty: Bool { displayName.isEmpty }

    /// Populated field count, used to prefer the fullest of several equivalent cards.
    var richness: Int {
        [givenName, middleName, familyName, organizationName].filter { !$0.isEmpty }.count
    }

    /// Stable key for deterministic tie-breaking.
    var sortKey: String { "\(givenName)|\(middleName)|\(familyName)|\(organizationName)" }
}
