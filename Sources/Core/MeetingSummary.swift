// Il riassunto esecutivo in cima a una nota di riunione. Sta nel file come Markdown normale, tra due commenti HTML
// che nessun lettore Markdown mostra:
//
//   <!-- riassunto apple-intelligence -->     ("<!-- riassunto -->" se fatto con le regole)
//   **Sintesi.** Proposta da chiudere entro fine mese; Luca riscrive introduzione e conclusioni.
//   **Prossimo incontro:** 12 marzo alle 10:00
//   **Scadenze:** proposta chiusa entro fine mese
//   - [ ] Riscrivere l'introduzione della proposta · Luca
//   - [ ] Rivedere le conclusioni · Luca
//   <!-- /riassunto -->
//
// L'editor nasconde i commenti e disegna il blocco come un riquadro. Le caselle sono to-do vere: finiscono in Oggi
// e nel progetto della riunione. Lo scrive Apple Intelligence; senza, un riassunto più semplice fatto con le regole.

import Foundation

struct MeetingSummary: Equatable {
    struct Action: Equatable {
        var text: String
        var owner: String?
    }

    var synthesis: String = ""
    var nextMeeting: String?
    var deadlines: [String] = []
    var actions: [Action] = []
    /// Fatto da Apple Intelligence o dalle regole.
    var byAI = false

    /// L'apertura dice anche chi l'ha scritto: "<!-- riassunto -->" o "<!-- riassunto apple-intelligence -->".
    static let open = "<!-- riassunto"
    static let openAI = "<!-- riassunto apple-intelligence -->"
    static let openPlain = "<!-- riassunto -->"
    static let close = "<!-- /riassunto -->"

    var markdown: String {
        var lines = [byAI ? Self.openAI : Self.openPlain]
        if !synthesis.isEmpty { lines.append("**" + L("Sintesi.") + "** " + synthesis) }
        if let nextMeeting, !nextMeeting.isEmpty { lines.append("**" + L("Prossimo incontro:") + "** " + nextMeeting) }
        if !deadlines.isEmpty { lines.append("**" + L("Scadenze:") + "** " + deadlines.joined(separator: "; ")) }
        for a in actions {
            lines.append("- [ ] " + a.text + (a.owner.map { " · " + $0 } ?? ""))
        }
        lines.append(Self.close)
        return lines.joined(separator: "\n")
    }

    // MARK: Il blocco nel testo

    /// Dove sta il blocco del riassunto (righe dei commenti comprese, con l'a capo finale).
    static func blockRange(in text: String) -> NSRange? {
        let ns = text as NSString
        let start = ns.range(of: open)
        guard start.location != NSNotFound else { return nil }
        let end = ns.range(of: close, range: NSRange(location: start.upperBound, length: ns.length - start.upperBound))
        guard end.location != NSNotFound else { return nil }
        var upper = end.upperBound
        if upper < ns.length, ns.character(at: upper) == 10 { upper += 1 }
        return NSRange(location: start.location, length: upper - start.location)
    }

    /// Il testo con il riassunto messo (o rimesso) dopo la riga del titolo e quella della data.
    static func insert(_ summary: MeetingSummary, into text: String) -> String {
        let clean = remove(from: text)
        let ns = clean as NSString
        // Dopo le prime due righe (titolo, data) se ci sono.
        var location = 0
        for _ in 0..<2 where location < ns.length {
            var end = 0
            ns.getLineStart(nil, end: &end, contentsEnd: nil, for: NSRange(location: location, length: 0))
            location = end
        }
        var head = ns.substring(to: location)
        if !head.isEmpty, !head.hasSuffix("\n") { head += "\n" }
        let tail = ns.substring(from: location)
        return head + summary.markdown + "\n" + (tail.hasPrefix("\n") ? tail : "\n" + tail)
    }

    static func remove(from text: String) -> String {
        guard let r = blockRange(in: text) else { return text }
        let ns = NSMutableString(string: text)
        ns.deleteCharacters(in: r)
        // Via anche la riga vuota che lo separava dal testo, se ne resterebbero due di fila.
        if r.location + 1 < ns.length, ns.character(at: r.location) == 10, ns.character(at: r.location + 1) == 10 {
            ns.deleteCharacters(in: NSRange(location: r.location, length: 1))
        }
        return ns as String
    }

    /// Il riassunto nel testo l'ha scritto Apple Intelligence.
    static func isByAI(_ text: String) -> Bool { text.contains(openAI) }

    /// Il testo della riunione senza il riassunto: è quello che si riassume.
    static func body(of text: String) -> String { remove(from: text) }

    // MARK: Risposta di Apple Intelligence

    /// Legge la risposta nel formato chiesto:
    ///   SINTESI: …
    ///   PROSSIMO: …   (o "nessuno")
    ///   SCADENZE: …; …
    ///   - azione | responsabile
    static func parse(_ response: String) -> MeetingSummary {
        var s = MeetingSummary(byAI: true)
        for raw in response.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
            guard !line.isEmpty else { continue }
            if let v = value(line, "SINTESI") {
                s.synthesis = v
            } else if let v = value(line, "PROSSIMO") {
                s.nextMeeting = isNone(v) ? nil : v
            } else if let v = value(line, "SCADENZE") {
                s.deadlines = isNone(v) ? [] : v.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else if let first = line.first, first == "-" || first == "•" || first == "*" {
                let item = line.dropFirst().trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "[ ]", with: "").trimmingCharacters(in: .whitespaces)
                let parts = item.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let text = parts.first, !text.isEmpty else { continue }
                let owner = parts.count > 1 && !isNone(parts[1]) ? parts[1] : nil
                s.actions.append(Action(text: text, owner: owner))
            }
        }
        return s
    }

    private static func value(_ line: String, _ key: String) -> String? {
        guard line.uppercased().hasPrefix(key), let colon = line.firstIndex(of: ":") else { return nil }
        return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    private static func isNone(_ v: String) -> Bool {
        let l = v.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        return l.isEmpty || ["nessuno", "nessuna", "none", "n/a", "no"].contains(l)
    }

    // MARK: Senza Apple Intelligence

    /// Un riassunto fatto con le regole: le righe numerate o a elenco diventano to-do (con il nome tra parentesi come
    /// responsabile), la prima data dopo "prossimo" è il prossimo incontro, le frasi con "entro" sono scadenze.
    static func fallback(for text: String, knowledge: Knowledge) -> MeetingSummary {
        var s = MeetingSummary()
        let body = Self.body(of: text)
        let lines = body.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let numbered = try! NSRegularExpression(pattern: #"^(?:\d{1,2}[.)]|[-*•])[ \t]+(?!\[)(.+)$"#)
        let owner = try! NSRegularExpression(pattern: #"\(([\p{Lu}][\p{L}'’ -]{1,40})\)\s*$"#)
        for line in lines.dropFirst(2) {
            let ns = line as NSString
            guard let m = numbered.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            var item = ns.substring(with: m.range(at: 1))
            var who: String?
            let ins = item as NSString
            if let o = owner.firstMatch(in: item, range: NSRange(location: 0, length: ins.length)) {
                who = ins.substring(with: o.range(at: 1)).trimmingCharacters(in: .whitespaces)
                item = ins.substring(to: o.range.location).trimmingCharacters(in: .whitespaces)
            }
            if item.count > 140 { item = String(item.prefix(137)) + "…" }
            s.actions.append(Action(text: item, owner: who))
        }
        let dates = EntityRecognizer.entities(in: body, kind: .meeting, knowledge: knowledge).filter { $0.kind == .date }
        let nsBody = body as NSString
        let next = nsBody.range(of: "prossim", options: .caseInsensitive).location
        if next != NSNotFound {
            s.nextMeeting = dates.first { $0.range.location > next }?.text
        }
        s.deadlines = dates.filter { $0.text.lowercased().hasPrefix("entro") }.map(\.text)
        if s.actions.isEmpty {
            s.synthesis = L("Nessuna riga numerata o a elenco da trasformare in to-do.")
        }
        return s
    }
}
