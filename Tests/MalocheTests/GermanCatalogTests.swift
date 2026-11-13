import Foundation
import Testing

/// S15, D7: every string of the catalog has a translated German version with the arguments of the source.
@Suite struct GermanCatalogTests {
    private typealias Object = [String: Any]

    private static var strings: [String: Object] {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/Maloche/Resources/Localizable.xcstrings")
        let catalog = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? Object
        return catalog?["strings"] as? [String: Object] ?? [:]
    }

    /// The string unit and every plural or substitution case below it.
    private static func units(_ localization: Object) -> [Object] {
        let unit = (localization["stringUnit"] as? Object).map { [$0] } ?? []
        let variations = (localization["variations"] as? [String: [String: Object]] ?? [:]).values
            .flatMap(\.values).flatMap(units)
        let substitutions = (localization["substitutions"] as? [String: Object] ?? [:]).values.flatMap(units)
        return unit + variations + substitutions
    }

    /// Argument number to type, e.g. [1: "@", 2: "lld"]; "%#@name@" takes number and type from the substitution.
    private static func arguments(_ format: String, substitutions: [String: Object] = [:]) -> [Int: String] {
        var arguments: [Int: String] = [:]
        var next = 1
        for match in format.matches(of: /%(?:(\d+)\$)?(#@(\w+)@|lld|ld|d|@)/) {
            if let name = match.3, let substitution = substitutions[String(name)] {
                arguments[substitution["argNum"] as? Int ?? 0] = substitution["formatSpecifier"] as? String
                continue
            }
            let number = match.1.flatMap { Int($0) } ?? next
            arguments[number] = String(match.2)
            next = number + 1
        }
        return arguments
    }

    @Test func theCatalogHasStrings() {
        #expect(Self.strings.count > 200)
    }

    @Test func everyStringIsTranslatedIntoGermanWithTheSameArguments() {
        for (key, entry) in Self.strings {
            let localizations = entry["localizations"] as? [String: Object] ?? [:]
            let source = (localizations["en"]?["stringUnit"] as? Object)?["value"] as? String ?? key
            guard let german = localizations["de"] else {
                Issue.record("no German for \"\(key)\"")
                continue
            }
            let substitutions = german["substitutions"] as? [String: Object] ?? [:]
            let units = Self.units(german)
            #expect(!units.isEmpty, "no German for \"\(key)\"")
            for unit in units {
                let value = unit["value"] as? String ?? ""
                #expect(unit["state"] as? String == "translated", "\"\(key)\" is not translated")
                #expect(!value.isEmpty, "\"\(key)\" is empty in German")
                // a substitution case stands for its own argument, written as %arg
                guard !value.contains("%arg") else { continue }
                #expect(
                    Self.arguments(value, substitutions: substitutions) == Self.arguments(source),
                    "\"\(key)\" has other arguments in German: \"\(value)\"")
            }
        }
    }

    @Test func germanUsesTheChosenWords() {
        let chosen = [
            "Log": "Erfassen", "Check In Now": "Jetzt erfassen", "Start": "Start",
            "Done for today": "Feierabend", "That’s it for today": "Feierabend",
            "Move to Project": "In Projekt verschieben",
            "Restore the backup from %@?": "Backup vom %@ wiederherstellen?",
            "Schedule": "Arbeitszeiten", "Back Up Now": "Backup jetzt erstellen",
        ]
        for (key, expected) in chosen {
            let german = (Self.strings[key]?["localizations"] as? [String: Object])?["de"]
            let value = (german?["stringUnit"] as? Object)?["value"] as? String
            #expect(value == expected, "\(key)")
        }
    }

    @Test func germanCopyStaysPositiveAndCalm() {
        let forbidden = ["offen", "fehlend", "fehlt", "verloren", "lücke", "nicht zugeordnet", "countdown", "·"]
        for (key, entry) in Self.strings {
            guard let german = (entry["localizations"] as? [String: Object])?["de"] else { continue }
            for value in Self.units(german).compactMap({ $0["value"] as? String }) {
                let lowered = value.lowercased()
                for word in forbidden where lowered.contains(word) {
                    Issue.record("\"\(key)\" says \"\(word)\" in German: \"\(value)\"")
                }
            }
        }
    }
}
