# Privacy

SmartMemo lavora sul tuo Mac e non ha server suoi. Nessun account, nessuna telemetria.

## Dove stanno le note

Le note sono file Markdown in iCloud Drive (cartella `SmartMemo`) o, senza iCloud Drive, in `Documenti/SmartMemo`. Si
leggono con qualsiasi editor, anche senza l'app: chi può aprire quella cartella può leggerle.

## Dove va il testo

Solo sul Mac. Il riconoscimento di progetti, persone e date usa regole e NaturalLanguage; i riassunti e la punteggiatura
usano Apple Intelligence, che gira sul Mac. Nessun servizio esterno e nessuna AI fuori dal Mac. L'unica connessione è il
controllo degli aggiornamenti, che legge il numero di versione da GitHub senza mandare altro.

## Cosa si salva fuori dalle note

La configurazione (sigle dei progetti, nomi e clienti riconosciuti) sta in `~/Library/Application Support/SmartMemo`,
in una cartella leggibile solo dal tuo utente. Le impostazioni stanno nelle preferenze di macOS. Il file di
configurazione che esporti lo salvi dove scegli tu e resta tuo.

## Se le note contengono dati di clienti

- Tieni acceso FileVault (Impostazioni di Sistema › Privacy e sicurezza): cifra il disco del Mac.
- Se usi iCloud Drive, attiva la Protezione avanzata dei dati (Impostazioni di Sistema › ID Apple › iCloud): le note
  sono cifrate end-to-end anche su iCloud.

## Diagnostica

Il report di Impostazioni › Feedback contiene stati e conteggi, mai il testo delle note. Si condivide solo se lo copi
e lo mandi tu.
