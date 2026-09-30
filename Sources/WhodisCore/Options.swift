import Foundation

public let whodisVersion = "0.1.0"

public struct Options: Equatable {
    public var vcardPath: String?
    public var dryRun = false
    public var assumeYes = false
    public var undo = false
    public var notify = true
    public var keepVCard = false
    public var help = false
    public var version = false

    public init() {}

    public static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var iterator = arguments.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "-h", "--help": options.help = true
            case "--version": options.version = true
            case "-n", "--dry-run": options.dryRun = true
            case "-y", "--yes": options.assumeYes = true
            case "--undo": options.undo = true
            case "--no-notify": options.notify = false
            case "--keep-vcard": options.keepVCard = true
            case "-f", "--file":
                guard let value = iterator.next() else { throw OptionsError.missingValue(arg) }
                try options.setPath(value)
            default:
                if arg.hasPrefix("-") { throw OptionsError.unknownOption(arg) }
                try options.setPath(arg)
            }
        }
        return options
    }

    private mutating func setPath(_ path: String) throws {
        guard vcardPath == nil else { throw OptionsError.extraArgument(path) }
        vcardPath = path
    }

    public static let usage = """
    whodis \(whodisVersion): put names back on the bare numbers in macOS Messages

    USAGE
      whodis [options] [path/to/contacts.vcf]

      With no path, whodis offers the newest .vcf in ~/Downloads (where AirDrop puts it).

    OPTIONS
      -f, --file <path>   vCard exported from your iPhone's Contacts app
      -n, --dry-run       Show what would change; write nothing
      -y, --yes           Skip confirmations (also trashes the vCard unless --keep-vcard)
          --keep-vcard    Leave the vCard in place afterwards
          --no-notify     Skip the macOS notification
          --undo          Revert every contact whodis has written
      -h, --help          Show this help
          --version       Show the version
    """
}

public enum OptionsError: Error, Equatable, CustomStringConvertible {
    case unknownOption(String)
    case missingValue(String)
    case extraArgument(String)

    public var description: String {
        switch self {
        case .unknownOption(let o): return "Unknown option: \(o)"
        case .missingValue(let o): return "\(o) needs a file path"
        case .extraArgument(let a): return "Unexpected extra argument: \(a) (only one vCard at a time)"
        }
    }
}
