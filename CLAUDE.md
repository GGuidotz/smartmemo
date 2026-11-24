# SmartMemo

App macOS di to-do e riunioni (Swift/SwiftUI + AppKit, macOS 26+). Stesso schema di GGuidotz/whats-going-on e Nod.
Piano: progetto AppDevelop, `app-note/piano-smartmemo.md`.

- Compilazione: `./build.sh` (swiftc diretto, niente progetto Xcode, `-swift-version 5`). Firma con l'identità locale
  di Nod (~/.nod-signing) se c'è, altrimenti ad hoc. Nel cloud Swift non compila: ogni modifica la prova Giulio sul Mac
  con `./build.sh --install`. Rileggi il codice con cura prima di consegnare.
- Firma con hardened runtime (`--options runtime`) ed entitlement in `Resources/SmartMemo.entitlements`: da aggiornare
  se l'app usa una risorsa nuova (microfono, calendari, ecc.). Oggi solo Automazione (apple-events) per l'Updater.
- Controllo nel cloud: `pip install tree-sitter tree-sitter-swift`, poi `python3 -I tools/check-syntax.py`. Non
  sostituisce la compilazione.
- `Sources/Core` solo Foundation (+ NaturalLanguage dietro `#if canImport`): parser delle to-do, riconoscimento,
  file, Oggi. `Sources/App`: AppKit e SwiftUI.
- Avvio AppKit (`Sources/App/Main.swift`): la scorciatoia ⌃⌥Spazio (Carbon, niente permesso Accessibilità) e il
  pannello rapido devono funzionare a finestra chiusa.
- Formato dei file: Markdown puro. Il solo segno che l'app aggiunge al testo è `✓ ` a inizio riga per le to-do fatte.
  `SIGLA:` apre un blocco progetto, una riga di tre o più trattini lo chiude.
- L'editor (`NoteTextView`) è TextKit 1: serve la posizione delle parole per capsule, cerchi e accensione.
- Due tipi di nota, To-do e Riunione, ognuna in una scheda sua (`CardWindow.swift`); la finestra principale ha solo
  gli elenchi (Oggi, To-do, Riunioni, Progetti). Nelle riunioni le to-do sono le righe `- [ ] `; il riassunto sta tra
  `<!-- riassunto … -->` e `<!-- /riassunto -->` (`MeetingSummary`), scritto da Apple Intelligence (`Intelligence.swift`,
  dietro `#if canImport(FoundationModels)`, collegata debole) o con le regole.
- Guida iniziale (`Onboarding.swift`), impostazioni a schede (`SettingsView.swift`), aggiornamenti, novità e feedback
  come in What's Going On.
- Testi: chiave = frase italiana, `L("…")`; ogni chiave nuova va in `Localization/en.lproj/Localizable.strings`.
  Controllo: `python3 -I tools/check-strings.py`.
- Versione: `VERSION` + sezione `## <versione> · <data>` in cima a `CHANGELOG.md` (build.sh la richiede).
  Rilascio: `./release.sh` sul Mac di Giulio (DMG, release GitHub, cask nel tap).
- Design: Human Interface Guidelines (skill apple-design) e Sguardo, il sistema di design comune (github.com/GGuidotz/sguardo,
  submodule in `Vendor/Sguardo`, regole in DESIGN.md e PLAYBOOK.md), compilato insieme all'app da build.sh
  (`SGUARDO_DIR` per provare il kit locale). Accento predefinito `SG.Accent.smartmemo` (l'indaco dell'icona, in
  `Theme.swift`), applicato a ogni radice con `.sguardoAccent(default:)`: in Generale la persona sceglie colore
  dell'app, di sistema o personalizzato (`SGAccentRow`); il testo di AppKit lo legge da `Theme.accent`. Impostazioni e
  guide con `SGPage`/`SGSection`/`SGGroup`, pulsanti nel contenuto `.buttonStyle(.sgSecondary/.sgPrimary)`. Liquid
  Glass solo su ciò che galleggia (pannello rapido, barra delle schede `SGFloatingTabBar`, pulsanti in fondo alle
  schede con `floatingGlassButton`). Colore mai come unico segnale, colori di sistema per progetti, persone e date.
  Interfaccia in italiano e inglese, niente emoji.
- Mai dati reali di Giulio (note, sigle, nomi, clienti) nel repository, che è pubblico: solo esempi inventati
  (SITO, BANDO, LANCIO, #ALFA, Marta, Nexa, Studio Rossi, Luca). La sua configurazione la carica lui sul Mac con
  "Configura dalle tue note" (`SetupWizard.swift`, `SetupAnalyzer.swift`), o da un file esportato che resta suo.
- Riservato: nessun servizio esterno, nessuna AI fuori dal Mac (le note sono di lavoro, con dati di clienti).
