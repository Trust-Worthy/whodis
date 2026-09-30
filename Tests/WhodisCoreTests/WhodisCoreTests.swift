import Foundation
import XCTest
@testable import WhodisCore

final class HandleTests: XCTestCase {
    func testClassify() {
        XCTAssertEqual(HandleKind.classify("+15550192348"), .phone)
        XCTAssertEqual(HandleKind.classify("(555) 019-2348"), .phone)
        XCTAssertEqual(HandleKind.classify("Alex@Example.com"), .email)
        XCTAssertNil(HandleKind.classify("88202"), "short codes are skipped")
        XCTAssertNil(HandleKind.classify("urn:biz:1234-5678"), "Business Chat ids are skipped")
        XCTAssertNil(HandleKind.classify(""))
    }

    func testSignificantDigits() {
        XCTAssertEqual(PhoneKey.significantDigits("+1 (555) 019-2348"), "15550192348")
        XCTAssertEqual(PhoneKey.significantDigits("07700 900123"), "7700900123")
        XCTAssertEqual(PhoneKey.significantDigits("0049 30 1234567"), "49301234567")
    }
}

final class ContactIndexTests: XCTestCase {
    let alex = PersonName(givenName: "Alex", familyName: "Miller")
    let sam = PersonName(givenName: "Sam", familyName: "Lee")

    func testUSNumberWithoutCountryCode() {
        var index = ContactIndex()
        index.addPhone("(555) 019-2348", name: alex)
        XCTAssertEqual(index.match("+15550192348"), .unique(alex))
    }

    func testInternationalTrunkPrefixes() {
        var index = ContactIndex()
        index.addPhone("07700 900123", name: alex)        // UK, local format
        index.addPhone("030 1234567", name: sam)          // Berlin, local format
        XCTAssertEqual(index.match("+447700900123"), .unique(alex))
        XCTAssertEqual(index.match("+49301234567"), .unique(sam))
    }

    func testExactBeatsSuffix() {
        var index = ContactIndex()
        index.addPhone("+1 555 019 2348", name: alex)
        index.addPhone("+44 555 019 2348", name: sam)
        XCTAssertEqual(index.match("+15550192348"), .unique(alex))
    }

    func testShortLocalNumberDoesNotGrabFullNumber() {
        var index = ContactIndex()
        index.addPhone("555-1234", name: sam)  // old 7-digit local entry, area code unknown
        XCTAssertEqual(index.match("+12125551234"), .noMatch)
    }

    func testConflictIsAmbiguous() {
        var index = ContactIndex()
        index.addPhone("555-019-2348", name: alex)
        index.addPhone("(555) 019-2348", name: sam)  // shared family line, or a reassigned number
        XCTAssertEqual(index.match("+15550192348"), .ambiguous(["Alex Miller", "Sam Lee"]))
    }

    func testDuplicateCardsForSamePersonResolve() {
        var index = ContactIndex()
        let withCompany = PersonName(givenName: "Alex", familyName: "Miller", organizationName: "Acme")
        index.addPhone("+15550192348", name: alex)
        index.addPhone("+15550192348", name: withCompany)
        XCTAssertEqual(index.match("+15550192348"), .unique(withCompany), "fullest card wins")
    }

    func testBusinessOnlyCard() {
        var index = ContactIndex()
        let bank = PersonName(organizationName: "Chase Bank")
        index.addPhone("+18005551234", name: bank)
        XCTAssertEqual(index.match("+18005551234"), .unique(bank))
    }

    func testEmailIsCaseInsensitive() {
        var index = ContactIndex()
        index.addEmail("Alex@Example.com", name: alex)
        XCTAssertEqual(index.match("alex@example.COM"), .unique(alex))
    }

    func testNamelessCardsIgnored() {
        var index = ContactIndex()
        index.addPhone("+15550192348", name: PersonName())
        XCTAssertEqual(index.match("+15550192348"), .noMatch)
        XCTAssertEqual(index.phoneCount, 0)
    }

    func testMultiWordNamesStayIntact() {
        let name = PersonName(givenName: "Mary Ann", familyName: "Smith")
        XCTAssertEqual(name.displayName, "Mary Ann Smith")
        XCTAssertEqual(name.givenName, "Mary Ann")
    }
}

final class OptionsTests: XCTestCase {
    func testDefaults() throws {
        XCTAssertEqual(try Options.parse([]), Options())
    }

    func testFlagsAndPositionalPath() throws {
        let o = try Options.parse(["-n", "--yes", "--no-notify", "~/Downloads/c.vcf"])
        XCTAssertTrue(o.dryRun)
        XCTAssertTrue(o.assumeYes)
        XCTAssertFalse(o.notify)
        XCTAssertEqual(o.vcardPath, "~/Downloads/c.vcf")
    }

    func testErrors() {
        XCTAssertThrowsError(try Options.parse(["--nope"]))
        XCTAssertThrowsError(try Options.parse(["--file"]))
        XCTAssertThrowsError(try Options.parse(["a.vcf", "b.vcf"]))
    }
}

final class TerminalTests: XCTestCase {
    func testCleanDroppedPath() {
        let home = NSString(string: "~").expandingTildeInPath
        XCTAssertEqual(cleanDroppedPath("~/Downloads/My\\ Contacts.vcf "), home + "/Downloads/My Contacts.vcf")
        XCTAssertEqual(cleanDroppedPath("'/tmp/a b.vcf'"), "/tmp/a b.vcf")
    }

    func testRenderTableAligns() {
        let out = renderTable(headers: ["A", "Name"], rows: [["+15550192348", "Alex"]])
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "A             Name")
        XCTAssertEqual(lines[2], "+15550192348  Alex")
    }

    func testAppleMessageDate() {
        let seconds: Int64 = 700_000_000
        XCTAssertEqual(appleMessageDate(seconds), Date(timeIntervalSinceReferenceDate: 700_000_000))
        XCTAssertEqual(appleMessageDate(seconds * 1_000_000_000), Date(timeIntervalSinceReferenceDate: 700_000_000))
        XCTAssertNil(appleMessageDate(0))
    }

    func testShortAge() {
        XCTAssertEqual(shortAge(30), "just now")
        XCTAssertEqual(shortAge(3 * 3_600), "3h ago")
        XCTAssertEqual(shortAge(5 * 86_400), "5d ago")
    }
}

final class ManifestTests: XCTestCase {
    func testRoundTripIsOwnerOnly() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("manifest.json")
        let entry = ManifestEntry(
            contactIdentifier: "abc",
            action: .created,
            handles: ["+15550192348"],
            name: PersonName(givenName: "Alex"),
            date: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try Manifest(entries: [entry]).save(to: url)
        XCTAssertEqual(try Manifest.load(from: url).entries, [entry])

        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testMissingFileIsEmpty() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        XCTAssertEqual(try Manifest.load(from: url), Manifest())
    }
}
