// La configurazione guidata: parti dalle tue note e decidi insieme a SmartMemo cosa è cosa e cosa evidenziare.
//   1. Le tue note: le incolli, le apri da un file, oppure importi una configurazione salvata prima.
//   2. Cosa è cosa: per ogni sigla o nome trovato, Progetto, Persona o cliente, Niente. Puoi aggiungerne altri.
//   3. Cosa evidenziare: progetti, persone, date, URGENTE, con l'anteprima sul tuo testo.
//   4. Fatto: salva, e se vuoi esporta la configurazione in un file (per un altro Mac o per ripartire da lì).
// Il testo incollato non si salva: si legge per proporre, e resta solo in questa finestra. Ciò che decidi va in
// Application Support/SmartMemo sul Mac, come tutto ciò che l'app impara. Niente rete.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let view = SetupView(model: model, prefs: model.prefs) { [weak self] in self?.window?.performClose(nil) }
            let w = TranslucentWindow.make(view, size: SetupView.size)
            w.delegate = self
            window = w
        }
        window?.title = L("Configura dalle tue note")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Chiusa: via la finestra e il testo incollato con lei.
    nonisolated func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.window?.contentViewController = nil
                self?.window = nil
            }
        }
    }
}

struct SetupView: View {
    static let size = CGSize(width: 640, height: 660)

    var model: AppModel
    @ObservedObject var prefs: Preferences
    var close: () -> Void

    @State private var step = 0
    @State private var text = ""
    @State private var candidates: [SetupCandidate] = []
    @State private var newName = ""
    @State private var newRole: SetupCandidate.Role = .person
    @State private var message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: notesStep
                case 1: rolesStep
                case 2: highlightStep
                default: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .id(step)

            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .id(prefs.language)
    }

    // MARK: - 1. Le tue note

    private var notesStep: some View {
        Page(symbol: "doc.text.magnifyingglass", title: L("Parti dalle tue note"),
             text: L("Incolla qui qualche pagina di to-do o di riunione scritta come la scrivi di solito. SmartMemo cerca sigle e nomi e ti propone cosa sono.")) {
            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
                .frame(height: 250)
                .accessibilityLabel(L("Le tue note"))
            HStack {
                Button(L("Apri un file…")) { openNotes() }
                Button(L("Importa una configurazione…")) { importConfiguration() }
                Spacer()
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Label(L("Il testo resta in questa finestra: non si salva e non esce dal Mac. Si salva solo ciò che decidi nei passi dopo."),
                  systemImage: "lock")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 2. Cosa è cosa

    private var rolesStep: some View {
        Page(symbol: "person.crop.rectangle.stack", title: L("Cosa è cosa"),
             text: L("Ecco cosa ho trovato. Scegli per ognuno: progetto, persona o cliente, oppure niente se non va evidenziato.")) {
            ScrollView {
                VStack(spacing: 0) {
                    if candidates.isEmpty {
                        Text(L("Non ho trovato sigle o nomi: aggiungili qui sotto."))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    ForEach($candidates) { $c in
                        CandidateRow(candidate: $c)
                        Divider()
                    }
                }
            }
            .frame(height: 300)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: .rect(cornerRadius: 10))
            HStack(spacing: 8) {
                TextField(L("Aggiungi una sigla o un nome"), text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCandidate)
                Picker(L("Tipo"), selection: $newRole) {
                    Text(L("Progetto")).tag(SetupCandidate.Role.project)
                    Text(L("Persona")).tag(SetupCandidate.Role.person)
                }
                .labelsHidden()
                .frame(width: 120)
                Button(L("Aggiungi"), action: addCandidate)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - 3. Cosa evidenziare

    private var highlightStep: some View {
        Page(symbol: "highlighter", title: L("Cosa evidenziare"),
             text: L("Scegli cosa si accende mentre scrivi. Ciò che spegni si riconosce lo stesso: Oggi e i progetti continuano a funzionare.")) {
            Toggle(isOn: $prefs.highlightProjects) { Label(L("Progetti: capsula colorata"), systemImage: "capsule") }
            Toggle(isOn: $prefs.highlightPeople) { Label(L("Persone e clienti: indaco con puntini"), systemImage: "person") }
            Toggle(isOn: $prefs.highlightDates) { Label(L("Date e orari: sottolineatura arancione"), systemImage: "calendar") }
            Toggle(isOn: $prefs.highlightUrgent) { Label(L("URGENTE: capsula rossa"), systemImage: "exclamationmark.circle") }
            if !text.isEmpty {
                Text(L("Anteprima sulle tue note"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ScrollView {
                    Text(preview)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                }
                .frame(height: 170)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 10))
            }
        }
        .toggleStyle(.switch)
    }

    /// Le prime righe del testo, segnate con le scelte fatte.
    private var preview: AttributedString {
        let head = text.components(separatedBy: .newlines).prefix(14).joined(separator: "\n")
        let knowledge = SetupAnalyzer.apply(candidates, to: model.knowledge)
        var out = AttributedString(head)
        for e in EntityRecognizer.entities(in: head, kind: .todo, knowledge: knowledge) where prefs.highlights(e.kind) {
            guard let r = Range(e.range, in: out) else { continue }
            // Attributi di SwiftUI per nome, così non si confondono con quelli di AppKit.
            var a = AttributeContainer()
            switch e.kind {
            case .project:
                a.swiftUI.backgroundColor = Color.project(e.name, knowledge: knowledge).opacity(0.2)
                a.inlinePresentationIntent = .stronglyEmphasized
            case .person:
                let indigo = Color(nsColor: Theme.person)
                a.swiftUI.foregroundColor = indigo
                a.swiftUI.underlineStyle = Text.LineStyle(pattern: .dot, color: indigo)
            case .date:
                a.swiftUI.underlineStyle = Text.LineStyle(pattern: .solid, color: Color(nsColor: Theme.date))
            case .urgent:
                a.swiftUI.foregroundColor = Color.white
                a.swiftUI.backgroundColor = Color.red
            }
            out[r].mergeAttributes(a)
        }
        return out
    }

    // MARK: - 4. Fatto

    private var doneStep: some View {
        let projects = candidates.filter { $0.role == .project }.count
        let people = candidates.filter { $0.role == .person }.count
        return Page(symbol: "checkmark.circle", title: L("Pronto da salvare"),
                    text: L("%d progetti e %d persone o clienti. Salva e SmartMemo li riconosce da subito, in ogni scheda.", projects, people)) {
            Label(L("Si salva solo su questo Mac, in Application Support. Le tue note restano dove sono."), systemImage: "lock")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(L("Puoi esportare la configurazione in un file: ti serve per un altro Mac o per ripartire da qui. Il file è tuo, tienilo dove vuoi."),
                  systemImage: "square.and.arrow.up")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L("Esporta configurazione…")) { exportConfiguration() }
                .padding(.top, 4)
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Label(L("Cambi idea più tardi? Impostazioni › Progetti e persone, o clic destro su una parola nella nota."),
                  systemImage: "cursorarrow.click.2")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - In fondo

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.primary.opacity(0.75) : Color.primary.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Passo %d di %d", step + 1, steps))

            Spacer()

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if step > 0 {
                        Button(L("Indietro")) { go(step - 1) }
                            .buttonStyle(.glass)
                            .keyboardShortcut(.cancelAction)
                    }
                    Button(step == steps - 1 ? L("Salva") : L("Avanti")) { next() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(step == 0 && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && candidates.isEmpty)
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func next() {
        switch step {
        case 0:
            // Proposte nuove dal testo; le scelte già fatte su un nome restano.
            let previous = Dictionary(candidates.map { ($0.name, $0.role) }, uniquingKeysWith: { a, _ in a })
            candidates = SetupAnalyzer.candidates(in: text, knowledge: model.knowledge).map { c in
                var c = c
                if let role = previous[c.name] { c.role = role }
                return c
            } + candidates.filter { c in !text.contains(c.name) }
            message = nil
            go(1)
        case steps - 1:
            model.applySetup(SetupAnalyzer.apply(candidates, to: model.knowledge), replace: true)
            diag(.app, "setup saved: \(candidates.count) entries")
            text = ""
            close()
        default:
            go(step + 1)
        }
    }

    private func go(_ next: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = min(max(0, next), steps - 1) }
    }

    private func addCandidate() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        candidates.removeAll { $0.name == name }
        candidates.insert(SetupCandidate(name: name, role: newRole, count: 0, example: ""), at: 0)
        newName = ""
    }

    // MARK: - File (solo sul Mac)

    private func openNotes() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        let texts = panel.urls.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
        guard !texts.isEmpty else { message = L("Non riesco a leggere il file: serve testo semplice o Markdown."); return }
        text = (text.isEmpty ? "" : text + "\n\n") + texts.joined(separator: "\n\n")
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try JSONDecoder().decode(SetupFile.self, from: Data(contentsOf: url))
            guard file.format == "smartmemo-config" else { throw CocoaError(.fileReadCorruptFile) }
            let k = file.knowledge
            candidates = k.projects.map { SetupCandidate(name: $0, role: .project, count: 0, example: "") }
                + k.people.map { SetupCandidate(name: $0, role: .person, count: 0, example: "") }
            if let h = file.highlight { prefs.setHighlights(h) }
            model.applySetup(k, replace: false)
            message = L("Configurazione importata: %d progetti e %d persone. Controlla nei passi dopo.", k.projects.count, k.people.count)
            go(1)
        } catch {
            message = L("Questo file non è una configurazione di SmartMemo.")
        }
    }

    private func exportConfiguration() {
        message = ConfigurationFile.export(SetupAnalyzer.apply(candidates, to: model.knowledge), prefs: prefs)
    }
}

/// Il file di configurazione, salvato dove sceglie chi usa l'app. Mai nel repository né dentro l'app.
@MainActor
enum ConfigurationFile {
    /// Restituisce un messaggio da mostrare, o nil se si è annullato.
    static func export(_ knowledge: Knowledge, prefs: Preferences) -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = L("Configurazione SmartMemo") + ".json"
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let file = SetupFile(knowledge: knowledge, highlight: prefs.highlightMap)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(file).write(to: url, options: .atomic)
            return L("Salvato: %@", url.lastPathComponent)
        } catch {
            return error.localizedDescription
        }
    }
}

/// Una riga di "Cosa è cosa": il nome, dove compare, e la scelta.
private struct CandidateRow: View {
    @Binding var candidate: SetupCandidate

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name).font(.body.weight(.semibold))
                if !candidate.example.isEmpty {
                    Text(candidate.example)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            Picker(L("Cos'è %@", candidate.name), selection: $candidate.role) {
                Text(L("Progetto")).tag(SetupCandidate.Role.project)
                Text(L("Persona")).tag(SetupCandidate.Role.person)
                Text(L("Niente")).tag(SetupCandidate.Role.ignore)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

/// Una pagina della procedura: simbolo, titolo, una frase, poi il contenuto.
private struct Page<Content: View>: View {
    var symbol: String
    var title: String
    var text: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.semibold))
                .fontDesign(.rounded)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
