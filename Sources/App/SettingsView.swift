// Le impostazioni, in cinque schede: Generale, Apple Intelligence, Progetti e persone, Aggiornamenti (con le note di
// rilascio) e Feedback. Una finestra AppKit con dentro SwiftUI, perché l'avvio è AppKit. Barra del titolo trasparente:
// la barra delle schede è di vetro e galleggia sopra il contenuto, il fondo è il materiale delle barre laterali.
// Stesso schema di What's Going On. HIG, Impostazioni: poche scelte, ognuna spiegata sotto.

import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, intelligence, learned, updates, feedback
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("Generale")
        case .intelligence: L("Apple Intelligence")
        case .learned: L("Progetti e persone")
        case .updates: L("Aggiornamenti")
        case .feedback: L("Feedback")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
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
        Group {
            switch model.settingsTab {
            case .general: GeneralSettings(model: model, prefs: prefs)
            case .intelligence: IntelligenceSettings(prefs: prefs)
            case .learned: LearnedSettings(model: model, prefs: prefs)
            case .updates: UpdatesSettings(updater: model.updater, prefs: prefs)
            case .feedback: FeedbackSettings(model: model)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsTabBar(selection: $model.settingsTab)
                .padding(.top, 2)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .id(prefs.language)
    }
}

/// La barra delle schede: un controllo che galleggia, quindi di vetro. ⌘1…⌘5 per passare da una scheda all'altra.
private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element) { index, tab in
                    let selected = selection == tab
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 15, weight: .medium))
                                .frame(height: 18)
                            Text(tab.title)
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(width: 104, height: 44)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(5)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
    }
}

/// Il testo sotto una sezione.
private struct Footnote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Generale

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle(L("Apertura rapida con %@", HotKey.display), isOn: $prefs.hotKeyEnabled)
                Toggle(L("Icona nella barra dei menu"), isOn: $prefs.menuBarIcon)
                Toggle(L("Apri all'accesso"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            } header: {
                Text(L("Apertura"))
            } footer: {
                Footnote(L("Con l'apertura all'accesso la scorciatoia risponde sempre, anche se non hai ancora aperto l'app."))
            }

            Section {
                Toggle(L("Schede in primo piano"), isOn: $prefs.cardsOnTop)
                Stepper(value: $prefs.eveningHour, in: 12...23) {
                    LabeledContent(L("Le to-do vanno a domani dalle"), value: "\(prefs.eveningHour):00")
                        .monospacedDigit()
                }
            } header: {
                Text(L("Schede"))
            } footer: {
                Footnote(L("In primo piano le schede restano sopra le altre finestre; la puntina in alto a destra di ogni scheda lo cambia solo per quella. Di sera si scrive per domani: dall'ora scelta, To-do apre la pagina del giorno dopo."))
            }

            Section {
                LabeledContent(L("Cartella delle note")) {
                    Text(model.store.root.path(percentEncoded: false))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                Button(L("Mostra nel Finder")) {
                    try? FileManager.default.createDirectory(at: model.store.root, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([model.store.root])
                }
            } header: {
                Text(L("Note"))
            } footer: {
                Footnote(model.store.isInICloud
                         ? L("File Markdown in iCloud Drive: li apri anche con altre app, e restano tuoi.")
                         : L("File Markdown in Documenti: iCloud Drive non è attivo su questo Mac."))
            }

            Section {
                Picker(L("Lingua"), selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                Button(L("Rivedi la guida iniziale")) { model.showOnboarding() }
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
        Form {
            Section {
                IntelligenceStatus()
                Toggle(L("Riassunti delle riunioni con Apple Intelligence"), isOn: $prefs.useAppleIntelligence)
                if Intelligence.unavailableReason != nil {
                    Button(L("Apri Impostazioni di Sistema")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } footer: {
                Footnote(L("Il modello sta sul Mac: le note non escono mai, nemmeno verso Apple. Niente rete, niente account."))
            }

            Section {
                Tip(symbol: "checklist", text: L("Concludi riunione scrive in cima la sintesi, il prossimo incontro, le scadenze e le to-do minimal con chi le fa."))
                Tip(symbol: "arrow.clockwise", text: L("Puoi rifarlo dopo aver aggiunto appunti, toglierlo, o annullarlo con ⌘Z. Le to-do del riassunto finiscono in Oggi."))
                Tip(symbol: "highlighter", text: L("Progetti, persone e date si riconoscono mentre scrivi con il linguaggio naturale del Mac, anche senza Apple Intelligence."))
                Tip(symbol: "list.number", text: L("Senza Apple Intelligence il riassunto si fa con le regole: le righe numerate o a elenco diventano to-do, il nome tra parentesi è chi le fa."))
            } header: {
                Text(L("Cosa fa"))
            }
        }
    }
}

struct Tip: View {
    var symbol: String
    var text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
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
        Form {
            Section {
                HStack {
                    Button(L("Configura dalle tue note…")) { model.showSetup() }
                    Button(L("Esporta configurazione…")) {
                        exportMessage = ConfigurationFile.export(model.knowledge, prefs: model.prefs)
                    }
                }
                if let exportMessage { Footnote(exportMessage) }
            } footer: {
                Footnote(L("Parti da qualche pagina delle tue note e decidi cosa è progetto, cosa è persona e cosa evidenziare. Tutto resta su questo Mac; l'esportazione è un file tuo, per un altro Mac o per ripartire da lì."))
            }
            Section {
                Toggle(L("Progetti"), isOn: $prefs.highlightProjects)
                Toggle(L("Persone e clienti"), isOn: $prefs.highlightPeople)
                Toggle(L("Date e orari"), isOn: $prefs.highlightDates)
                Toggle(L("URGENTE"), isOn: $prefs.highlightUrgent)
            } header: {
                Text(L("Evidenzia mentre scrivi"))
            }
            Section {
                if addingProject {
                    NewNameField(prompt: L("Sigla, es. SITO o SITO Nuovo sito")) { model.addProject($0) } close: {
                        addingProject = false
                    }
                } else if model.knowledge.projects.isEmpty {
                    Text(L("Nessun progetto ancora. Premi + o scrivi nelle note una sigla seguita dai due punti, come SITO:")).foregroundStyle(.secondary)
                }
                ForEach(model.knowledge.projects, id: \.self) { sigla in
                    ProjectRow(model: model, sigla: sigla)
                }
            } header: {
                HStack {
                    Text(L("Progetti"))
                    Spacer()
                    PlusButton(help: L("Aggiungi un progetto")) { addingProject = true }
                }
            } footer: {
                Footnote(L("Il nome lungo è facoltativo: compare accanto alla sigla nella vista Oggi."))
            }
            Section {
                if addingPerson {
                    NewNameField(prompt: L("Nome, es. Marta o Studio Rossi")) { model.addPerson($0) } close: {
                        addingPerson = false
                    }
                } else if model.knowledge.people.isEmpty {
                    Text(L("Nessuna persona ancora. Premi + per aggiungerne una.")).foregroundStyle(.secondary)
                }
                ForEach(model.knowledge.people, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button(L("Dimentica")) { model.forgetPerson(name) }
                            .accessibilityLabel(L("Dimentica %@", name))
                    }
                }
            } header: {
                HStack {
                    Text(L("Persone e clienti"))
                    Spacer()
                    PlusButton(help: L("Aggiungi una persona o un cliente")) { addingPerson = true }
                }
            } footer: {
                Footnote(L("SmartMemo impara da ciò che scrivi. Se sbaglia, clic destro sulla parola nella nota."))
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
            Text(sigla).font(.body.weight(.semibold)).frame(minWidth: 60, alignment: .leading)
            TextField(L("Nome lungo"), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.setProjectName(sigla, name) }
                .accessibilityLabel(L("Nome lungo di %@", sigla))
            Button(L("Dimentica")) { model.forgetProject(sigla) }
                .accessibilityLabel(L("Dimentica %@", sigla))
        }
        .onAppear { name = model.knowledge.projectNames[sigla] ?? "" }
    }
}

// MARK: - Aggiornamenti e note di rilascio

private struct UpdatesSettings: View {
    @ObservedObject var updater: Updater
    @ObservedObject var prefs: Preferences
    private let releases = Changelog.load()

    var body: some View {
        Form {
            Section {
                Toggle(L("Controlla automaticamente (ogni 6 ore)"), isOn: $prefs.autoCheckUpdates)
                LabeledContent(L("Versione installata"), value: updater.currentVersion)
                LabeledContent(L("Ultimo controllo")) {
                    if let last = updater.lastCheck { Text(last, style: .relative) } else { Text(L("Mai")) }
                }
                HStack {
                    Button(L("Controlla ora")) { Task { await updater.check() } }
                        .disabled(updater.state == .checking)
                    UpdateStateText(updater: updater)
                }
            } footer: {
                Footnote(L("Il controllo legge solo il numero di versione e le note di rilascio da GitHub. Nient'altro esce dal Mac."))
            }

            if updater.isUpdateAvailable {
                Section { UpdateCard(updater: updater) }
            }

            if !releases.isEmpty {
                Section {
                    ChangelogList(entries: releases)
                } header: {
                    Text(L("Note di rilascio"))
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
            Label(L("Disponibile la versione %@", version), systemImage: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
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
                    .font(.headline)
            }
            if !updater.news.isEmpty { ChangelogList(entries: updater.news) }
            Text(L("Per aggiornare, esegui nel Terminale:")).foregroundStyle(.secondary)
            Text(updater.command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
            HStack {
                Button(L("Copia comando")) { updater.copyCommand() }
                Button(L("Aggiorna nel Terminale")) { updater.runInTerminal() }
                    .buttonStyle(.glassProminent)
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
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Smart(Me)mo").font(.title2.weight(.semibold)).fontDesign(.rounded)
                        Text(L("Versione %@", "\(SystemInfo.version) (\(SystemInfo.build))")).foregroundStyle(.secondary)
                        Text(L("To-do e riunioni che capiscono progetti, persone e date.")).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                FeedbackButton(symbol: "ladybug", title: L("Segnala un problema"),
                               detail: L("Su GitHub, con versione, macOS e modello del Mac già scritti.")) {
                    Feedback.openIssue(.problem)
                }
                FeedbackButton(symbol: "lightbulb", title: L("Suggerisci un'idea"),
                               detail: L("Un modo di scrivere che non riconosce, una vista che manca, qualcosa da semplificare.")) {
                    Feedback.openIssue(.idea)
                }
                FeedbackButton(symbol: "envelope", title: L("Scrivi un'email"), detail: Developer.email) {
                    Feedback.composeEmail()
                }
            } header: {
                Text(L("Feedback"))
            } footer: {
                Footnote(L("GitHub è il canale preferito: le segnalazioni sono pubbliche, quindi non incollare il testo delle note. Per qualcosa di privato usa l'email."))
            }

            Section {
                HStack {
                    Button(L("Copia report")) {
                        Feedback.copyReport(model: model)
                        status = L("Report copiato: incollalo nella segnalazione.")
                    }
                    Button(L("Salva…")) { status = Feedback.saveReport(model: model) }
                    Spacer()
                    Button(showReport ? L("Nascondi") : L("Mostra")) { showReport.toggle() }
                }
                if let status { Footnote(status) }
                if showReport {
                    ScrollView {
                        Text(DiagnosticsReport.make(model: model))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                }
            } header: {
                Text(L("Diagnostica"))
            } footer: {
                Footnote(L("Il report dice versione, Mac, le tue scelte e quante note hai. Mai il testo delle note, né nomi di persone o progetti."))
            }

            Section {
                DeveloperLinks()
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
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}
