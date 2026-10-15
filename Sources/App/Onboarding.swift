// La guida dei primi passi: cinque schermate brevi al primo avvio (e da Impostazioni › Generale o dal menu Aiuto).
// Cosa fa l'app, come si scrivono le to-do, come si apre in un attimo, le riunioni con Apple Intelligence, dove stanno
// le note. Ogni scelta qui è la stessa delle impostazioni, quindi si può saltare tutto: chiudere la finestra va bene
// quanto arrivare in fondo. Gli esempi sono disegnati come nelle schede, così si riconoscono al primo uso.
// HIG (onboarding): breve, si impara usando, i permessi si chiedono quando servono e spiegando perché.

import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let view = OnboardingView(model: model, prefs: model.prefs) { [weak self] in
                self?.window?.performClose(nil)
                model.quickOpen(.todo)
            }
            let w = TranslucentWindow.make(view, size: OnboardingView.size)
            w.delegate = self
            window = w
        }
        window?.title = L("Benvenuto in SmartMemo")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Chiusa in qualunque modo, la guida è vista: non torna da sola.
    nonisolated func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                let prefs = AppModel.shared.prefs
                prefs.onboardingDone = true
                prefs.lastSeenVersion = SystemInfo.version
                self?.window?.contentViewController = nil
                self?.window = nil
            }
        }
    }
}

struct OnboardingView: View {
    static let size = CGSize(width: 560, height: 640)

    var model: AppModel
    @ObservedObject var prefs: Preferences
    var finish: () -> Void

    @State private var step = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps = 5

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: todos
                case 2: quickOpen
                case 3: meetings
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36)
            .padding(.top, 40)
            .transition(.opacity)
            .id(step)

            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .id(prefs.language)
    }

    // MARK: - Passi

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(L("Benvenuto in Smart(Me)mo"))
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.rounded)
                .multilineTextAlignment(.center)
            Text(L("To-do e riunioni che capiscono progetti, persone e date mentre scrivi. Tutto resta sul Mac."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            SampleCard(title: L("Oggi")) {
                SampleTask(project: "SITO") { Text("\(L("chiama")) \(SampleStyle.person("Marta"))") }
                SampleTask { Text("\(L("manda il preventivo a")) \(SampleStyle.person("Nexa"))") }
                SampleTask(project: "LANCIO", urgent: true) { Text(L("rivedi le slide con i commenti")) }
                SampleTask(done: true) { Text(L("prenota sala")) }
            }
            .padding(.top, 6)
            Text(L("Ti mostro come si usa in quattro passi. Puoi chiudere quando vuoi."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var todos: some View {
        StepPage(symbol: "checklist", title: L("Le to-do, come le scrivi già"),
                 text: L("Una pagina al giorno. Scrivi per progetto: SmartMemo capisce da solo dove comincia e dove finisce.")) {
            SampleCard(title: L("To-do")) {
                SampleTask(project: "SITO") { Text("\(L("chiama")) \(SampleStyle.person("Marta")), \(L("manda il preventivo"))") }
                SampleSeparator()
                SampleTask(project: "BANDO") { Text("\(L("rispondi a")) \(SampleStyle.person("Studio Rossi")) \(SampleStyle.date(L("entro venerdì")))") }
            }
            Tip(symbol: "textformat.abc", text: L("SIGLA: a inizio riga apre un progetto, tre trattini lo chiudono. Le sigle si colorano da sole."))
            Tip(symbol: "return", text: L("Invio alla fine di una riga la divide alle virgole: ogni azione diventa una to-do."))
            Tip(symbol: "circle", text: L("Clic sul cerchio o ⌘K per spuntarla. URGENTE la porta in cima."))
            Tip(symbol: "arrow.uturn.forward", text: L("Quelle non fatte restano in Oggi, con da quanti giorni aspettano."))
        }
    }

    private var quickOpen: some View {
        StepPage(symbol: "bolt", title: L("Si apre in un attimo"),
                 text: L("Da qualsiasi app, %@ e scegli: T per le to-do, R per una riunione. Si apre una scheda piccola, da tenere accanto a ciò che fai.", HotKey.display)) {
            HStack(spacing: 12) {
                SampleChoice(symbol: NoteKind.todo.symbol, title: L("To-do"), key: "T")
                SampleChoice(symbol: NoteKind.meeting.symbol, title: L("Riunione"), key: "R")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            Toggle(L("Apertura rapida con %@", HotKey.display), isOn: $prefs.hotKeyEnabled)
            Toggle(L("Icona nella barra dei menu"), isOn: $prefs.menuBarIcon)
            Toggle(L("Apri all'accesso"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) {
                    do {
                        if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Toggle(L("Schede in primo piano"), isOn: $prefs.cardsOnTop)
            Footnote(L("Con l'apertura all'accesso la scorciatoia risponde sempre. La puntina in alto in ogni scheda la tiene sopra le altre finestre."))
        }
        .toggleStyle(.switch)
    }

    private var meetings: some View {
        StepPage(symbol: "sparkles", title: L("Riunioni con Apple Intelligence"),
                 text: L("Prendi appunti come vengono. Alla fine, Concludi riunione scrive in cima il riassunto e le to-do, con chi le fa.")) {
            SampleCard(title: L("Riunione #ALFA")) {
                SampleSummary()
                Text("\(L("prossimo meeting il")) \(SampleStyle.date(L("12 marzo alle 10:00")))")
                    .font(.callout)
            }
            IntelligenceStatus()
                .font(.callout)
            Toggle(L("Riassunti con Apple Intelligence"), isOn: $prefs.useAppleIntelligence)
                .toggleStyle(.switch)
            Footnote(L("Il modello sta sul Mac: le note non escono mai. Senza Apple Intelligence il riassunto si fa con le regole (righe numerate e nomi tra parentesi)."))
        }
    }

    private var ready: some View {
        StepPage(symbol: "checkmark.circle", title: L("Tutto pronto"),
                 text: L("Ecco dove trovi le cose.")) {
            Tip(symbol: "sun.max", text: L("La finestra di SmartMemo mostra Oggi: tutte le to-do da fare, di ogni pagina e riunione, divise per progetto."))
            Tip(symbol: "folder", text: model.store.isInICloud
                ? L("Le note sono file Markdown in iCloud Drive › SmartMemo: le apri anche con altre app.")
                : L("Le note sono file Markdown in Documenti › SmartMemo: le apri anche con altre app."))
            Tip(symbol: "cursorarrow.click.2", text: L("Clic destro su una parola sbagliata: non è una persona, è un progetto. SmartMemo impara."))
            Button {
                model.showSetup()
            } label: {
                Label(L("Configura dalle tue note…"), systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(.top, 4)
            Footnote(L("Incolli qualche pagina delle tue note e decidi tu cosa è progetto, cosa è persona e cosa evidenziare. Resta tutto sul Mac."))
            Tip(symbol: "gearshape", text: L("Impostazioni (⌘,): Apple Intelligence, aggiornamenti, note di rilascio e feedback."))
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
                    Button(step == steps - 1 ? L("Apri le to-do di oggi") : L("Avanti")) {
                        if step == steps - 1 { finish() } else { go(step + 1) }
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func go(_ next: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = min(max(0, next), steps - 1) }
    }
}

/// Una pagina della guida: simbolo, titolo, una frase, poi il contenuto.
private struct StepPage<Content: View>: View {
    var symbol: String
    var title: String
    var text: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.semibold))
                .fontDesign(.rounded)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Footnote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Esempi disegnati come nelle schede

private enum SampleStyle {
    static func person(_ s: String) -> Text {
        Text(s).foregroundStyle(Color(nsColor: Theme.person)).underline(pattern: .dot, color: Color(nsColor: Theme.person))
    }

    static func date(_ s: String) -> Text {
        Text(s).underline(color: Color(nsColor: Theme.date).opacity(0.7))
    }
}

/// Una scheda finta: il foglio bianco con il titolo e qualche riga.
private struct SampleCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            content
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Esempio"))
    }
}

private struct SampleTask<Content: View>: View {
    var project: String? = nil
    var urgent = false
    var done = false
    @ViewBuilder var label: Content

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.accentColor : (urgent ? Color.red : Color.secondary))
            if let project {
                Text(project)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 6)
                    .background(Color(nsColor: Theme.projectColor(project, knowledge: Knowledge())).opacity(0.16), in: .capsule)
                    .overlay(Capsule().strokeBorder(Color(nsColor: Theme.projectColor(project, knowledge: Knowledge())).opacity(0.55)))
            }
            if urgent {
                Text("URGENTE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.red, in: .capsule)
            }
            label
                .strikethrough(done)
                .foregroundStyle(done ? Color.secondary : Color.primary)
        }
    }
}

private struct SampleSeparator: View {
    var body: some View {
        Text("-----").foregroundStyle(.tertiary)
    }
}

/// Il riquadro del riassunto, come lo disegna l'editor.
private struct SampleSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(L("Riassunto · Apple Intelligence"), systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(Text(L("Sintesi.")).bold()) \(L("Proposta da chiudere entro fine mese."))")
            HStack(spacing: 6) {
                Image(systemName: "circle").foregroundStyle(.secondary)
                Text("\(L("Riscrivere l'introduzione")) · \(SampleStyle.person("Luca"))")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.06), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(LinearGradient(colors: [.blue, .purple, .pink, .orange], startPoint: .leading, endPoint: .trailing),
                              lineWidth: 1.5)
        )
    }
}

/// Un pulsante del pannello rapido, finto.
private struct SampleChoice: View {
    var symbol: String
    var title: String
    var key: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium))
            Text(title).font(.headline)
            Text(key)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: .rect(cornerRadius: 4))
        }
        .frame(width: 104, height: 96)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}
