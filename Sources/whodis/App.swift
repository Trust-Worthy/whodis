#if os(macOS)
import Contacts
import Foundation
import WhodisCore

struct App {
    let arguments: [String]

    func run() -> Int32 {
        let options: Options
        do {
            options = try Options.parse(arguments)
        } catch {
            printError("\(error)")
            print("\n" + Options.usage)
            return 2
        }
        if options.help { print(Options.usage); return 0 }
        if options.version { print("whodis \(whodisVersion)"); return 0 }

        print(Style.bold(Style.cyan("whodis")) + Style.dim("  put names back on the numbers in Messages\n"))

        let book = AddressBook()
        guard book.requestAccess() else {
            printError("whodis doesn't have access to Contacts.")
            print("  Turn it on for your terminal app in System Settings → Privacy & Security → Contacts, then run again.")
            return 1
        }
        return options.undo ? undo(book: book, options: options) : sync(book: book, options: options)
    }

    // MARK: - Sync

    private func sync(book: AddressBook, options: Options) -> Int32 {
        // 1. Who in Messages has no name on this Mac?
        printStep("Reading Messages (read-only)…")
        let handles: [ChatHandle]
        do {
            handles = try MessagesDB.activeHandles()
        } catch {
            printError("Couldn't open ~/Library/Messages/chat.db (\(error)).")
            print("  whodis only reads it, but macOS still requires Full Disk Access.")
            print("  Grant it to your terminal app in System Settings → Privacy & Security → Full Disk Access,")
            print("  then quit and reopen the terminal.")
            return 1
        }

        var unnamed: [(handle: ChatHandle, existing: CNContact?)] = []
        do {
            for handle in handles {
                switch try book.lookup(handle) {
                case .named: continue
                case .unnamed(let card): unnamed.append((handle, card))
                case .missing: unnamed.append((handle, nil))
                }
            }
        } catch {
            printError("Couldn't search Contacts: \(error.localizedDescription)")
            return 1
        }

        print("  \(handles.count) people in Messages; \(Style.bold("\(unnamed.count)")) show up as a bare number or email.\n")
        guard !unnamed.isEmpty else {
            printSuccess("Every conversation already has a name. Nothing to do.")
            return 0
        }

        // 2. Load the iPhone export.
        guard let vcardURL = chooseVCard(options) else { return 1 }
        printStep("Reading \(vcardURL.lastPathComponent)…")
        let index: ContactIndex
        do {
            index = try VCard.index(from: vcardURL)
        } catch {
            printError("Couldn't read that vCard: \(error.localizedDescription)")
            return 1
        }
        print("  \(index.phoneCount) phone numbers and \(index.emailCount) emails in the export.\n")

        // 3. Match surgically: only handles that are both in Messages and unnamed.
        var plan: [PlannedChange] = []
        var newCardSlot: [PersonName: Int] = [:]
        var ambiguous: [(handle: ChatHandle, names: [String])] = []
        var unmatched = 0

        for item in unnamed {
            switch index.match(item.handle.id) {
            case .unique(let name):
                if let existing = item.existing {
                    plan.append(PlannedChange(name: name, handles: [item.handle], existing: existing))
                } else if let slot = newCardSlot[name] {
                    plan[slot].handles.append(item.handle)  // same person, another number: one card
                } else {
                    newCardSlot[name] = plan.count
                    plan.append(PlannedChange(name: name, handles: [item.handle], existing: nil))
                }
            case .ambiguous(let names):
                ambiguous.append((item.handle, names))
            case .noMatch:
                unmatched += 1
            }
        }

        // 4. Show the plan.
        let handleCount = plan.reduce(0) { $0 + $1.handles.count }
        if !plan.isEmpty {
            print(Style.bold("Ready to name \(handleCount) conversation(s):"))
            let now = Date()
            let rows: [[String]] = plan.flatMap { change in
                change.handles.map { handle in
                    [
                        handle.id,
                        change.name.displayName,
                        change.existing == nil ? "new card" : "name existing card",
                        handle.lastMessage.map { shortAge(now.timeIntervalSince($0)) } ?? "—",
                    ]
                }
            }
            print(renderTable(headers: ["Handle", "Name", "Action", "Last message"], rows: rows))
            print()
        }
        if !ambiguous.isEmpty {
            printWarning("Skipping \(ambiguous.count) handle(s) that match more than one person in your export:")
            for item in ambiguous {
                print("    \(item.handle.id): \(item.names.joined(separator: " / "))")
            }
            print()
        }
        if unmatched > 0 {
            print(Style.dim("  \(unmatched) handle(s) aren't in the export (unknown senders, businesses, old numbers).\n"))
        }

        guard !plan.isEmpty else {
            printWarning("No matches between this export and your unnamed conversations. Nothing written.")
            return 0
        }
        if options.dryRun {
            print("Dry run: no changes made.")
            return 0
        }

        // 5. Write through Contacts.framework, after an explicit yes.
        print("Destination: \(book.defaultContainerDescription())")
        guard confirm("Write \(plan.count) contact card(s)?", defaultYes: true, assumeYes: options.assumeYes) else {
            print("Cancelled. No changes made.")
            return 0
        }

        let outcome = book.apply(plan)
        recordForUndo(outcome.applied)

        let named = outcome.applied.reduce(0) { $0 + $1.handles.count }
        if !outcome.applied.isEmpty {
            printSuccess("Named \(named) conversation(s) across \(outcome.applied.count) card(s).")
            print(Style.dim("  If Messages still shows numbers, quit and reopen it. Changed your mind? whodis --undo"))
        }
        for failure in outcome.failed {
            printError("\(failure.change.name.displayName): \(failure.error.localizedDescription)")
        }
        if options.notify && named > 0 {
            Notifier.post("Updated \(named) name\(named == 1 ? "" : "s") in Messages.")
        }

        // 6. The export is your whole address book in plaintext; don't leave it lying around.
        if !options.keepVCard {
            print()
            if confirm("Move \(vcardURL.lastPathComponent) to the Trash? It contains your entire address book.",
                       defaultYes: true, assumeYes: options.assumeYes) {
                do {
                    try FileManager.default.trashItem(at: vcardURL, resultingItemURL: nil)
                    printSuccess("Moved to Trash.")
                } catch {
                    printWarning("Couldn't move it to the Trash: \(error.localizedDescription)")
                }
            }
        }

        return outcome.applied.isEmpty && !outcome.failed.isEmpty ? 1 : 0
    }

    private func chooseVCard(_ options: Options) -> URL? {
        if let path = options.vcardPath {
            let url = URL(fileURLWithPath: cleanDroppedPath(path))
            guard FileManager.default.fileExists(atPath: url.path) else {
                printError("No file at \(url.path)")
                return nil
            }
            return url
        }

        if let newest = VCard.newestInDownloads() {
            let age = shortAge(Date().timeIntervalSince(newest.modified))
            print("Found \(Style.cyan(newest.url.lastPathComponent)) in Downloads (\(age)).")
            if confirm("Use it?", defaultYes: true, assumeYes: options.assumeYes) { return newest.url }
        } else {
            print(Self.exportInstructions)
        }

        if options.assumeYes {
            printError("No vCard given. Pass one with --file.")
            return nil
        }
        print("Path to the exported .vcf (you can drag it into this window): ", terminator: "")
        fflush(stdout)
        guard let line = readLine(), !line.trimmingCharacters(in: .whitespaces).isEmpty else {
            printError("No file given.")
            return nil
        }
        let url = URL(fileURLWithPath: cleanDroppedPath(line))
        guard FileManager.default.fileExists(atPath: url.path) else {
            printError("No file at \(url.path)")
            return nil
        }
        return url
    }

    private func recordForUndo(_ entries: [ManifestEntry]) {
        guard !entries.isEmpty else { return }
        do {
            var manifest = try Manifest.load()
            manifest.entries.append(contentsOf: entries)
            try manifest.save()
        } catch {
            // Don't overwrite an unreadable log; that would lose earlier undo history.
            printWarning("Couldn't update the undo log (\(error.localizedDescription)). These changes won't be covered by --undo.")
        }
    }

    static let exportInstructions = """
    No .vcf found in ~/Downloads. To make one on your iPhone:
      1. Open the Contacts app and tap Lists (top left).
      2. Long-press All Contacts → Export (make sure phone numbers are included).
      3. AirDrop the file to this Mac, then run whodis again.

    """

    // MARK: - Undo

    private func undo(book: AddressBook, options: Options) -> Int32 {
        let manifest: Manifest
        do {
            manifest = try Manifest.load()
        } catch {
            printError("Couldn't read the undo log at \(Manifest.defaultURL.path): \(error.localizedDescription)")
            return 1
        }
        guard !manifest.entries.isEmpty else {
            print("Nothing to undo. whodis hasn't written any contacts.")
            return 0
        }

        let created = manifest.entries.filter { $0.action == .created }.count
        let updated = manifest.entries.count - created
        print("whodis has written \(manifest.entries.count) card(s): \(created) new, \(updated) named existing.")
        if options.dryRun {
            print("Dry run: no changes made.")
            return 0
        }
        guard confirm("Revert all of them?", defaultYes: false, assumeYes: options.assumeYes) else {
            print("Cancelled.")
            return 0
        }

        var reverted = 0
        var keep: [ManifestEntry] = []
        for entry in manifest.entries {
            do {
                switch try book.revert(entry) {
                case .reverted:
                    reverted += 1
                case .notFound:
                    break  // already deleted; drop from the log
                case .editedSince:
                    printWarning("Left \(entry.name.displayName) alone: it was edited after whodis wrote it.")
                }
            } catch {
                printWarning("Couldn't revert \(entry.name.displayName): \(error.localizedDescription)")
                keep.append(entry)  // retry next time
            }
        }

        do {
            try Manifest(entries: keep).save()
        } catch {
            printWarning("Couldn't update the undo log: \(error.localizedDescription)")
        }
        printSuccess("Reverted \(reverted) card(s).")
        return keep.isEmpty ? 0 : 1
    }
}
#endif
