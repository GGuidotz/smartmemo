// Verbi d'azione delle to-do, per dividere una riga alle virgole solo dove comincia un'altra cosa da fare.
// Prima l'elenco (sicuro e istantaneo), poi il riconoscimento delle parti del discorso di Apple per i verbi che
// mancano. Imperativo e infinito, più qualche verbo inglese che capita nelle note di lavoro.

import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

enum ItalianVerbs {
    static let all: Set<String> = {
        let imperative = """
        aggiorna aggiungi allega analizza annulla apri approva archivia aspetta avvisa blocca carica cerca chiama chiedi \
        chiudi completa compra condividi conferma consegna contatta controlla convoca correggi crea definisci elimina \
        fai finalizza firma fissa giustifica imposta incontra informa inoltra inserisci integra invia leggi manda metti \
        modifica nota ordina organizza paga parla passa pianifica porta prendi prenota prepara presenta proponi prova \
        pubblica raccogli recupera registra rileggi rinnova riordina ripassa riprendi riassumi richiedi richiama \
        ricorda rispondi ritira rivedi salva scarica scrivi segna segnala senti sistema sollecita sposta stampa studia \
        sviluppa telefona termina trasferisci trova valuta verifica
        """
        let infinitive = """
        aggiornare aggiungere allegare analizzare aprire approvare caricare cercare chiamare chiedere chiudere \
        completare condividere confermare contattare controllare correggere creare definire fare finalizzare firmare \
        fissare inviare leggere mandare organizzare pagare parlare preparare presentare prenotare rielaborare rivedere \
        rispondere scrivere sentire sistemare sollecitare spostare trasferire verificare
        """
        let english = "ask book call check email fix follow plan prepare review send share submit update upload write"
        return Set((imperative + " " + infinitive + " " + english).split(separator: " ").map(String.init))
    }()

    /// Il riconoscimento di Apple dice che `word`, dentro `context`, è un verbo. Solo parole minuscole di almeno 4
    /// lettere che finiscono come un imperativo o un infinito: "sollecito" o "allegati" non dividono.
    static func looksLikeVerb(_ word: String, in context: String) -> Bool {
        guard word.count >= 4, let last = word.last, "aeir".contains(last) else { return false }
        #if canImport(NaturalLanguage)
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = context
        tagger.setLanguage(.italian, range: context.startIndex..<context.endIndex)
        let (tag, _) = tagger.tag(at: context.startIndex, unit: .word, scheme: .lexicalClass)
        return tag == .verb
        #else
        return false
        #endif
    }
}
