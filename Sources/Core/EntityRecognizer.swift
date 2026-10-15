// Trova nel testo progetti, persone (e clienti), date e URGENTE, a ogni tasto: niente modello generativo qui, solo
// regole, ciò che l'app ha imparato e il riconoscimento dei nomi di Apple (NaturalLanguage), tutto sul Mac e in pochi
// millisecondi. Apple Intelligence arriva con i riassunti delle riunioni, quando chi scrive si ferma.
//
// Priorità quando due risultati si sovrappongono: URGENTE, progetto, data, persona.

import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

enum EntityKind: String, Codable, Hashable {
    case project, person, date, urgent
}

struct Entity: Hashable {
    let kind: EntityKind
    let range: NSRange
    let text: String

    /// Il nome con cui l'app lo ricorda: la sigla senza #, il nome com'è scritto.
    var name: String {
        kind == .project && text.hasPrefix("#") ? String(text.dropFirst()) : text
    }
}

enum EntityRecognizer {
    static func entities(in text: String, kind: NoteKind, lines: [ParsedLine]? = nil, knowledge: Knowledge) -> [Entity] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }
        let lines = lines ?? (kind == .todo ? TodoParser.parse(text, knowledge: knowledge) : TodoParser.parseMeeting(text))
        var candidates: [Entity] = []
        func add(_ kind: EntityKind, _ range: NSRange) {
            guard range.length > 0, range.upperBound <= ns.length else { return }
            candidates.append(Entity(kind: kind, range: range, text: ns.substring(with: range)))
        }

        // URGENTE
        for m in TodoParser.urgentRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) { add(.urgent, m.range) }

        // Progetti: sigla a inizio riga (solo nelle to-do), #hashtag, sigle già note scritte nel testo.
        for line in lines { if let r = line.projectRange { add(.project, r) } }
        for m in hashtagRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let sigla = ns.substring(with: m.range(at: 1))
            if !knowledge.isIgnoredProject(sigla) { add(.project, m.range) }
        }
        if let known = wordsRegex(knowledge.projects.filter { $0.count >= 2 }, caseSensitive: true) {
            for m in known.matches(in: text, range: NSRange(location: 0, length: ns.length)) { add(.project, m.range) }
        }

        // Date e orari
        for regex in dateRegexes {
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) { add(.date, m.range) }
        }

        // Persone e clienti
        for r in people(in: text, knowledge: knowledge) { add(.person, r) }

        return resolve(candidates, knowledge: knowledge)
    }

    /// Le persone trovate in `text`, da ricordare quando la nota si salva.
    static func peopleNames(in text: String, knowledge: Knowledge) -> [String] {
        entities(in: text, kind: .meeting, knowledge: knowledge).filter { $0.kind == .person }.map(\.name)
    }

    // MARK: Sovrapposizioni

    private static func priority(_ k: EntityKind) -> Int {
        switch k {
        case .urgent: 4
        case .project: 3
        case .date: 2
        case .person: 1
        }
    }

    private static func resolve(_ candidates: [Entity], knowledge: Knowledge) -> [Entity] {
        let sorted = candidates.sorted {
            if priority($0.kind) != priority($1.kind) { return priority($0.kind) > priority($1.kind) }
            return $0.range.length > $1.range.length
        }
        var accepted: [Entity] = []
        for e in sorted {
            if e.kind == .person, knowledge.isIgnoredPerson(e.text) { continue }
            if accepted.contains(where: { NSIntersectionRange($0.range, e.range).length > 0 }) { continue }
            accepted.append(e)
        }
        return accepted.sorted { $0.range.location < $1.range.location }
    }

    // MARK: Persone

    private static func people(in text: String, knowledge: Knowledge) -> [NSRange] {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        var found: [NSRange] = []

        // Già conosciute, ovunque.
        if let known = wordsRegex(knowledge.people, caseSensitive: true) {
            found += known.matches(in: text, range: all).map(\.range)
        }

        // Dopo le parole che annunciano una persona: "chiama Marta", "sollecito a Sara", "rispondi a Studio Rossi".
        for m in triggerRegex.matches(in: text, range: all) {
            let r = m.range(at: 1)
            if isPlausibleName(ns.substring(with: r), knowledge: knowledge) { found.append(r) }
        }

        // Tra parentesi, come il responsabile nelle riunioni: "(Luca)".
        for m in parenthesisRegex.matches(in: text, range: all) {
            let r = m.range(at: 1)
            if isPlausibleName(ns.substring(with: r), knowledge: knowledge) { found.append(r) }
        }

        // Il riconoscimento dei nomi di Apple.
        #if canImport(NaturalLanguage)
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.setLanguage(.italian, range: text.startIndex..<text.endIndex)
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if tag == .personalName || tag == .organizationName {
                let r = NSRange(range, in: text)
                if isPlausibleName(ns.substring(with: r), knowledge: knowledge) { found.append(r) }
            }
            return true
        }
        #endif
        return found
    }

    /// Una maiuscola, non una sigla tutta maiuscola (PDF, API), non un mese o un giorno, non un progetto.
    private static func isPlausibleName(_ s: String, knowledge: Knowledge) -> Bool {
        guard let first = s.first, first.isUppercase, s.count >= 2 else { return false }
        if knowledge.people.contains(s) { return true }
        let letters = s.filter(\.isLetter)
        if letters.count >= 2, letters == letters.uppercased() { return false }
        if knowledge.isProject(s) || knowledge.isIgnoredPerson(s) { return false }
        return !notNames.contains(s.lowercased())
    }

    private static let notNames: Set<String> = [
        "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre",
        "novembre", "dicembre", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato", "domenica",
        "oggi", "domani", "urgente", "word", "excel", "powerpoint", "teams", "zoom", "pdf", "mail", "email",
    ]

    // MARK: Espressioni

    private static let hashtagRegex = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}#])#([\p{L}][\p{L}\p{N}_-]{0,23})"#)

    /// Un nome: parole con la maiuscola, unite da di/del/della/de/da/van/von (al massimo quattro).
    private static let name = #"\p{Lu}[\p{L}'’-]+(?:[ \t]+(?:(?:di|del|della|dei|de|da|van|von|y)[ \t]+)?\p{Lu}[\p{L}'’-]+){0,3}"#

    private static let triggerRegex = try! NSRegularExpression(pattern:
        #"(?i:\b(?:chiama|chiamare|richiama|senti|sentire|contatta|contattare|telefona|scrivi|scrivere|"# +
        #"rispondi|rispondere|sollecita|sollecitare|sollecito|incontra|incontro|call|riunione|meeting|"# +
        #"collega|cliente|con|a|ad|da|per)[ \t]+(?:(?:a|ad|al|alla|con|il|la|lo|l')[ \t]+)?)("# + EntityRecognizer.name + ")")

    private static let parenthesisRegex = try! NSRegularExpression(pattern: #"\((\p{Lu}[\p{L}'’-]+(?:[ \t]+\p{Lu}[\p{L}'’-]+)?)\)"#)

    private static let months = "gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre|" +
        "gen|feb|mar|apr|mag|giu|lug|ago|set|ott|nov|dic"
    private static let weekdays = "lunedì|martedì|mercoledì|giovedì|venerdì|sabato|domenica|lunedi|martedi|mercoledi|giovedi|venerdi"
    private static let time = #"(?:[ \t]+(?:alle|ore|h)[ \t]*\d{1,2}(?:[:.]\d{2})?)"#

    private static let dateRegexes: [NSRegularExpression] = {
        let patterns: [String] = [
            // 12 marzo, 3 marzo 2027, 12 mar alle 10:00
            #"(?i)\b\d{1,2}[ \t]+(?:"# + EntityRecognizer.months + #")\b\.?(?:[ \t]+\d{4})?"# + EntityRecognizer.time + "?",
            // giovedì, giovedì 15, venerdì alle 10
            #"(?i)\b(?:"# + EntityRecognizer.weekdays + #")(?![\p{L}])(?:[ \t]+\d{1,2})?"# + EntityRecognizer.time + "?",
            // oggi, domani, stasera…
            #"(?i)\b(?:oggi|domani|dopodomani|stasera|stamattina|stamani)\b"# + EntityRecognizer.time + "?",
            // fine mese, entro inizio aprile, metà settimana
            #"(?i)\b(?:entro[ \t]+)?(?:la[ \t]+)?(?:fine|inizio|metà)[ \t]+(?:di[ \t]+)?(?:"# + EntityRecognizer.months + #"|settimana|mese|anno)\b"#,
            // 15/10, 15/10/2026
            #"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#,
            // alle 17:00, ore 9.30
            #"(?i)\b(?:alle|ore)[ \t]*\d{1,2}[:.]\d{2}\b"#,
        ]
        return patterns.map { try! NSRegularExpression(pattern: $0) }
    }()

    /// Un'espressione che trova le parole intere di `words` (le più lunghe prima). Nil se l'elenco è vuoto.
    private static func wordsRegex(_ words: [String], caseSensitive: Bool) -> NSRegularExpression? {
        let list = words.filter { !$0.isEmpty }.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
        guard !list.isEmpty else { return nil }
        let pattern = #"(?<![\p{L}\p{N}])(?:"# + list.joined(separator: "|") + #")(?![\p{L}\p{N}])"#
        return try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
    }
}
