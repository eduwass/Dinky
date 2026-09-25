import Foundation
import TOMLDecoder

/// A TOML table read strictly: every key read is remembered and `done()` rejects the rest, so a
/// typo like `gap` is an error instead of being ignored. Each read returns nil when the key is
/// absent and throws a `ConfigError` naming the key path when the value has the wrong type.
///
/// This walks `TOMLTable` directly rather than going through `Decodable`: TOMLDecoder 0.4.4's
/// `Decoder` crashes on custom coding keys and hands scalars to table decoders.
final class Table {
    let path: String
    private let table: TOMLTable
    private var used: Set<String> = []

    init(_ table: TOMLTable, path: String = "") {
        self.table = table
        self.path = path
    }

    var keys: [String] { table.keys }

    func path(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    func bool(_ key: String) throws -> Bool? { try scalar(key, "true or false") { try $0.bool(forKey: key) } }
    func int(_ key: String) throws -> Int? { try scalar(key, "an integer") { Int(try $0.integer(forKey: key)) } }
    func double(_ key: String) throws -> Double? { try scalar(key, "a number") { try $0.float(forKey: key) } }

    func string(_ key: String) throws -> String? {
        // TOMLDecoder crashes reading a one digit integer as a string, so rule integers out first.
        if (try? table.integer(forKey: key)) != nil { throw ConfigError(path: path(key), "expected a string") }
        return try scalar(key, "a string") { try $0.string(forKey: key) }
    }

    /// A value that must be one of `T`'s raw values, e.g. `'tiles'` for `LayoutKind`.
    func choice<T: RawRepresentable & CaseIterable>(_ key: String) throws -> T? where T.RawValue == String {
        guard let raw = try string(key) else { return nil }
        guard let value = T(rawValue: raw) else {
            let choices = T.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
            throw ConfigError(path: path(key), "'\(raw)' is not one of \(choices)")
        }
        return value
    }

    func color(_ key: String) throws -> Color? {
        guard let hex = try string(key) else { return nil }
        do {
            return try Color(hex: hex)
        } catch {
            throw ConfigError(path: path(key), error.message)
        }
    }

    func table(_ key: String) throws -> Table? {
        guard use(key) else { return nil }
        guard let nested = try? table.table(forKey: key) else { throw ConfigError(path: path(key), "expected a table") }
        return Table(nested, path: path(key))
    }

    /// An array of tables, as written with `[[key]]`.
    func tables(_ key: String) throws -> [Table]? {
        guard use(key) else { return nil }
        guard let array = try? table.array(forKey: key) else { throw ConfigError(path: path(key), "expected a list of tables") }
        return try (0..<array.count).map { index in
            guard let nested = try? array.table(atIndex: index) else {
                throw ConfigError(path: "\(path(key))[\(index)]", "expected a table")
            }
            return Table(nested, path: "\(path(key))[\(index)]")
        }
    }

    /// A command string or a list of them, none empty. Commands stay strings here;
    /// the dispatcher owns the vocabulary.
    func commands(_ key: String) throws -> [String]? {
        guard table.contains(key: key) else { use(key); return nil }
        let error = ConfigError(path: path(key), "expected a command string or a list of them")
        var commands: [String]
        if let array = try? table.array(forKey: key) {
            use(key)
            commands = try (0..<array.count).map { index in
                guard (try? array.integer(atIndex: index)) == nil, let command = try? array.string(atIndex: index) else { throw error }
                return command
            }
        } else {
            guard let command = try? string(key) else { throw error }
            commands = [command]
        }
        if commands.isEmpty || commands.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw ConfigError(path: path(key), "commands can't be empty")
        }
        return commands
    }

    func done() throws {
        if let unknown = keys.first(where: { !used.contains($0) }) {
            throw ConfigError(path: path(unknown), "unknown key")
        }
    }

    /// Marks `key` as read; returns whether it is present.
    @discardableResult
    private func use(_ key: String) -> Bool {
        used.insert(key)
        return table.contains(key: key)
    }

    private func scalar<T>(_ key: String, _ expected: String, _ read: (TOMLTable) throws -> T) throws -> T? {
        guard use(key) else { return nil }
        do {
            return try read(table)
        } catch {
            throw ConfigError(path: path(key), "expected \(expected)", line: lineNumber(in: error))
        }
    }
}

/// TOMLDecoder puts the line in its error text, e.g. `(Line 3) Invalid integer value ...`.
private func lineNumber(in error: Error) -> Int? {
    let text = "\(error)"
    guard let range = text.range(of: #"(?<=\(Line )\d+"#, options: .regularExpression) else { return nil }
    return Int(text[range])
}
