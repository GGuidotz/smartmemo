// Gli elenchi Markdown mentre scrivi (nelle riunioni): Invio continua l'elenco, Invio su una voce vuota lo chiude,
// Tab e Maiusc-Tab annidano, i numeri si rinumerano da soli. Il file resta Markdown puro: "- ", "1. " e "- [ ] ".
// Solo Foundation: tutte le posizioni sono in UTF-16 (NSString), come vuole AppKit.

import Foundation

/// Una modifica al testo: sostituisce `range` con `replacement`.
struct TextEdit: Equatable {
    var range: NSRange
    var replacement: String

    /// Dove sta il cursore dopo la modifica.
    var caretAfter: Int { range.location + (replacement as NSString).length }

    /// La modifica minima che porta `old` a `new`: toglie il prefisso e il suffisso in comune.
    static func diff(from old: String, to new: String) -> TextEdit? {
        let a = Array(old.utf16), b = Array(new.utf16)
        guard a != b else { return nil }
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let replacement = String(decoding: b[prefix..<(b.count - suffix)], as: UTF16.self)
        return TextEdit(range: NSRange(location: prefix, length: a.count - prefix - suffix), replacement: replacement)
    }

    func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

/// Il segno di elenco all'inizio di una riga.
struct ListMarker: Equatable {
    enum Kind: Equatable {
        case bullet(Character)
        case number(Int, Character)
        case box(Character)
    }

    var indent: String
    var kind: Kind
    /// Dall'inizio della riga alla fine del segno (rientro, segno e spazi dopo), in UTF-16.
    var length: Int

    /// Il rientro in colonne (il tab vale 4).
    var indentWidth: Int { indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }

    var isNumbered: Bool { if case .number = kind { true } else { false } }

    /// Il segno come si scrive, senza il rientro: "- ", "3. ", "- [ ] ".
    var text: String {
        switch kind {
        case .bullet(let c): "\(c) "
        case .number(let n, let d): "\(n)\(d) "
        case .box(let c): "\(c) [ ] "
        }
    }

    /// Il segno della voce che segue.
    var next: ListMarker {
        var m = self
        switch kind {
        case .bullet: break
        case .number(let n, let d): m.kind = .number(n + 1, d)
        case .box(let c): m.kind = .box(c)
        }
        return m
    }

    /// Il segno come sta scritto nella riga (con la casella spuntata o no), senza il rientro.
    func written(in line: String) -> String {
        let start = (indent as NSString).length
        return (line as NSString).substring(with: NSRange(location: start, length: length - start))
    }

    private static let boxRegex = try! NSRegularExpression(pattern: #"^([ \t]*)([-*])[ \t]+\[[ xX]\][ \t]+"#)
    // Il segno è seguito da uno spazio: "---" e "**grassetto**" non sono elenchi.
    private static let markerRegex = try! NSRegularExpression(pattern: #"^([ \t]*)(?:([-*•])|(\d{1,3})([.)]))[ \t]+"#)

    static func parse(_ line: String) -> ListMarker? {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        if let m = boxRegex.firstMatch(in: line, range: whole) {
            return ListMarker(indent: ns.substring(with: m.range(at: 1)),
                              kind: .box(Character(ns.substring(with: m.range(at: 2)))), length: m.range.length)
        }
        guard let m = markerRegex.firstMatch(in: line, range: whole) else { return nil }
        let indent = ns.substring(with: m.range(at: 1))
        if m.range(at: 2).location != NSNotFound {
            return ListMarker(indent: indent, kind: .bullet(Character(ns.substring(with: m.range(at: 2)))), length: m.range.length)
        }
        guard let n = Int(ns.substring(with: m.range(at: 3))) else { return nil }
        return ListMarker(indent: indent, kind: .number(n, Character(ns.substring(with: m.range(at: 4)))), length: m.range.length)
    }
}

enum ListEditing {
    static let indentUnit = "    "

    // MARK: Invio

    /// Invio dentro una voce di elenco: continua l'elenco, oppure (voce vuota) lo chiude o lo porta un livello fuori.
    /// Nil se il cursore non è in una voce, o è dentro il segno: allora Invio fa il suo mestiere.
    static func newline(in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        guard selection.location <= ns.length else { return nil }
        var start = 0, contentsEnd = 0
        ns.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: selection.location, length: 0))
        let line = ns.substring(with: NSRange(location: start, length: contentsEnd - start))
        guard let marker = ListMarker.parse(line), selection.location >= start + marker.length else { return nil }

        let rest = (line as NSString).substring(from: marker.length).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty, selection.length == 0, selection.location == contentsEnd {
            // Voce vuota: Invio esce dall'elenco (o sale di un livello).
            var outer = marker
            if marker.indentWidth > 0 {
                outer.indent = outdented(marker.indent)
                return TextEdit(range: NSRange(location: start, length: contentsEnd - start), replacement: outer.indent + marker.text)
            }
            return TextEdit(range: NSRange(location: start, length: contentsEnd - start), replacement: "")
        }
        let next = marker.next
        return TextEdit(range: selection, replacement: "\n" + next.indent + next.text)
    }

    // MARK: Tab

    /// Tab (`deeper`) o Maiusc-Tab sulle voci di elenco toccate dalla selezione. Nil se nessuna riga è una voce.
    static func shift(in text: String, selection: NSRange, deeper: Bool) -> TextEdit? {
        let ns = text as NSString
        guard selection.location <= ns.length else { return nil }
        let last = selection.length > 0 ? selection.upperBound - 1 : selection.location
        var firstStart = 0, lastEnd = 0
        ns.getLineStart(&firstStart, end: nil, contentsEnd: nil, for: NSRange(location: selection.location, length: 0))
        ns.getLineStart(nil, end: &lastEnd, contentsEnd: nil, for: NSRange(location: min(last, ns.length), length: 0))
        let lines = NSRange(location: firstStart, length: lastEnd - firstStart)
        var result = ""
        var changed = false
        var location = lines.location
        while location < lines.upperBound {
            var lineEnd = 0, contentsEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let line = ns.substring(with: NSRange(location: location, length: contentsEnd - location))
            let terminator = ns.substring(with: NSRange(location: contentsEnd, length: lineEnd - contentsEnd))
            if let marker = ListMarker.parse(line) {
                var moved = marker
                if deeper {
                    moved.indent = marker.indent + indentUnit
                    if case .number(_, let d) = marker.kind { moved.kind = .number(1, d) }
                } else {
                    moved.indent = outdented(marker.indent)
                }
                if moved.indent != marker.indent {
                    changed = true
                    let sign = deeper && marker.isNumbered ? moved.text : marker.written(in: line)
                    result += moved.indent + sign + (line as NSString).substring(from: marker.length) + terminator
                    location = lineEnd
                    continue
                }
            }
            result += line + terminator
            location = lineEnd
        }
        guard changed else { return nil }
        return TextEdit(range: lines, replacement: result)
    }

    private static func outdented(_ indent: String) -> String {
        if indent.hasSuffix("\t") { return String(indent.dropLast()) }
        return String(indent.dropLast(min(indentUnit.count, indent.count)))
    }

    // MARK: Numeri

    /// Rinumera il blocco di elenco che contiene `position`: le voci numerate allo stesso livello diventano consecutive
    /// (la prima tiene il suo numero). Il resto del testo non si tocca.
    static func renumbered(_ text: String, around position: Int) -> String {
        let ns = text as NSString
        guard position <= ns.length else { return text }
        // I confini del blocco: righe consecutive che sono voci di elenco.
        var lineStarts: [Int] = []
        var location = 0
        while location < ns.length {
            lineStarts.append(location)
            var lineEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: nil, for: NSRange(location: location, length: 0))
            location = lineEnd
        }
        if lineStarts.isEmpty { return text }
        func isItem(_ i: Int) -> Bool {
            var contentsEnd = 0
            ns.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: lineStarts[i], length: 0))
            return ListMarker.parse(ns.substring(with: NSRange(location: lineStarts[i], length: contentsEnd - lineStarts[i]))) != nil
        }
        var current = lineStarts.lastIndex { $0 <= position } ?? 0
        if !isItem(current) {
            // Il cursore può stare in fondo a una riga vuota appena creata: prova la riga prima.
            guard current > 0, isItem(current - 1) else { return text }
            current -= 1
        }
        var first = current, last = current
        while first > 0, isItem(first - 1) { first -= 1 }
        while last + 1 < lineStarts.count, isItem(last + 1) { last += 1 }

        var counters: [Int: Int] = [:]
        var result = ""
        var cursor = lineStarts[first]
        for i in first...last {
            var lineEnd = 0, contentsEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStarts[i], length: 0))
            let line = ns.substring(with: NSRange(location: lineStarts[i], length: contentsEnd - lineStarts[i]))
            let terminator = ns.substring(with: NSRange(location: contentsEnd, length: lineEnd - contentsEnd))
            guard var marker = ListMarker.parse(line) else { continue }
            let width = marker.indentWidth
            for key in counters.keys where key > width { counters[key] = nil }
            if case .number(let n, let d) = marker.kind {
                let expected = counters[width].map { $0 + 1 } ?? n
                counters[width] = expected
                marker.kind = .number(expected, d)
            } else {
                counters[width] = nil
            }
            let sign = marker.isNumbered ? marker.text : marker.written(in: line)
            result += marker.indent + sign + (line as NSString).substring(from: marker.length) + terminator
            cursor = lineEnd
        }
        let blockRange = NSRange(location: lineStarts[first], length: cursor - lineStarts[first])
        return ns.replacingCharacters(in: blockRange, with: result)
    }

    /// Una modifica di elenco con i numeri a posto, come una modifica sola, e dove va il cursore.
    /// `caretAfterEdit` è la posizione del cursore nel testo dopo la modifica (prima di rinumerare).
    static func resolve(_ edit: TextEdit, in text: String, caretAfterEdit: Int) -> (edit: TextEdit, caret: Int) {
        let after = edit.applied(to: text)
        let fixed = renumbered(after, around: caretAfterEdit)
        guard fixed != after, let combined = TextEdit.diff(from: text, to: fixed) else { return (edit, caretAfterEdit) }
        return (combined, mapCaret(caretAfterEdit, from: after, to: fixed))
    }

    /// Porta una posizione da un testo a un altro con le stesse righe, dove cambia solo l'inizio delle righe: la distanza
    /// dalla fine della riga resta quella.
    static func mapCaret(_ caret: Int, from old: String, to new: String) -> Int {
        let a = old as NSString, b = new as NSString
        let caret = min(caret, a.length)
        var line = 0
        var location = 0
        while true {
            let r = a.range(of: "\n", options: [], range: NSRange(location: location, length: caret - location))
            if r.location == NSNotFound { break }
            line += 1
            location = r.upperBound
        }
        let next = a.range(of: "\n", options: [], range: NSRange(location: caret, length: a.length - caret))
        let distance = (next.location == NSNotFound ? a.length : next.location) - caret
        // La stessa riga nel testo nuovo.
        var start = 0
        for _ in 0..<line {
            let r = b.range(of: "\n", options: [], range: NSRange(location: start, length: b.length - start))
            if r.location == NSNotFound { return b.length }
            start = r.upperBound
        }
        let end = b.range(of: "\n", options: [], range: NSRange(location: start, length: b.length - start))
        return max(start, (end.location == NSNotFound ? b.length : end.location) - distance)
    }
}
