# Novità

Formato: `## <versione> · <data>`, poi `### Novità`, `### Miglioramenti`, `### Correzioni`, una riga `- ` per
cambiamento. release.sh usa la sezione della versione come note della release.

## 0.2.0 · 2026-11-13

Scrivere è più veloce: elenchi che si continuano da soli nelle riunioni, punteggiatura che si sistema mentre scrivi o con Apple Intelligence, e schede con i bordi in ordine.

### Novità
- Elenchi automatici nelle riunioni: scrivi `- ` o `1. ` a inizio riga e Invio continua l'elenco; Invio su una voce vuota lo chiude; Tab e Maiusc-Tab annidano e i numeri si aggiornano da soli. Una casella `- [ ] ` continua con una casella nuova. Il file resta Markdown puro.
- Regole di scrittura: niente spazio prima di virgola, punto e due punti; due spazi diventano un punto; nelle riunioni la maiuscola a inizio frase (non dopo abbreviazioni come "es." o "ecc."). Indietro, subito dopo, annulla la correzione.
- Sistema la punteggiatura (⌥⌘P, o clic destro): Apple Intelligence aggiunge virgole, punti e maiuscole a un testo dettato, sulla selezione o su tutta la nota. Cambia solo la punteggiatura, mai le parole; una riga con parole diverse resta com'era. Si annulla con ⌘Z. Tutto sul Mac.
- Nuova scheda Scrittura nelle Impostazioni: regole, elenchi e correzione di macOS si accendono e si spengono una per una.
- Correzione automatica e sostituzioni di testo di macOS nelle schede; le sigle dei progetti e i nomi che SmartMemo conosce non vengono corretti.

### Miglioramenti
- Titoli (`# ` e `## `) più grandi nelle riunioni; elenchi con pallini, numeri in grigio e righe a capo allineate al testo.
- Il testo resta in colonna sulle finestre larghe.
- La barra in fondo alle schede sta sotto il testo, non sopra, con margini più larghi; mostra anche i messaggi delle nuove funzioni.
- Margini più larghi a destra e a sinistra: il cerchio delle to-do e il riquadro del riassunto stanno lontani dagli angoli arrotondati della finestra.

### Correzioni
- Il testo di esempio e il riquadro del riassunto si adattano alla larghezza vera della scheda.
- Il pannello rapido ha un margine trasparente attorno al vetro: bordo e ombra non vengono più tagliati, e i titoli lunghi si riducono invece di troncarsi.

## 0.1.0 · 2026-10-15

La prima versione: to-do e riunioni che si capiscono mentre le scrivi, in schede piccole da tenere accanto al lavoro.

### Novità
- Apertura rapida da qualsiasi app con ⌃⌥Spazio: To-do (T) o Riunione (R), Invio sceglie To-do. Le stesse voci sono nell'icona della barra dei menu, nel Dock e nel menu Archivio (⌘T, ⌘N).
- Ogni pagina di to-do e ogni riunione si apre in una scheda sua: piccola, senza barre laterali, che torna dove l'avevi lasciata. La puntina in alto la tiene sopra le altre finestre.
- Pagine di to-do per giorno, scritte come sempre: `SITO:` apre il blocco di un progetto, tre trattini lo chiudono, ogni riga è una to-do. Dalle 17 (regolabile) To-do apre la pagina di domani.
- L'accensione: progetti, persone e clienti, date e URGENTE si riconoscono mentre scrivi, una luce li attraversa una volta e restano segnati, ognuno con una forma sua (capsula, puntini, sottolineatura, capsula rossa). Con Riduci movimento è una breve dissolvenza.
- Invio divide una riga alle virgole quando dopo la virgola comincia un'altra azione: "chiama Marta, manda il preventivo a Nexa" diventa due to-do. ⌘Z la ricompone.
- Spunta con il cerchio a sinistra della riga o con ⌘K. Nel file la to-do fatta comincia con "✓ ": resta Markdown leggibile ovunque.
- Concludi riunione (⌘Invio): Apple Intelligence scrive in cima sintesi, prossimo incontro, scadenze e to-do minimal con chi le fa. Tutto sul Mac, niente rete. Si rifà, si toglie o si annulla con ⌘Z; senza Apple Intelligence un riassunto più semplice dalle righe numerate.
- Oggi: le to-do aperte di tutte le pagine e riunioni, per progetto, URGENTE in cima, quelle dei giorni passati con "da N giorni" finché non le spunti; la stessa to-do riscritta in più giorni si vede una volta sola.
- Finestra principale essenziale: Oggi, To-do, Riunioni e i progetti con il loro colore.
- Guida al primo avvio in cinque passi, con esempi disegnati come nelle schede e le scelte principali.
- Impostazioni: Generale, Apple Intelligence, Progetti e persone, Aggiornamenti con le note di rilascio, Feedback con segnalazioni su GitHub, email e report di diagnostica (senza il testo delle note).
- Aggiornamenti: controllo automatico ogni 6 ore e aggiornamento con un clic nel Terminale (Homebrew o dai sorgenti).
- Configura dalle tue note: incolli o apri qualche pagina delle tue note, decidi cosa è progetto, cosa è persona o cliente e cosa evidenziare, con l'anteprima sul tuo testo. Il testo non si salva; la configurazione resta sul Mac e si può esportare e importare come file tuo.
- SmartMemo impara sigle e persone da ciò che scrivi; clic destro su una parola per correggerlo ("non è una persona", "è un progetto").
- Un + per aggiungere a mano progetti e persone: nella barra laterale accanto a Progetti, in Impostazioni › Progetti e persone e nella configurazione guidata. "SITO Nuovo sito" aggiunge la sigla con il suo nome lungo.
- Le note sono file Markdown in iCloud Drive/SmartMemo (o in Documenti/SmartMemo). Nessun servizio esterno.
