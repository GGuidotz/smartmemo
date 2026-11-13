// Le regole di scrittura, a ogni tasto: niente spazio prima della punteggiatura, due spazi diventano ". ", e nelle
// riunioni la maiuscola a inizio frase. Si guarda solo il testo prima del cursore e si restituisce una modifica
// (che include il carattere battuto) oppure nil: allora il tasto fa il suo mestiere.
// Mai uno spazio aggiunto dopo la punteggiatura: romperebbe "13,5", "17:00" e gli indirizzi.
// Solo Foundation: le posizioni sono in UTF-16.

import Foundation

struct TypingOptions: Equatable {
    /// Niente spazio prima di , . ; : ! ? e due spazi diventano ". ".
    var spacing = true
    /// Maiuscola a inizio frase (solo nelle riunioni: nelle to-do si comincia con un verbo minuscolo).
    var capitalize = true
}

enum TypingRules {
    private static let closers: Set<Character> = [",", ".", ";", ":", "!", "?"]
    private static let enders: Set<Character> = [".", "!", "?"]

    /// Abbreviazioni dopo cui il punto non chiude la frase.
    private static let abbreviations: Set<String> = [
        "es", "ecc", "etc", "dott", "dr", "sig", "sigg", "ing", "avv", "prof", "proff", "dott.ssa", "p.es", "cfr", "vs",
        "pag", "pagg", "tel", "rif", "ca", "max", "min", "mr", "mrs", "ms", "eg", "ie", "no", "n", "art", "cap", "fig",
    ]

    static func edit(in text: String, caret: Int, typed: String, kind: NoteKind, options: TypingOptions) -> TextEdit? {
        guard typed.count == 1, let char = typed.first, caret > 0 else { return caret == 0 ? capitalizeAtStart(text, typed: typed, kind: kind, options: options) : nil }
        let ns = text as NSString
        guard caret <= ns.length else { return nil }
        var lineStart = 0
        ns.getLineStart(&lineStart, end: nil, contentsEnd: nil, for: NSRange(location: caret, length: 0))
        let prefix = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))

        if options.spacing {
            if closers.contains(char), let e = noSpaceBefore(prefix, lineStart: lineStart, typed: typed) { return e }
            if char == " ", let e = doubleSpace(prefix, lineStart: lineStart) { return e }
        }
        if options.capitalize, kind == .meeting, char.isLetter, char.isLowercase,
           startsSentence(prefix) {
            let upper = typed.uppercased()
            guard upper.count == 1 else { return nil }
            return TextEdit(range: NSRange(location: caret, length: 0), replacement: upper)
        }
        return nil
    }

    private static func capitalizeAtStart(_ text: String, typed: String, kind: NoteKind, options: TypingOptions) -> TextEdit? {
        guard options.capitalize, kind == .meeting, typed.count == 1, let c = typed.first, c.isLetter, c.isLowercase else { return nil }
        let upper = typed.uppercased()
        return upper.count == 1 ? TextEdit(range: NSRange(location: 0, length: 0), replacement: upper) : nil
    }

    // MARK: Regole

    /// "ciao ," → "ciao,": toglie lo spazio che sta prima. Non a inizio riga, non dopo un segno di elenco o il "✓ ".
    private static func noSpaceBefore(_ prefix: String, lineStart: Int, typed: String) -> TextEdit? {
        let chars = Array(prefix)
        guard chars.count >= 2, chars[chars.count - 1] == " ", !chars[chars.count - 2].isWhitespace else { return nil }
        if let marker = ListMarker.parse(prefix), marker.length >= (prefix as NSString).length { return nil }
        if prefix.trimmingCharacters(in: .whitespaces) == "✓" { return nil }
        let caret = lineStart + (prefix as NSString).length
        return TextEdit(range: NSRange(location: caret - 1, length: 1), replacement: typed)
    }

    /// "ciao  " → "ciao. ": il secondo spazio dopo una lettera o una cifra chiude la frase, come su iPhone.
    private static func doubleSpace(_ prefix: String, lineStart: Int) -> TextEdit? {
        let chars = Array(prefix)
        guard chars.count >= 2, chars[chars.count - 1] == " ", chars[chars.count - 2].isLetter || chars[chars.count - 2].isNumber else { return nil }
        let caret = lineStart + (prefix as NSString).length
        return TextEdit(range: NSRange(location: caret - 1, length: 1), replacement: ". ")
    }

    /// Il cursore è all'inizio di una frase: inizio riga (dopo segno di elenco, casella o titolo) o dopo ". ", "! ", "? ".
    static func startsSentence(_ prefix: String) -> Bool {
        var rest = prefix
        if let marker = ListMarker.parse(prefix) {
            rest = (prefix as NSString).substring(from: marker.length)
        } else if let range = rest.range(of: #"^#{1,6}[ \t]+"#, options: .regularExpression) {
            rest.removeSubrange(range)
        }
        if rest.isEmpty { return true }
        guard rest.hasSuffix(" ") else { return false }
        let trimmed = String(rest.dropLast())
        guard let last = trimmed.last, enders.contains(last), !rest.hasSuffix("  ") else { return false }
        if trimmed.hasSuffix("..") { return false }
        // La parola prima del punto: abbreviazioni, sigle ("M."), numeri ("3."), indirizzi e nomi di file non chiudono.
        let word = trimmed.dropLast().split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        if last == "." {
            if word.isEmpty { return false }
            if abbreviations.contains(word.lowercased()) { return false }
            if word.count == 1, word.first?.isLetter == true { return false }
            if word.contains(where: \.isNumber) { return false }
            if word.contains(".") || word.contains("/") || word.contains("@") { return false }
        }
        return true
    }
}

/// Il controllo di ciò che restituisce Apple Intelligence quando sistema la punteggiatura: si accettano solo righe con
/// le stesse parole, nello stesso ordine; cambia soltanto la punteggiatura e le maiuscole.
enum PunctuationGuard {
    private static let prefixRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:✓[ \t]*)?(?:(?:[-*•]|\d{1,3}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)?(?:#{1,6}[ \t]+)?(?:[A-ZÀ-Ý][\p{L}\p{N}&._-]{0,23}:[ \t]+)?"#)

    /// Separa i segni all'inizio della riga (✓, elenco, casella, titolo, SIGLA:) dal testo da sistemare.
    static func split(_ line: String) -> (prefix: String, body: String) {
        let ns = line as NSString
        guard let m = prefixRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return ("", line) }
        return (ns.substring(to: m.range.length), ns.substring(from: m.range.length))
    }

    /// Le lettere e le cifre, in minuscolo: devono essere identiche prima e dopo.
    private static func skeleton(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static func accepts(original: String, candidate: String) -> Bool {
        !candidate.isEmpty && skeleton(original) == skeleton(candidate)
    }

    /// Rimette i segni davanti ai testi sistemati. Se il numero di righe non torna, o una riga cambia parole, resta
    /// l'originale (per quella riga o per tutte). Nelle to-do la prima lettera mantiene la sua maiuscola o minuscola.
    static func merge(lines: [String], fixed: [String]?, keepInitialCase: Bool) -> [String] {
        guard let fixed, fixed.count == lines.count else { return lines }
        return zip(lines, fixed).map { original, candidate in
            let parts = split(original)
            var text = candidate.trimmingCharacters(in: .whitespaces)
            guard accepts(original: parts.body, candidate: text) else { return original }
            if keepInitialCase, let o = parts.body.first(where: { $0.isLetter }), let c = text.firstIndex(where: { $0.isLetter }) {
                let letter = String(text[c])
                text.replaceSubrange(c...c, with: o.isLowercase ? letter.lowercased() : letter)
            }
            return parts.prefix + text
        }
    }
}
