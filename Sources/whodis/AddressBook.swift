#if os(macOS)
import Contacts
import Foundation
import WhodisCore

/// One card to write: a new card, or a name for an existing nameless card.
/// New cards group every handle belonging to the same person.
struct PlannedChange {
    let name: PersonName
    var handles: [ChatHandle]
    let existing: CNContact?
}

/// All contact reads and writes go through the public Contacts.framework API.
/// whodis never touches the AddressBook SQLite files.
final class AddressBook {
    enum Existing {
        case named
        case unnamed(CNContact)
        case missing
    }

    enum RevertResult {
        case reverted
        case editedSince
        case notFound
    }

    struct Outcome {
        var applied: [ManifestEntry] = []
        var failed: [(change: PlannedChange, error: Error)] = []
    }

    private let store = CNContactStore()

    private static let keys: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactMiddleNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
    ]

    // MARK: Permission

    /// Blocks until the user answers the prompt. (`requestAccess` is async; not
    /// waiting for it makes the first run fail silently.)
    func requestAccess() -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            store.requestAccess(for: .contacts) { ok, _ in
                granted = ok
                semaphore.signal()
            }
            semaphore.wait()
            return granted
        default:
            // Newer states (e.g. limited access): proceed and let lookups show what's visible.
            return true
        }
    }

    // MARK: Lookup

    /// Asks Contacts, with Apple's own matching, whether this handle already has a name,
    /// the same way Messages resolves it.
    func lookup(_ handle: ChatHandle) throws -> Existing {
        let predicate: NSPredicate
        switch handle.kind {
        case .phone: predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: handle.id))
        case .email: predicate = CNContact.predicateForContacts(matchingEmailAddress: handle.id)
        }
        let matches = try store.unifiedContacts(matching: predicate, keysToFetch: Self.keys)
        if matches.contains(where: { !PersonName($0).isEmpty }) { return .named }
        if let nameless = matches.first { return .unnamed(nameless) }
        return .missing
    }

    func defaultContainerDescription() -> String {
        let id = store.defaultContainerIdentifier()
        let predicate = CNContainer.predicateForContainers(withIdentifiers: [id])
        guard let container = try? store.containers(matching: predicate).first else {
            return "your default Contacts account"
        }
        switch container.type {
        case .local: return "On My Mac (stays on this Mac)"
        case .cardDAV: return "\(container.name) (CardDAV, usually iCloud, so it syncs to your other devices)"
        case .exchange: return "\(container.name) (Exchange)"
        default: return container.name
        }
    }

    // MARK: Writes

    /// One save request per card, so a single failure (e.g. a read-only account) doesn't sink the rest.
    func apply(_ plan: [PlannedChange]) -> Outcome {
        var outcome = Outcome()
        for change in plan {
            do {
                outcome.applied.append(try apply(change))
            } catch {
                outcome.failed.append((change, error))
            }
        }
        return outcome
    }

    private func apply(_ change: PlannedChange) throws -> ManifestEntry {
        let request = CNSaveRequest()
        let contact: CNMutableContact
        let action: ManifestEntry.Action

        if let existing = change.existing, let copy = existing.mutableCopy() as? CNMutableContact {
            contact = copy
            action = .updated
            contact.setName(change.name)
            request.update(contact)
        } else {
            contact = CNMutableContact()
            action = .created
            contact.setName(change.name)
            contact.phoneNumbers = change.handles.filter { $0.kind == .phone }.map {
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0.id))
            }
            contact.emailAddresses = change.handles.filter { $0.kind == .email }.map {
                CNLabeledValue(label: CNLabelOther, value: $0.id as NSString)
            }
            request.add(contact, toContainerWithIdentifier: nil)
        }

        try store.execute(request)
        return ManifestEntry(
            contactIdentifier: contact.identifier,
            action: action,
            handles: change.handles.map(\.id),
            name: change.name
        )
    }

    // MARK: Undo

    /// Reverses one manifest entry, but only if the card still carries the exact name
    /// whodis wrote. If you've edited it since, it's yours and whodis leaves it alone.
    func revert(_ entry: ManifestEntry) throws -> RevertResult {
        let fetch = CNContactFetchRequest(keysToFetch: Self.keys)
        fetch.predicate = CNContact.predicateForContacts(withIdentifiers: [entry.contactIdentifier])
        fetch.unifyResults = false  // act on the exact card whodis wrote, not anything linked to it

        var found: CNContact?
        try store.enumerateContacts(with: fetch) { contact, stop in
            found = contact
            stop.pointee = true
        }

        guard let current = found, let mutable = current.mutableCopy() as? CNMutableContact else {
            return .notFound
        }
        guard PersonName(current) == entry.name else { return .editedSince }

        let request = CNSaveRequest()
        switch entry.action {
        case .created:
            request.delete(mutable)
        case .updated:
            mutable.setName(PersonName())
            request.update(mutable)
        }
        try store.execute(request)
        return .reverted
    }
}

// MARK: - Bridging

extension PersonName {
    /// Reads only keys that were actually fetched. Touching an unfetched key raises an
    /// Objective-C exception that Swift can't catch.
    init(_ contact: CNContact) {
        func field(_ key: String, _ value: () -> String) -> String {
            contact.isKeyAvailable(key) ? value() : ""
        }
        self.init(
            givenName: field(CNContactGivenNameKey) { contact.givenName },
            middleName: field(CNContactMiddleNameKey) { contact.middleName },
            familyName: field(CNContactFamilyNameKey) { contact.familyName },
            organizationName: field(CNContactOrganizationNameKey) { contact.organizationName }
        )
    }
}

extension CNMutableContact {
    func setName(_ name: PersonName) {
        givenName = name.givenName
        middleName = name.middleName
        familyName = name.familyName
        organizationName = name.organizationName
    }
}
#endif
