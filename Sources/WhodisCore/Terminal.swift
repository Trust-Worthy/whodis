import Foundation

// MARK: - Color (off when piped or when NO_COLOR is set)

public enum Style {
    public static let isEnabled: Bool = {
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
        return isatty(STDOUT_FILENO) == 1
    }()

    private static func wrap(_ code: String, _ text: String) -> String {
        isEnabled ? "\u{001B}[\(code)m\(text)\u{001B}[0m" : text
    }

    public static func bold(_ s: String) -> String { wrap("1", s) }
    public static func dim(_ s: String) -> String { wrap("2", s) }
    public static func red(_ s: String) -> String { wrap("31", s) }
    public static func green(_ s: String) -> String { wrap("32", s) }
    public static func yellow(_ s: String) -> String { wrap("33", s) }
    public static func cyan(_ s: String) -> String { wrap("36", s) }
}

// MARK: - Output

public func printStep(_ message: String) { print(Style.yellow("→ ") + message) }
public func printSuccess(_ message: String) { print(Style.green("✓ ") + message) }
public func printWarning(_ message: String) { print(Style.yellow("! ") + message) }

public func printError(_ message: String) {
    FileHandle.standardError.write(Data((Style.red("✗ ") + message + "\n").utf8))
}

// MARK: - Prompts

/// Yes/no prompt. With `assumeYes` it answers yes. If stdin is closed (piped, cron)
/// it answers **no**, so whodis never writes without an explicit yes.
public func confirm(_ question: String, defaultYes: Bool, assumeYes: Bool) -> Bool {
    if assumeYes { return true }
    print(question + (defaultYes ? " [Y/n] " : " [y/N] "), terminator: "")
    fflush(stdout)
    guard let line = readLine() else {
        print()
        return false
    }
    let answer = line.trimmingCharacters(in: .whitespaces).lowercased()
    if answer.isEmpty { return defaultYes }
    return answer == "y" || answer == "yes"
}

/// Cleans a path typed or drag-and-dropped into Terminal: strips surrounding quotes,
/// removes backslash escapes ("My\ Contacts.vcf"), and expands "~".
public func cleanDroppedPath(_ input: String) -> String {
    var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.count >= 2, let first = s.first, first == s.last, first == "'" || first == "\"" {
        s = String(s.dropFirst().dropLast())
    } else {
        var unescaped = ""
        var escaping = false
        for ch in s {
            if escaping {
                unescaped.append(ch)
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else {
                unescaped.append(ch)
            }
        }
        s = unescaped
    }
    return NSString(string: s).expandingTildeInPath
}

// MARK: - Tables

/// Plain aligned columns. (Swift `String(format: "%-22s", swiftString)` is undefined
/// behavior since %s expects a C string, so padding is done by hand.)
public func renderTable(headers: [String], rows: [[String]], maxColumnWidth: Int = 32) -> String {
    func fit(_ s: String) -> String {
        s.count <= maxColumnWidth ? s : String(s.prefix(maxColumnWidth - 1)) + "…"
    }
    let columns = headers.count
    let cells = ([headers] + rows).map { row in
        (0..<columns).map { i in i < row.count ? fit(row[i]) : "" }
    }
    var widths = Array(repeating: 0, count: columns)
    for row in cells {
        for (i, cell) in row.enumerated() { widths[i] = max(widths[i], cell.count) }
    }
    func line(_ row: [String]) -> String {
        var out = row.enumerated()
            .map { i, cell in cell + String(repeating: " ", count: widths[i] - cell.count) }
            .joined(separator: "  ")
        while out.last == " " { out.removeLast() }
        return out
    }
    let rule = widths.map { String(repeating: "─", count: $0) }.joined(separator: "  ")
    return ([line(cells[0]), rule] + cells.dropFirst().map(line)).joined(separator: "\n")
}

// MARK: - Dates

/// chat.db `message.date` is seconds since 2001-01-01 on old macOS and nanoseconds on
/// macOS 10.13+. Values too large to be seconds are treated as nanoseconds.
public func appleMessageDate(_ raw: Int64) -> Date? {
    guard raw > 0 else { return nil }
    let seconds = raw > 100_000_000_000 ? Double(raw) / 1_000_000_000 : Double(raw)
    return Date(timeIntervalSinceReferenceDate: seconds)
}

public func shortAge(_ interval: TimeInterval) -> String {
    let s = max(0, Int(interval))
    switch s {
    case ..<60: return "just now"
    case ..<3_600: return "\(s / 60)m ago"
    case ..<86_400: return "\(s / 3_600)h ago"
    case ..<(86_400 * 60): return "\(s / 86_400)d ago"
    case ..<(86_400 * 365): return "\(s / (86_400 * 30))mo ago"
    default: return "\(s / (86_400 * 365))y ago"
    }
}
