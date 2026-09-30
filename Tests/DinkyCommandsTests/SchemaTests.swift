import Foundation
import Testing
import DinkyConfig
import TOMLDecoder
@testable import DinkyCommands

/// docs/schemas/dinky.json is written by hand; these keep it from drifting away from the code.
struct SchemaTests {
    private static let schema: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/schemas/dinky.json")
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    private var definitions: [String: [String: Any]] { Self.schema["definitions"] as! [String: [String: Any]] }

    @Test func `Command pattern lists every command`() throws {
        let pattern = definitions["command"]!["pattern"] as! String
        let regex = try NSRegularExpression(pattern: pattern)
        func matches(_ text: String) -> Bool { regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
        for doc in Command.all {
            #expect(matches(doc.name), "\(doc.name)")
            #expect(matches(doc.syntax), "\(doc.syntax)")
        }
        for bad in ["", "fly left", "workspaces 3", "layouts", "modes main"] {
            #expect(!matches(bad), "\(bad)")
        }
        // The alternation names exactly the commands, no more.
        let listed = pattern.split(separator: "(")[1].split(separator: ")")[0].split(separator: "|").map(String.init)
        #expect(Set(listed) == Set(Command.all.map(\.name)))
        #expect(listed.count == Command.all.count, "a command is listed twice")
    }

    @Test func `Key combo pattern matches every key name`() throws {
        let pattern = definitions["keyCombo"]!["pattern"] as! String
        let regex = try NSRegularExpression(pattern: pattern)
        func matches(_ text: String) -> Bool { regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
        for name in KeyCombo.keyNames {
            #expect(matches(name), "\(name)")
            #expect(matches("alt-shift-\(name)"), "\(name)")
        }
        for bad in ["", "alt-", "hyper-a", "alt-hh", "pageUp", "f21", "keypad-", "alt--", "A"] {
            #expect(!matches(bad), "\(bad)")
        }
    }

    @Test func `Schema knows every key in the shipped config`() throws {
        #expect(Config.defaultTOML.hasPrefix("#:schema \(Self.schema["$id"] as! String)\n"))
        let root = try TOMLTable(source: Config.defaultTOML)
        let properties = Self.schema["properties"] as! [String: Any]
        func check(_ table: TOMLTable, _ schema: [String: Any], at path: String) throws {
            let known = schema["properties"] as? [String: Any] ?? [:]
            for key in table.keys {
                let here = path.isEmpty ? key : "\(path).\(key)"
                if let child = known[key] as? [String: Any] {
                    if let nested = try? table.table(forKey: key) { try check(nested, resolve(child), at: here) }
                } else {
                    #expect(schema["additionalProperties"] as? [String: Any] != nil, "\(here) is not in the schema")
                }
            }
        }
        try check(root, Self.schema, at: "")
        // Rules are an array of tables; check the first one's keys too.
        let rule = try root.array(forKey: "rules").table(atIndex: 0)
        let ruleSchema = (properties["rules"] as! [String: Any])["items"] as! [String: Any]
        try check(rule, ruleSchema, at: "rules[0]")
    }

    /// Follows a local `$ref`.
    private func resolve(_ schema: [String: Any]) -> [String: Any] {
        guard let ref = schema["$ref"] as? String, ref.hasPrefix("#/definitions/") else { return schema }
        return definitions[String(ref.dropFirst("#/definitions/".count))]!
    }
}
