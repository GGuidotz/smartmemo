# Smart(Me)mo

To-do e riunioni per macOS che capiscono progetti, persone e date mentre scrivi.

Scrivi le to-do come le scrivi già, veloci e a sigle:

```
SITO: chiama Marta, manda il preventivo a Nexa
-------------
BANDO: carica i documenti in cartella, finalizza allegato B
rispondi a Studio Rossi sul preventivo
-------------
LANCIO: URGENTE! rivedi le slide con i commenti
```

SmartMemo riconosce i progetti (`SITO:`, `#ALFA`), le persone e i clienti, le date e URGENTE: ogni parola riconosciuta
si accende una volta e resta segnata. Invio divide una riga alle virgole dove comincia un'altra azione. La vista Oggi
raccoglie le to-do aperte per progetto, con URGENTE in cima e quelle dei giorni passati riportate finché non le spunti.

## Apertura rapida e schede

⌃⌥Spazio da qualsiasi app: To-do (T) o Riunione (R). Invio sceglie To-do, Esc chiude. Si apre una scheda piccola,
senza barre laterali, da tenere accanto al lavoro; la puntina la tiene in primo piano.

## Riunioni

Scrivi gli appunti come vengono. Concludi riunione (⌘Invio) chiede ad Apple Intelligence, sul Mac, un riassunto in
cima: sintesi, prossimo incontro, scadenze e to-do minimal con chi le fa. Le to-do finiscono in Oggi. Senza Apple
Intelligence il riassunto si fa con le regole (righe numerate, nome tra parentesi).

## Dove stanno le note

File Markdown in `iCloud Drive/SmartMemo` (o `Documenti/SmartMemo` senza iCloud Drive): `To-do/2026-10-15.md`,
`Riunioni/2026-10-02 17.00.md`. Si aprono con qualsiasi editor. Una to-do fatta comincia con `✓ `.

Il riconoscimento e i riassunti girano tutti sul Mac (regole, NaturalLanguage e Apple Intelligence). Nessun servizio
esterno: l'unica connessione è il controllo degli aggiornamenti, che legge il numero di versione da GitHub.

## Requisiti e installazione

macOS 26 o successivo.

```
brew install --cask gguidotz/tap/smartmemo
```

Dal codice, con Xcode o i Command Line Tools: `./build.sh --install`.

## Tappe

- 0.1 To-do e riunioni in schede: apertura rapida, accensione, spunte, Oggi, riporto, progetti, Concludi riunione
  con Apple Intelligence, guida iniziale, aggiornamenti, feedback.
- 0.2 Prossimo incontro in Calendario, persone collegate a Contatti.
- 0.3 Integrazioni: importa ed esporta con Apple Notes, invia a Promemoria.

## Feedback

[GitHub Issues](https://github.com/GGuidotz/smartmemo/issues) è il canale preferito.
