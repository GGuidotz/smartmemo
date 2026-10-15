// Legge una pagina di to-do scritta come la scrive Giulio:
//
//   SITO: chiama Marta, manda il preventivo a Nexa
//   -------------
//   BANDO: carica i documenti in cartella
//   rispondi a Studio Rossi sul preventivo
//
// `SIGLA:` a inizio riga apre il blocco di un progetto; le righe dopo restano in quel progetto fino a un separatore
// (tre o più trattini) o alla sigla successiva. Ogni riga non vuota è una to-do. Una to-do fatta comincia con "✓ ":
// è l'unico segno che l'app aggiunge al testo, così il file resta leggibile ovunque. URGENTE la porta in cima.
// Valgono anche le caselle Markdown "- [ ] " e "- [x] ": nelle riunioni sono le sole to-do (le scrive il riassunto).
// Tutte le posizioni sono in UTF-16 (NSString), come vuole AppKit.

import Foundation

struct ParsedLine: Hashable {
    enum Kind: Hashable { case task, separator, blank, header, text }

    var kind: Kind
    /// La riga senza a capo.
    var range: NSRange
    var project: String?
    /// La sigla scritta su questa riga (senza i due punti).
    var projectRange: NSRange?
    /// "SITO: " con due punti e spazi.
    var prefixRange: NSRange?
    var doneMarkRange: NSRange?
    /// La casella Markdown "- [ ] " o "- [x] ", se la riga ne ha una.
    var boxRange: NSRange?
    var boxDone = false
    var urgentRanges: [NSRange] = []
    /// Il testo da mostrare nelle liste.
    var body: String = ""

    var done: Bool { doneMarkRange != nil || boxDone }
    var urgent: Bool { !urgentRanges.isEmpty }
}

enum TodoParser {
    static let doneMark = "✓ "

    // Sigla: comincia con una maiuscola, poi lettere, cifre o & . _ - (fino a 24), poi i due punti seguiti da spazio o
    // fine riga (così "ore 17:00" non è un progetto).
    private static let prefixRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*([A-ZÀ-Ý][\p{L}\p{N}&._-]{0,23})[ \t]*:(?=[ \t]|$)[ \t]*"#)
    static let boxRegex = try! NSRegularExpression(pattern: #"^[ \t]*[-*][ \t]+\[([ xX])\][ \t]+"#)
    private static let hashtagRegex = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}#])#([\p{L}][\p{L}\p{N}_-]{0,23})"#)
    private static let separatorRegex = try! NSRegularExpression(pattern: #"^[ \t]*[-–—_=*]{3,}[ \t]*$"#)
    /// URGENTE in maiuscolo, oppure "urgente!" con il punto esclamativo, in qualsiasi forma.
    static let urgentRegex = try! NSRegularExpression(
        pattern: #"(?<![\p{L}])(?:URGENTE|(?i:urgente)(?=!))!*(?![\p{L}])"#)

    /// Parole che non sono sigle anche se stanno prima dei due punti.
    private static let notSigla: Set<String> = ["URGENTE", "Nota", "Note", "NB", "PS", "Oggi", "Domani", "Ore", "Re", "Fw", "Fwd"]

    static func parse(_ text: String, knowledge: Knowledge = Knowledge()) -> [ParsedLine] {
        let ns = text as NSString
        var result: [ParsedLine] = []
        var current: String?
        var location = 0
        while location < ns.length {
            var lineEnd = 0, contentsEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let range = NSRange(location: location, length: contentsEnd - location)
            result.append(parseLine(ns, range: range, current: &current, knowledge: knowledge))
            location = lineEnd
        }
        return result
    }

    private static func parseLine(_ ns: NSString, range: NSRange, current: inout String?, knowledge: Knowledge) -> ParsedLine {
        let line = ns.substring(with: range)
        var parsed = ParsedLine(kind: .task, range: range, project: current)
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            parsed.kind = .blank
            return parsed
        }
        let whole = NSRange(location: 0, length: (line as NSString).length)
        if separatorRegex.firstMatch(in: line, range: whole) != nil {
            current = nil
            parsed.kind = .separator
            parsed.project = nil
            return parsed
        }

        var offset = 0   // dove comincia il testo dopo il segno di fatto
        if line.hasPrefix("✓") {
            let markLength = line.hasPrefix(doneMark) ? (doneMark as NSString).length : 1
            parsed.doneMarkRange = NSRange(location: range.location, length: markLength)
            offset = markLength
        }

        if let box = boxRegex.firstMatch(in: line, range: NSRange(location: offset, length: whole.length - offset)) {
            parsed.boxRange = NSRange(location: range.location + box.range.location, length: box.range.length)
            parsed.boxDone = (line as NSString).substring(with: box.range(at: 1)) != " "
            offset = box.range.upperBound
        }

        let rest = NSRange(location: offset, length: whole.length - offset)
        if let m = prefixRegex.firstMatch(in: line, range: rest) {
            let sigla = (line as NSString).substring(with: m.range(at: 1))
            if isSigla(sigla, knowledge: knowledge) {
                current = sigla
                parsed.project = sigla
                parsed.projectRange = NSRange(location: range.location + m.range(at: 1).location, length: m.range(at: 1).length)
                parsed.prefixRange = NSRange(location: range.location + m.range.location, length: m.range.length)
                if m.range.upperBound >= whole.length { parsed.kind = .header }
            }
        }
        if parsed.kind == .task, line.hasPrefix("# ") || line == "#" {
            parsed.kind = .header
        }

        parsed.urgentRanges = urgentRegex.matches(in: line, range: whole).map {
            NSRange(location: range.location + $0.range.location, length: $0.range.length)
        }
        parsed.body = body(of: line, lineStart: range.location, parsed: parsed)
        return parsed
    }

    /// Una nota di riunione: solo le righe con la casella sono to-do, tutte del progetto della riunione (il primo
    /// #hashtag delle prime righe).
    static func parseMeeting(_ text: String) -> [ParsedLine] {
        let project = meetingProject(text)
        return parse(text).map { line in
            var l = line
            l.projectRange = nil
            l.prefixRange = nil
            if l.kind == .task || l.kind == .header {
                if l.boxRange != nil {
                    l.kind = .task
                    l.project = project
                } else {
                    l.kind = .text
                    l.project = nil
                }
            }
            if l.kind == .separator || l.kind == .blank { l.project = nil }
            return l
        }
    }

    /// Il progetto di una riunione: il primo #hashtag nelle prime tre righe.
    static func meetingProject(_ text: String) -> String? {
        let head = text.split(separator: "\n", maxSplits: 3, omittingEmptySubsequences: false).prefix(3).joined(separator: "\n")
        let ns = head as NSString
        guard let m = hashtagRegex.firstMatch(in: head, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    static func isSigla(_ s: String, knowledge: Knowledge) -> Bool {
        !notSigla.contains(s) && !knowledge.isIgnoredProject(s) && !knowledge.people.contains(s)
    }

    /// Il testo della to-do senza segno di fatto, sigla e URGENTE, senza virgole in coda.
    private static func body(of line: String, lineStart: Int, parsed: ParsedLine) -> String {
        let ns = NSMutableString(string: line)
        var cuts: [NSRange] = parsed.urgentRanges
        if let p = parsed.prefixRange { cuts.append(p) }
        if let d = parsed.doneMarkRange { cuts.append(d) }
        if let b = parsed.boxRange { cuts.append(b) }
        for r in cuts.sorted(by: { $0.location > $1.location }) {
            ns.replaceCharacters(in: NSRange(location: r.location - lineStart, length: r.length), with: " ")
        }
        let collapsed = (ns as String).split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " ,;").union(.whitespaces))
    }

    // MARK: Divisione alle virgole

    /// "SITO: chiama Marta, manda il preventivo a Nexa" → ["SITO: chiama Marta", "manda il preventivo a Nexa"].
    /// Divide solo dove dopo la virgola comincia un'azione (un verbo), così "Sara, Marco e Marta" o "13,5" restano
    /// interi. Nil se non c'è niente da dividere.
    static func splitSegments(_ line: String) -> [String]? {
        let parts = line.components(separatedBy: ",")
        guard parts.count > 1 else { return nil }
        var segments = [parts[0]]
        for part in parts.dropFirst() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }   // virgola in fondo
            if startsWithAction(trimmed) {
                segments.append(trimmed)
            } else {
                segments[segments.count - 1] += "," + part
            }
        }
        guard segments.count > 1 else { return nil }
        return segments.map { trimTrailing($0) }
    }

    private static func trimTrailing(_ s: String) -> String {
        var s = s
        while let last = s.last, last == " " || last == "\t" || last == "," { s.removeLast() }
        return s
    }

    static func startsWithAction(_ segment: String) -> Bool {
        var words = segment.split(separator: " ").map(String.init)
        // "URGENTE! manda mail…": conta la parola dopo.
        while let first = words.first,
              urgentRegex.firstMatch(in: first, range: NSRange(location: 0, length: (first as NSString).length)) != nil {
            words.removeFirst()
        }
        guard let first = words.first else { return false }
        let word = first.trimmingCharacters(in: .punctuationCharacters)
        guard let initial = word.first, initial.isLowercase || ItalianVerbs.all.contains(word.lowercased()) else {
            return false
        }
        return ItalianVerbs.all.contains(word.lowercased()) || ItalianVerbs.looksLikeVerb(word, in: words.joined(separator: " "))
    }
}
