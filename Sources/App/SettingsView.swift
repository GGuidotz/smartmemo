// Le impostazioni, in sei schede: Generale, Scrittura, Apple Intelligence, Progetti e persone, Aggiornamenti (con le note di
// rilascio) e Feedback. Una finestra AppKit con dentro SwiftUI, perché l'avvio è AppKit. Barra del titolo trasparente:
// la barra delle schede (Sguardo) galleggia in fondo, di vetro, e le righe ci scorrono sotto; il fondo è il materiale
// delle barre laterali. Stesso schema di What's Going On. HIG, Impostazioni: poche scelte, ognuna spiegata sotto.

import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, writing, intelligence, learned, updates, feedback
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("Generale")
        case .writing: L("Scrittura")
        case .intelligence: L("Apple Intelligence")
        case .learned: L("Progetti e persone")
        case .updates: L("Aggiornamenti")
        case .feedback: L("Feedback")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .writing: "character.cursor.ibeam"
        case .intelligence: "sparkles"
        case .learned: "person.crop.rectangle.stack"
        case .updates: "arrow.down.circle"
        case .feedback: "bubble.left.and.text.bubble.right"
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: AppModel, tab: SettingsTab? = nil) {
        if let tab { model.settingsTab = tab }
        if window == nil {
            let w = TranslucentWindow.make(SettingsView(model: model), size: SettingsView.size)
            w.delegate = self
            window = w
        }
        window?.title = L("Impostazioni di SmartMemo")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.window?.contentViewController = nil
                self?.window = nil
            }
        }
    }
}

/// Una finestra con il fondo traslucido del sistema e la barra del titolo trasparente: impostazioni e guida iniziale.
@MainActor
enum TranslucentWindow {
    static func make(_ root: some View, size: CGSize) -> NSWindow {
        let host = NSHostingController(rootView: root)
        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        let container = NSViewController()
        container.view = effect
        container.addChild(host)
        effect.frame = NSRect(origin: .zero, size: size)
        host.view.frame = effect.bounds
        host.view.autoresizingMask = [.width, .height]
        effect.addSubview(host.view)
        let w = NSWindow(contentViewController: container)
        w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.setContentSize(size)
        w.center()
        return w
    }
}

struct SettingsView: View {
    static let size = CGSize(width: 620, height: 640)

    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences

    init(model: AppModel) {
        self.model = model
        prefs = model.prefs
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch model.settingsTab {
                case .general: GeneralSettings(model: model, prefs: prefs)
                case .writing: WritingSettings(prefs: prefs)
                case .intelligence: IntelligenceSettings(prefs: prefs)
                case .learned: LearnedSettings(model: model, prefs: prefs)
                case .updates: UpdatesSettings(updater: model.updater, prefs: prefs)
                case .feedback: FeedbackSettings(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // La barra delle schede galleggia in fondo: le righe ci scorrono sotto (SGPage lascia lo spazio).
            SettingsTabBar(selection: $model.settingsTab)
                .padding(.bottom, SG.Size.tabBarBottomInset)
        }
        // In alto, sotto i semafori della finestra, il contenuto sfuma invece di tagliarsi di netto.
        .overlay(alignment: .top) { SGProgressiveBlur() }
        .frame(width: Self.size.width, height: Self.size.height)
        // La barra del titolo è trasparente e la vista occupa tutta la finestra: senza questo la zona sicura in alto
        // spinge giù tutto e la barra delle schede finisce sul bordo inferiore.
        .ignoresSafeArea()
        .sguardoAccent(default: .smartmemo)
        .id(prefs.language)
    }
}

/// La barra delle schede (Sguardo): una capsula che galleggia sopra il fondo della finestra, di vetro su macOS 26. La
/// scheda scelta mostra il nome, le altre solo il simbolo (il nome resta nel suggerimento e per VoiceOver). ⌘1…⌘6.
private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        SGFloatingTabBar(SettingsTab.allCases.map { SGTab($0, title: $0.title, systemImage: $0.symbol) },
                         selection: $selection, commandShortcuts: true)
    }
}

/// Una sezione con un'azione accanto al titolo (il +): Sguardo ha il titolo e basta, qui si aggiunge il pulsante.
private struct ActionSection<Content: View, Footer: View>: View {
    let title: String
    let action: AnyView
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                SGSectionTitle(title).accessibilityAddTraits(.isHeader)
                action.padding(.trailing, 2)
            }
            SGGroup { content }
            footer
                .padding(.horizontal, SG.Space.sectionTitleInset)
                .padding(.top, 6)
        }
    }
}

// MARK: - Generale

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        SGPage {
            SGSection(L("Apertura")) {
                SGToggleRow(L("Apertura rapida con %@", HotKey.display), isOn: $prefs.hotKeyEnabled)
                SGDivider()
                SGToggleRow(L("Icona nella barra dei menu"), isOn: $prefs.menuBarIcon)
                SGDivider()
                SGToggleRow(L("Apri all'accesso"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let loginError {
                    SGRowBlock { Text(loginError).font(SG.Font.caption).foregroundStyle(.red) }
                }
            } footer: {
                SGFootnote(L("Con l'apertura all'accesso la scorciatoia risponde sempre, anche se non hai ancora aperto l'app."))
            }

            SGSection(L("Schede")) {
                SGToggleRow(L("Schede in primo piano"), isOn: $prefs.cardsOnTop)
                SGDivider()
                SGLabeledRow {
                    Text(L("Le to-do vanno a domani dalle"))
                } trailing: {
                    HStack(spacing: 8) {
                        Text("\(prefs.eveningHour):00")
                            .font(SG.Font.body)
                            .foregroundStyle(SG.Ink.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                        Stepper(L("Le to-do vanno a domani dalle"), value: $prefs.eveningHour, in: 12...23)
                            .labelsHidden()
                    }
                }
            } footer: {
                SGFootnote(L("In primo piano le schede restano sopra le altre finestre; la puntina in alto a destra di ogni scheda lo cambia solo per quella. Di sera si scrive per domani: dall'ora scelta, To-do apre la pagina del giorno dopo."))
            }

            SGSection(L("Note")) {
                SGLabeledRow {
                    Text(L("Cartella delle note"))
                } trailing: {
                    Text(model.store.root.path(percentEncoded: false))
                        .font(SG.Font.caption)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(SG.Ink.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 330, alignment: .trailing)
                }
                SGDivider()
                SGRowBlock {
                    Button(L("Mostra nel Finder")) {
                        try? FileManager.default.createDirectory(at: model.store.root, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([model.store.root])
                    }
                    .buttonStyle(.sgSecondary)
                }
            } footer: {
                SGFootnote(model.store.isInICloud
                         ? L("File Markdown in iCloud Drive: li apri anche con altre app, e restano tuoi.")
                         : L("File Markdown in Documenti: iCloud Drive non è attivo su questo Mac."))
            }

            SGSection {
                SGMenuRow(L("Lingua"), selection: $prefs.language,
                          options: AppLanguage.allCases.map { (value: $0, title: $0.title) })
                SGDivider()
                SGAccentRow(L("Colore d'accento"),
                            options: (app: L("Colore dell'app"), system: L("Colore di sistema"), custom: L("Personalizzato")),
                            appDefault: .smartmemo)
                SGDivider()
                SGRowBlock {
                    Button(L("Rivedi la guida iniziale")) { model.showOnboarding() }
                        .buttonStyle(.sgSecondary)
                }
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = L("Non riesco a cambiare l'apertura all'accesso: %@", error.localizedDescription)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Scrittura

private struct WritingSettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        SGPage {
            SGSection(L("Regole di scrittura")) {
                SGToggleRow(L("Punteggiatura mentre scrivi"), isOn: $prefs.autoPunctuation)
                SGDivider()
                SGToggleRow(L("Maiuscola a inizio frase (riunioni)"), isOn: $prefs.autoCapitalize)
            } footer: {
                SGFootnote(L("Niente spazio prima di virgola, punto e due punti; due spazi diventano un punto. Indietro, subito dopo, annulla la correzione. Nelle to-do la maiuscola non c'è: si comincia con un verbo."))
            }

            SGSection(L("Elenchi")) {
                SGToggleRow(L("Elenchi automatici (riunioni)"), isOn: $prefs.autoLists)
            } footer: {
                SGFootnote(L("Scrivi \"- \" o \"1. \" a inizio riga: Invio continua l'elenco, Invio su una voce vuota lo chiude, Tab annida e i numeri si aggiornano da soli. Il file resta Markdown."))
            }

            SGSection(L("Correzione di macOS")) {
                SGToggleRow(L("Correzione automatica di macOS"), isOn: $prefs.systemAutocorrect)
                SGDivider()
                SGToggleRow(L("Sostituzioni di testo di macOS"), isOn: $prefs.textReplacements)
            } footer: {
                SGFootnote(L("Le sigle dei progetti e i nomi che SmartMemo conosce non vengono corretti. Le sostituzioni sono quelle di Impostazioni di Sistema › Tastiera."))
            }

            SGSection(L("Punteggiatura con Apple Intelligence")) {
                SGRowBlock { Tip(symbol: "text.badge.checkmark", text: L("Sistema la punteggiatura (⌥⌘P, o clic destro) aggiunge virgole, punti e maiuscole a un testo dettato, sulla selezione o su tutta la nota.")) }
                SGDivider()
                SGRowBlock { Tip(symbol: "lock", text: L("Lo fa Apple Intelligence sul Mac, senza rete: cambia solo la punteggiatura, mai le parole. ⌘Z annulla.")) }
            }
        }
    }
}

// MARK: - Apple Intelligence

/// Lo stato di Apple Intelligence su questo Mac, scritto e con un simbolo (mai solo il colore).
struct IntelligenceStatus: View {
    var body: some View {
        if let reason = Intelligence.unavailableReason {
            Label(reason, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label(L("Apple Intelligence è pronta su questo Mac."), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

private struct IntelligenceSettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        SGPage {
            SGSection {
                SGRowBlock { IntelligenceStatus() }
                SGDivider()
                SGToggleRow(L("Riassunti delle riunioni con Apple Intelligence"), isOn: $prefs.useAppleIntelligence)
                if Intelligence.unavailableReason != nil {
                    SGDivider()
                    SGRowBlock {
                        Button(L("Apri Impostazioni di Sistema")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.sgSecondary)
                    }
                }
            } footer: {
                SGFootnote(L("Il modello sta sul Mac: le note non escono mai, nemmeno verso Apple. Niente rete, niente account."))
            }

            SGSection(L("Cosa fa")) {
                SGRowBlock { Tip(symbol: "checklist", text: L("Concludi riunione scrive in cima la sintesi, il prossimo incontro, le scadenze e le to-do minimal con chi le fa.")) }
                SGDivider()
                SGRowBlock { Tip(symbol: "arrow.clockwise", text: L("Puoi rifarlo dopo aver aggiunto appunti, toglierlo, o annullarlo con ⌘Z. Le to-do del riassunto finiscono in Oggi.")) }
                SGDivider()
                SGRowBlock { Tip(symbol: "highlighter", text: L("Progetti, persone e date si riconoscono mentre scrivi con il linguaggio naturale del Mac, anche senza Apple Intelligence.")) }
                SGDivider()
                SGRowBlock { Tip(symbol: "list.number", text: L("Senza Apple Intelligence il riassunto si fa con le regole: le righe numerate o a elenco diventano to-do, il nome tra parentesi è chi le fa.")) }
            }
        }
    }
}

struct Tip: View {
    var symbol: String
    var text: String

    var body: some View {
        Label {
            Text(text).font(SG.Font.body).foregroundStyle(SG.Ink.primary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(SG.Ink.secondary).frame(width: 22)
        }
    }
}

// MARK: - Progetti e persone

private struct LearnedSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var exportMessage: String?
    @State private var addingProject = false
    @State private var addingPerson = false

    var body: some View {
        SGPage {
            SGSection {
                SGRowBlock {
                    HStack(spacing: 8) {
                        Button(L("Configura dalle tue note…")) { model.showSetup() }
                        Button(L("Esporta configurazione…")) {
                            exportMessage = ConfigurationFile.export(model.knowledge, prefs: model.prefs)
                        }
                        Spacer(minLength: 0)
                    }
                    .buttonStyle(.sgSecondary)
                }
                if let exportMessage {
                    SGRowBlock { SGFootnote(exportMessage) }
                }
            } footer: {
                SGFootnote(L("Parti da qualche pagina delle tue note e decidi cosa è progetto, cosa è persona e cosa evidenziare. Tutto resta su questo Mac; l'esportazione è un file tuo, per un altro Mac o per ripartire da lì."))
            }

            SGSection(L("Evidenzia mentre scrivi")) {
                SGToggleRow(L("Progetti"), isOn: $prefs.highlightProjects)
                SGDivider()
                SGToggleRow(L("Persone e clienti"), isOn: $prefs.highlightPeople)
                SGDivider()
                SGToggleRow(L("Date e orari"), isOn: $prefs.highlightDates)
                SGDivider()
                SGToggleRow(L("URGENTE"), isOn: $prefs.highlightUrgent)
            }

            ActionSection(title: L("Progetti"),
                          action: AnyView(SectionPlusButton(help: L("Aggiungi un progetto")) { addingProject = true })) {
                if addingProject {
                    SGRowBlock {
                        NewNameField(prompt: L("Sigla, es. SITO o SITO Nuovo sito")) { model.addProject($0) } close: {
                            addingProject = false
                        }
                    }
                } else if model.knowledge.projects.isEmpty {
                    SGRowBlock {
                        Text(L("Nessun progetto ancora. Premi + o scrivi nelle note una sigla seguita dai due punti, come SITO:"))
                            .foregroundStyle(SG.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(Array(model.knowledge.projects.enumerated()), id: \.element) { index, sigla in
                    if index > 0 || addingProject { SGDivider() }
                    ProjectRow(model: model, sigla: sigla)
                }
            } footer: {
                SGFootnote(L("Il nome lungo è facoltativo: compare accanto alla sigla nella vista Oggi."))
            }

            ActionSection(title: L("Persone e clienti"),
                          action: AnyView(SectionPlusButton(help: L("Aggiungi una persona o un cliente")) { addingPerson = true })) {
                if addingPerson {
                    SGRowBlock {
                        NewNameField(prompt: L("Nome, es. Marta o Studio Rossi")) { model.addPerson($0) } close: {
                            addingPerson = false
                        }
                    }
                } else if model.knowledge.people.isEmpty {
                    SGRowBlock {
                        Text(L("Nessuna persona ancora. Premi + per aggiungerne una."))
                            .foregroundStyle(SG.Ink.secondary)
                    }
                }
                ForEach(Array(model.knowledge.people.enumerated()), id: \.element) { index, name in
                    if index > 0 || addingPerson { SGDivider() }
                    SGLabeledRow {
                        Text(name)
                    } trailing: {
                        Button(L("Dimentica")) { model.forgetPerson(name) }
                            .buttonStyle(.sgSecondary)
                            .accessibilityLabel(L("Dimentica %@", name))
                    }
                }
            } footer: {
                SGFootnote(L("SmartMemo impara da ciò che scrivi. Se sbaglia, clic destro sulla parola nella nota."))
            }
        }
    }
}

private struct ProjectRow: View {
    @ObservedObject var model: AppModel
    let sigla: String
    @State private var name = ""

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.project(sigla, knowledge: model.knowledge)).frame(width: 9, height: 9)
                .accessibilityHidden(true)
            Text(sigla).font(SG.Font.bodyEmphasis).foregroundStyle(SG.Ink.primary)
                .frame(minWidth: 60, alignment: .leading)
            TextField(L("Nome lungo"), text: $name)
                .capsuleField()
                .onSubmit { model.setProjectName(sigla, name) }
                .accessibilityLabel(L("Nome lungo di %@", sigla))
            Button(L("Dimentica")) { model.forgetProject(sigla) }
                .buttonStyle(.sgSecondary)
                .accessibilityLabel(L("Dimentica %@", sigla))
        }
        .padding(.horizontal, SG.Space.rowInset)
        .padding(.vertical, 6)
        .frame(minHeight: SG.Size.row)
        .onAppear { name = model.knowledge.projectNames[sigla] ?? "" }
    }
}

// MARK: - Aggiornamenti e note di rilascio

private struct UpdatesSettings: View {
    @ObservedObject var updater: Updater
    @ObservedObject var prefs: Preferences
    private let releases = Changelog.load()

    var body: some View {
        SGPage {
            SGSection {
                SGToggleRow(L("Controlla automaticamente (ogni 6 ore)"), isOn: $prefs.autoCheckUpdates)
                SGDivider()
                SGValueRow(L("Versione installata"), value: updater.currentVersion)
                SGDivider()
                SGValueRow(L("Ultimo controllo")) {
                    if let last = updater.lastCheck { Text(last, style: .relative) } else { Text(L("Mai")) }
                }
                SGDivider()
                SGRowBlock {
                    HStack(spacing: 10) {
                        Button(L("Controlla ora")) { Task { await updater.check() } }
                            .buttonStyle(.sgSecondary)
                            .disabled(updater.state == .checking)
                        UpdateStateText(updater: updater)
                        Spacer(minLength: 0)
                    }
                }
            } footer: {
                SGFootnote(L("Il controllo legge solo il numero di versione e le note di rilascio da GitHub. Nient'altro esce dal Mac."))
            }

            if updater.isUpdateAvailable {
                SGSection { SGRowBlock { UpdateCard(updater: updater) } }
            }

            if !releases.isEmpty {
                SGSection(L("Note di rilascio")) {
                    SGRowBlock { ChangelogList(entries: releases) }
                }
            }
        }
    }
}

private struct UpdateStateText: View {
    @ObservedObject var updater: Updater

    var body: some View {
        switch updater.state {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .upToDate:
            Label(L("SmartMemo è aggiornato."), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let version):
            Label(L("Disponibile la versione %@", version), systemImage: "arrow.down.circle.fill").foregroundStyle(.tint)
        case .failed(let why):
            Text(why).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Le novità della nuova versione e il comando per aggiornare.
private struct UpdateCard: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .available(let version) = updater.state {
                Label(L("Disponibile SmartMemo %@", version), systemImage: "arrow.down.circle.fill")
                    .font(SG.Font.bodyEmphasis)
            }
            if !updater.news.isEmpty { ChangelogList(entries: updater.news) }
            Text(L("Per aggiornare, esegui nel Terminale:")).foregroundStyle(SG.Ink.secondary)
            Text(updater.command)
                .font(SG.Font.value)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: SG.Radius.tile, style: .continuous).fill(SG.Fill.tile))
                .overlay(RoundedRectangle.sgTile.strokeBorder(SG.Fill.rowBorder, lineWidth: SG.Stroke.hairline))
            HStack(spacing: 8) {
                Button(L("Copia comando")) { updater.copyCommand() }
                    .buttonStyle(.sgSecondary)
                Button(L("Aggiorna nel Terminale")) { updater.runInTerminal() }
                    .buttonStyle(.sgPrimary)
            }
            if let error = updater.terminalError {
                Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Feedback

private struct FeedbackSettings: View {
    @ObservedObject var model: AppModel
    @State private var status: String?
    @State private var showReport = false

    var body: some View {
        SGPage {
            SGSection {
                SGRowBlock {
                    HStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 72, height: 72)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Smart(Me)mo").font(SG.Font.title)
                            Text(L("Versione %@", "\(SystemInfo.version) (\(SystemInfo.build))"))
                                .foregroundStyle(SG.Ink.secondary)
                            Text(L("To-do e riunioni che capiscono progetti, persone e date."))
                                .foregroundStyle(SG.Ink.secondary)
                        }
                    }
                }
            }

            SGSection(L("Feedback")) {
                FeedbackButton(symbol: "ladybug", title: L("Segnala un problema"),
                               detail: L("Su GitHub, con versione, macOS e modello del Mac già scritti.")) {
                    Feedback.openIssue(.problem)
                }
                SGDivider()
                FeedbackButton(symbol: "lightbulb", title: L("Suggerisci un'idea"),
                               detail: L("Un modo di scrivere che non riconosce, una vista che manca, qualcosa da semplificare.")) {
                    Feedback.openIssue(.idea)
                }
                SGDivider()
                FeedbackButton(symbol: "envelope", title: L("Scrivi un'email"), detail: Developer.email) {
                    Feedback.composeEmail()
                }
            } footer: {
                SGFootnote(L("GitHub è il canale preferito: le segnalazioni sono pubbliche, quindi non incollare il testo delle note. Per qualcosa di privato usa l'email."))
            }

            SGSection(L("Diagnostica")) {
                SGRowBlock {
                    HStack(spacing: 8) {
                        Button(L("Copia report")) {
                            Feedback.copyReport(model: model)
                            status = L("Report copiato: incollalo nella segnalazione.")
                        }
                        Button(L("Salva…")) { status = Feedback.saveReport(model: model) }
                        Spacer()
                        Button(showReport ? L("Nascondi") : L("Mostra")) { showReport.toggle() }
                    }
                    .buttonStyle(.sgSecondary)
                }
                if let status {
                    SGRowBlock { SGFootnote(status) }
                }
                if showReport {
                    SGDivider()
                    SGRowBlock {
                        ScrollView {
                            Text(DiagnosticsReport.make(model: model))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                    }
                }
            } footer: {
                SGFootnote(L("Il report dice versione, Mac, le tue scelte e quante note hai. Mai il testo delle note, né nomi di persone o progetti."))
            }

            SGSection {
                SGRowBlock { DeveloperLinks() }
            }
        }
    }
}

private struct FeedbackButton: View {
    var symbol: String
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(SG.Ink.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(SG.Font.body).foregroundStyle(SG.Ink.primary)
                    Text(detail).font(SG.Font.caption).foregroundStyle(SG.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(SG.Ink.tertiary)
            }
            .padding(.horizontal, SG.Space.rowInset)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: SG.Size.row, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}
