#if os(macOS)
import Contacts
import Foundation
import WhodisCore

enum VCard {
    /// Parses the iPhone export into an in-memory index. Nothing from the vCard is written
    /// anywhere except the names whodis actually needs.
    static func index(from url: URL) throws -> ContactIndex {
        let contacts = try CNContactVCardSerialization.contacts(with: Data(contentsOf: url))
        var index = ContactIndex()
        for contact in contacts {
            let name = PersonName(contact)
            guard !name.isEmpty else { continue }
            if contact.isKeyAvailable(CNContactPhoneNumbersKey) {
                for number in contact.phoneNumbers {
                    index.addPhone(number.value.stringValue, name: name)
                }
            }
            if contact.isKeyAvailable(CNContactEmailAddressesKey) {
                for email in contact.emailAddresses {
                    index.addEmail(email.value as String, name: name)
                }
            }
        }
        return index
    }

    /// The newest .vcf in ~/Downloads, which is where AirDrop drops files.
    static func newestInDownloads() -> (url: URL, modified: Date)? {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: downloads,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (url: URL, modified: Date)?
        for url in files where url.pathExtension.lowercased() == "vcf" {
            guard let modified = try? url.resourceValues(forKeys: keys).contentModificationDate else { continue }
            if newest == nil || modified > newest!.modified {
                newest = (url: url, modified: modified)
            }
        }
        return newest
    }
}

enum Notifier {
    /// Unbundled CLIs can't use UNUserNotificationCenter, so this goes through osascript.
    static func post(_ message: String) {
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(escaped)\" with title \"whodis\""]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // A missed notification isn't worth failing over.
        }
    }
}
#endif
