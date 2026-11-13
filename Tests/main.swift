// Prove della logica di Sources/Core. Uso: tools/test-core.sh

import Foundation

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0

func expect(_ actual: String?, _ expected: String?, _ name: String, line: Int = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        print("FALLITO (riga \(line)) \(name)\n  atteso:  \(String(describing: expected))\n  ottenuto: \(String(describing: actual))")
    }
}

/// Applica l'Invio con le regole degli elenchi; il cursore è dove sta "|".
func enter(_ marked: String) -> String? {
    let caret = (marked as NSString).range(of: "|").location
    let text = marked.replacingOccurrences(of: "|", with: "")
    guard let edit = ListEditing.newline(in: text, selection: NSRange(location: caret, length: 0)) else { return nil }
    return ListEditing.resolve(edit, in: text, caretAfterEdit: edit.caretAfter).edit.applied(to: text)
}

func tab(_ text: String, at original: Int, deeper: Bool) -> String? {
    guard let edit = ListEditing.shift(in: text, selection: NSRange(location: original, length: 0), deeper: deeper) else { return nil }
    let caret = ListEditing.mapCaret(original, from: text, to: edit.applied(to: text))
    return ListEditing.resolve(edit, in: text, caretAfterEdit: caret).edit.applied(to: text)
}

func type(_ marked: String, _ typed: String, kind: NoteKind = .meeting, options: TypingOptions = TypingOptions()) -> String? {
    let caret = (marked as NSString).range(of: "|").location
    let text = marked.replacingOccurrences(of: "|", with: "")
    guard let edit = TypingRules.edit(in: text, caret: caret, typed: typed, kind: kind, options: options) else { return nil }
    return edit.applied(to: text)
}

// MARK: Elenchi

expect(enter("- uno|"), "- uno\n- ", "trattino continua")
expect(enter("* uno|"), "* uno\n* ", "asterisco continua")
expect(enter("1. uno|"), "1. uno\n2. ", "numero continua")
expect(enter("9) uno|"), "9) uno\n10) ", "numero con parentesi continua")
expect(enter("- [ ] chiama Marta|"), "- [ ] chiama Marta\n- [ ] ", "casella continua vuota")
expect(enter("- [x] fatto|"), "- [x] fatto\n- [ ] ", "casella spuntata continua da fare")
expect(enter("- |"), "", "voce vuota chiude l'elenco")
expect(enter("1. uno\n2. |"), "1. uno\n", "numero vuoto chiude l'elenco")
expect(enter("    - |"), "- ", "voce vuota annidata sale di un livello")
expect(enter("---|"), nil, "il separatore non è un elenco")
expect(enter("**grassetto**|"), nil, "il grassetto non è un elenco")
expect(enter("testo normale|"), nil, "riga normale: Invio normale")
expect(enter("-|"), nil, "senza spazio non è un elenco")
expect(enter("1. uno|\n2. due\n3. tre"), "1. uno\n2. \n3. due\n4. tre", "inserire in mezzo rinumera")
expect(enter("- uno|due"), "- uno\n- due", "Invio in mezzo alla voce la divide")
expect(enter("|- uno"), nil, "cursore davanti al segno: Invio normale")

expect(tab("1. a\n2. b", at: 9, deeper: true), "1. a\n    1. b", "Tab annida e riparte da 1")
expect(tab("1. a\n    1. b\n2. c", at: 18, deeper: true), "1. a\n    1. b\n    2. c", "Tab continua il livello")
expect(tab("1. a\n    1. b", at: 13, deeper: false), "1. a\n2. b", "Maiusc-Tab torna al livello e rinumera")
expect(tab("- [x] fatta", at: 3, deeper: true), "    - [x] fatta", "Tab non cambia una casella spuntata")
expect(tab("testo", at: 2, deeper: true), nil, "Tab fuori dagli elenchi: nil")
expect(tab("- a", at: 1, deeper: false), nil, "Maiusc-Tab al livello zero: nil")

expect(ListEditing.renumbered("1. a\n3. b\n7. c", around: 5), "1. a\n2. b\n3. c", "rinumera")
expect(ListEditing.renumbered("4. a\n9. b", around: 0), "4. a\n5. b", "la prima tiene il suo numero")
expect(ListEditing.renumbered("1. a\n- b\n5. c", around: 0), "1. a\n- b\n5. c", "un trattino interrompe la numerazione")
expect(ListEditing.renumbered("1. a\n\n5. c", around: 0), "1. a\n\n5. c", "una riga vuota chiude il blocco")

expect(String(ListEditing.mapCaret(5, from: "1. a\n2. b", to: "1. a\n10. b")), "6", "il cursore resta nella riga")
expect(String(ListEditing.mapCaret(12, from: "9. a\n9. b", to: "9. a\n10. b")), "10", "oltre la fine: ultima riga")
expect(String(ListEditing.mapCaret(3, from: "- a\n- b", to: "- a\n- b")), "3", "stesso testo")

// MARK: Regole di scrittura

expect(type("ciao |", ","), "ciao,", "niente spazio prima della virgola")
expect(type("SITO |", ":", kind: .todo), "SITO:", "niente spazio prima dei due punti")
expect(type("- |", "."), nil, "dopo il segno di elenco lo spazio resta")
expect(type("✓ |", "."), nil, "dopo il ✓ lo spazio resta")
expect(type("|", ","), nil, "a inizio riga niente")
expect(type("ciao|", ","), nil, "senza spazio prima non c'è niente da togliere")
expect(type("ciao |", ",", options: TypingOptions(spacing: false, capitalize: true)), nil, "regola spenta")

expect(type("ciao |", " "), "ciao. ", "doppio spazio dopo una lettera")
expect(type("alle 17 |", " "), "alle 17. ", "doppio spazio dopo una cifra")
expect(type("ciao, |", " "), nil, "doppio spazio dopo la virgola: niente")
expect(type("- |", " "), nil, "doppio spazio dopo il segno: niente")

expect(type("|", "c"), "C", "maiuscola a inizio nota")
expect(type("uno\n|", "d"), "uno\nD", "maiuscola a inizio riga")
expect(type("- |", "d"), "- D", "maiuscola dopo il trattino")
expect(type("- [ ] |", "c"), "- [ ] C", "maiuscola dopo la casella")
expect(type("# |", "r"), "# R", "maiuscola nel titolo")
expect(type("Fatto. |", "d"), "Fatto. D", "maiuscola dopo il punto")
expect(type("Davvero? |", "s"), "Davvero? S", "maiuscola dopo il punto interrogativo")
expect(type("Ok! |", "s"), "Ok! S", "maiuscola dopo il punto esclamativo")
expect(type("ad es. |", "u"), nil, "dopo un'abbreviazione no")
expect(type("Marta M. |", "r"), nil, "dopo un'iniziale no")
expect(type("alle 17. |", "p"), nil, "dopo un numero no")
expect(type("vedi sito.it |", "u"), nil, "senza punto non chiude")
expect(type("vedi sito.it. |", "u"), nil, "dopo un indirizzo no")
expect(type("Boh... |", "s"), nil, "dopo i puntini no")
expect(type("ciao |", "m"), nil, "dentro la frase no")
expect(type("#alfa|", "b"), nil, "dopo un hashtag no")
expect(type("|", "c", kind: .todo), nil, "nelle to-do niente maiuscola")
expect(type("|", "c", options: TypingOptions(spacing: true, capitalize: false)), nil, "maiuscola spenta")
expect(type("|", "1"), nil, "una cifra non si maiuscola")

// MARK: Controllo della punteggiatura (Apple Intelligence)

expect(PunctuationGuard.split("- [ ] chiama Marta").prefix, "- [ ] ", "prefisso casella")
expect(PunctuationGuard.split("SITO: chiama Marta").prefix, "SITO: ", "prefisso sigla")
expect(PunctuationGuard.split("✓ - rivedi le slide").prefix, "✓ - ", "prefisso fatto + elenco")
expect(PunctuationGuard.split("testo semplice").prefix, "", "nessun prefisso")
expect(PunctuationGuard.accepts(original: "ho sentito marta domani torna", candidate: "Ho sentito Marta, domani torna.").description, "true", "stesse parole")
expect(PunctuationGuard.accepts(original: "uno due", candidate: "Uno, due e tre.").description, "false", "parole aggiunte")
expect(PunctuationGuard.accepts(original: "uno due", candidate: "").description, "false", "riga vuota")
expect(PunctuationGuard.merge(lines: ["- ho sentito marta", "domani torna"], fixed: ["Ho sentito Marta.", "Domani torna."], keepInitialCase: false).joined(separator: "|"),
       "- Ho sentito Marta.|Domani torna.", "merge rimette il prefisso")
expect(PunctuationGuard.merge(lines: ["a b", "c d"], fixed: ["A, b."], keepInitialCase: false).joined(separator: "|"), "a b|c d", "numero di righe diverso: originali")
expect(PunctuationGuard.merge(lines: ["a b", "c d"], fixed: ["A, b.", "c d e."], keepInitialCase: false).joined(separator: "|"), "A, b.|c d", "una riga con parole cambiate resta com'era")
expect(PunctuationGuard.merge(lines: ["chiama marta, manda il preventivo"], fixed: ["Chiama Marta, manda il preventivo."], keepInitialCase: true).joined(separator: "|"),
       "chiama Marta, manda il preventivo.", "nelle to-do la prima lettera resta minuscola")

print(failures == 0 ? "Tutto a posto: \(checks) controlli." : "\(failures) falliti su \(checks).")
exit(failures == 0 ? 0 : 1)
