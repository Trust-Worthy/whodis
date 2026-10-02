# whodis

**Put names back on the bare phone numbers in macOS Messages.**

Your iPhone shows "Alex Miller." Your Mac shows `+15550192348`. `whodis` fixes that in one command, touches only the conversations that need it, and can undo everything it did.

```
$ whodis
→ Reading Messages (read-only)…
  214 people in Messages; 37 show up as a bare number or email.

Found 2,041 Contacts.vcf in Downloads (2m ago).
Use it? [Y/n]
→ Reading 2,041 Contacts.vcf…
  1983 phone numbers and 1402 emails in the export.

Ready to name 31 conversation(s):
Handle          Name             Action              Last message
──────────────  ───────────────  ──────────────────  ────────────
+15550192348    Alex Miller      new card            2h ago
+447700900123   Priya Shah       new card            3d ago
sam@example.com Sam Lee          name existing card  1mo ago
…

Destination: iCloud (CardDAV, usually iCloud, so it syncs to your other devices)
Write 29 contact card(s)? [Y/n]
✓ Named 31 conversation(s) across 29 card(s).
```

## Why this happens

iMessage doesn't send names. Each message carries only a handle (a phone number or an Apple Account email), and Messages on each device looks that handle up in *that device's* Contacts.

Your iPhone searches every account it's signed into: iCloud, Google, Exchange, "On My iPhone." Your Mac usually only has iCloud. Anyone saved to Google or kept locally on the phone has a name on the iPhone and a bare number on the Mac.

The usual advice (toggle iCloud Contacts, sign out and back in) doesn't help, because those contacts were never in iCloud. Importing the full export does work, but it dumps thousands of stale cards onto your Mac.

## What whodis does

1. **Reads** `~/Library/Messages/chat.db` (opened **read-only**) to list everyone you've messaged.
2. **Asks Contacts**, through Apple's own matching, which of those handles have no name on this Mac.
3. **Parses** an export from your iPhone (all accounts, in one `.vcf`) and matches only those handles.
4. **Shows the plan** and waits for a yes.
5. **Writes** the names through the public `Contacts.framework` API, then offers to trash the export.

Only the people you actually talk to get cards. Nothing else from the export is written anywhere.

## Install

Requires macOS 13+ and Swift 5.9+ (Xcode or the Command Line Tools: `xcode-select --install`).

```sh
git clone https://github.com/Trust-Worthy/whodis.git
cd whodis
make install                      # installs to /usr/local/bin (may need sudo)
# or: make install PREFIX=~/.local
```

### Permissions (one time)

| Permission | Why | Where |
|---|---|---|
| **Full Disk Access** | macOS protects `chat.db` even for read-only access | System Settings → Privacy & Security → Full Disk Access → add your terminal app, then restart it |
| **Contacts** | To look up and write names | macOS prompts on first run. If you missed it: Privacy & Security → Contacts |

Both permissions attach to **your terminal app** (Terminal, iTerm, Ghostty…), not to `whodis` itself. That's how macOS handles command-line tools.

## Use

**On your iPhone:** open **Contacts** → tap **Lists** (top left) → long-press **All Contacts** → **Export** → AirDrop the file to your Mac.

**On your Mac:**

```sh
whodis                 # finds the newest .vcf in ~/Downloads
whodis path/to/file.vcf
whodis --dry-run       # preview, write nothing
whodis --undo          # revert everything whodis has written
```

| Option | |
|---|---|
| `-f, --file <path>` | vCard to use (also accepted as a bare argument) |
| `-n, --dry-run` | Show what would change; write nothing |
| `-y, --yes` | Skip confirmations (also trashes the vCard unless `--keep-vcard`) |
| `--keep-vcard` | Leave the export in place afterward |
| `--no-notify` | Skip the macOS notification |
| `--undo` | Revert every card whodis has written |

Run it again whenever names go missing. It's idempotent: conversations that already have a name are skipped.

## Safety model

- **`chat.db` is never written.** It's opened with `SQLITE_OPEN_READONLY`.
- **No private databases.** Contacts are read and written only through `Contacts.framework`, never by poking the AddressBook SQLite files, so macOS updates can't turn a schema change into corruption.
- **Nothing is written without an explicit yes.** If stdin isn't a terminal and you didn't pass `--yes`, whodis treats every prompt as "no."
- **Existing cards are respected.** If your Mac already has a nameless card for a number, whodis fills in the name instead of creating a duplicate. Cards that already have a name are never touched.
- **Conflicts are skipped, not guessed.** If two different people in your export share a number, whodis lists it and leaves it alone.
- **Undo is scoped and cautious.** Every write is logged to `~/Library/Application Support/whodis/manifest.json` (mode `0600`). `--undo` deletes cards whodis created and clears names it filled in, but skips any card you've edited since.
- **The export doesn't linger.** Your whole address book in a plaintext file in Downloads is a liability, so whodis offers to move it to the Trash.
- **No network, no dependencies.** Foundation, SQLite3, and Contacts only.

## How matching works

Phone numbers are reduced to their digits with leading zeros removed, which strips trunk prefixes (`07700…`, `030…`) and the `00` international prefix. A handle matches a vCard number if the digits are identical or, failing that, share the longest trailing run of at least 8 digits. So `+1 555 019 2348` matches `(555) 019-2348`, `+44 7700 900123` matches `07700 900123`, and `+49 30 1234567` matches `030 1234567`. An old 7-digit local number without an area code won't claim a full international number.

Several cards with the same display name (the same person in iCloud and Google, say) count as one person, and the fullest card wins. Business-only cards (organization name, no person name) are matched too. Emails match case-insensitively.

## Known behavior

- New cards go to your **default Contacts account**, shown before you confirm. If that's iCloud, the cards also sync to your iPhone, which may then show the person twice (their Google card and the new iCloud card). iOS usually links cards with identical names automatically. If it doesn't, pick "On My Mac" as the default account in Contacts → Settings before running.
- Group-chat participants who've never sent a message are not picked up yet.
- Short codes (2FA senders, etc.) and Business Chat handles are ignored on purpose.

## Development

```sh
swift build
swift test      # WhodisCore: matching, parsing, formatting (no permissions needed)
```

The code is split so the logic is testable without macOS permissions:

- `Sources/WhodisCore/`: pure Foundation. Matching, options, manifest, terminal output.
- `Sources/whodis/`: the macOS CLI. `MessagesDB` (read-only SQLite), `AddressBook` (Contacts.framework), `VCard`, `App` (the flow).

## Roadmap

- Menu bar app that watches `~/Downloads` for AirDropped exports
- A LaunchAgent that notices newly unnamed conversations and nudges you to refresh
- Pick the destination account with `--account`
- Include group-chat participants

## License

MIT. See [LICENSE](LICENSE).
