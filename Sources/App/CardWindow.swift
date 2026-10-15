// Le schede: ogni pagina di to-do e ogni riunione si apre in una finestrella sua, piccola e senza barre laterali, da
// tenere accanto a ciò che stai facendo. Solo il testo, il titolo in alto e, in fondo, ciò che serve a quella nota:
// quante to-do restano (pagine di to-do) o "Concludi riunione" con il riassunto (riunioni).
// La puntina nella barra del titolo la tiene sopra le altre finestre; il predefinito è in Impostazioni › Generale.
// Ogni scheda torna dove avevi lasciato l'ultima dello stesso tipo. Una nota già aperta non si apre due volte.

import AppKit
import SwiftUI

/// Lo stato di una scheda, condiviso tra la finestra (AppKit) e il contenuto (SwiftUI).
@MainActor
final class CardState: ObservableObject {
    let document: OpenDocument
    weak var textView: NoteTextView?
    weak var window: NSWindow?

    @Published private(set) var onTop: Bool
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var hasSummary = false
    @Published private(set) var openCount = 0
    @Published private(set) var doneCount = 0

    /// Chiamato quando cambia la puntina, per aggiornare il pulsante nella barra del titolo.
    var onTopChanged: () -> Void = {}

    init(document: OpenDocument, onTop: Bool) {
        self.document = document
        self.onTop = onTop
    }

    func setOnTop(_ value: Bool) {
        onTop = value
        window?.level = value ? .floating : .normal
        onTopChanged()
    }

    /// Dopo ogni pausa di scrittura: conteggi, riassunto presente, titolo della finestra.
    func textChanged(_ text: String) {
        switch document.kind {
        case .todo:
            let tasks = TodoParser.parse(text, knowledge: textView?.model?.knowledge ?? Knowledge()).filter { $0.kind == .task && !$0.body.isEmpty }
            let done = tasks.filter(\.done).count
            if doneCount != done { doneCount = done }
            if openCount != tasks.count - done { openCount = tasks.count - done }
        case .meeting:
            let has = MeetingSummary.blockRange(in: text) != nil
            if hasSummary != has { hasSummary = has }
            let first = text.split(separator: "\n").lazy
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && $0 != "#" }
            let title = first.map { String($0.prefix(60)) } ?? L("Riunione")
            if window?.title != title { window?.title = title }
        }
    }

    // MARK: Riassunto

    /// "Concludi riunione": il riassunto esecutivo in cima, con le to-do minimal. Con Apple Intelligence se si può,
    /// altrimenti con le regole. Si annulla con ⌘Z come ogni modifica.
    func conclude(model: AppModel) {
        guard let tv = textView, !busy else { return }
        busy = true
        message = nil
        let text = tv.string
        let useAI = model.prefs.useAppleIntelligence
        Task { @MainActor in
            let (summary, note) = await Intelligence.summarize(text, knowledge: model.knowledge, useAI: useAI)
            self.busy = false
            guard let tv = self.textView else { return }
            tv.replaceAll(with: MeetingSummary.insert(summary, into: tv.string), actionName: L("Concludi riunione"))
            tv.glowSummary()
            if let note {
                self.message = note
            } else if !summary.byAI, useAI {
                self.message = Intelligence.unavailableReason
            }
            self.textChanged(tv.string)
        }
    }

    func removeSummary() {
        guard let tv = textView else { return }
        tv.replaceAll(with: MeetingSummary.remove(from: tv.string), actionName: L("Togli il riassunto"))
        message = nil
        textChanged(tv.string)
    }
}

@MainActor
final class CardWindows: NSObject, NSWindowDelegate {
    private struct Card {
        let window: NSWindow
        let state: CardState
        let pin: PinAccessory
    }

    private let model: AppModel
    private var cards: [URL: Card] = [:]

    init(model: AppModel) { self.model = model }

    func show(_ doc: OpenDocument) {
        NSApp.activate()
        if let card = cards[doc.url] {
            card.window.makeKeyAndOrderFront(nil)
            return
        }
        let state = CardState(document: doc, onTop: model.prefs.cardsOnTop)
        let host = NSHostingController(rootView: CardView(model: model, prefs: model.prefs, card: state))
        host.sizingOptions = []
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.backgroundColor = .textBackgroundColor
        w.title = doc.title
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed
        w.collectionBehavior.insert(.fullScreenAuxiliary)
        w.minSize = NSSize(width: 320, height: 260)
        w.delegate = self
        let pin = PinAccessory(card: state)
        w.addTitlebarAccessoryViewController(pin)
        state.window = w
        state.onTopChanged = { [weak pin] in pin?.update() }
        state.setOnTop(state.onTop)
        place(w, kind: doc.kind)
        cards[doc.url] = Card(window: w, state: state, pin: pin)
        w.makeKeyAndOrderFront(nil)
    }

    /// La puntina predefinita è cambiata nelle impostazioni: vale per tutte le schede aperte.
    func applyPreferences() {
        for card in cards.values where card.state.onTop != model.prefs.cardsOnTop {
            card.state.setOnTop(model.prefs.cardsOnTop)
        }
    }

    private static func frameName(_ kind: NoteKind) -> String { "SmartMemoCard.\(kind.rawValue)" }

    /// Dove l'ultima scheda dello stesso tipo è stata chiusa; spostata un po' se lì c'è già una scheda aperta.
    private func place(_ w: NSWindow, kind: NoteKind) {
        if !w.setFrameUsingName(Self.frameName(kind)) {
            w.setContentSize(NSSize(width: 440, height: 560))
            w.center()
        }
        var frame = w.frame
        while cards.values.contains(where: { abs($0.window.frame.minX - frame.minX) < 4 && abs($0.window.frame.maxY - frame.maxY) < 4 }) {
            frame = frame.offsetBy(dx: 26, dy: -26)
        }
        w.setFrame(frame, display: false)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let w = notification.object as? NSWindow else { return }
            closed(w)
        }
    }

    private func closed(_ w: NSWindow) {
        guard let entry = cards.first(where: { $0.value.window === w }) else { return }
        model.flushEditor(entry.key)
        w.saveFrame(usingName: Self.frameName(entry.value.state.document.kind))
        cards[entry.key] = nil
        // Via le viste dopo la chiusura: l'editor si toglie dall'elenco delle schede aperte.
        DispatchQueue.main.async { w.contentViewController = nil }
    }
}

/// La puntina nella barra del titolo: tiene la scheda sopra le altre finestre.
@MainActor
final class PinAccessory: NSTitlebarAccessoryViewController {
    private let card: CardState
    private let button = NSButton()

    init(card: CardState) {
        self.card = card
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .trailing
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    override func loadView() {
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(toggle(_:))
        button.frame = NSRect(x: 6, y: 3, width: 24, height: 22)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 38, height: 28))
        container.addSubview(button)
        view = container
        update()
    }

    @objc private func toggle(_ sender: Any?) {
        card.setOnTop(!card.onTop)
    }

    func update() {
        let on = card.onTop
        button.image = NSImage(systemSymbolName: on ? "pin.fill" : "pin", accessibilityDescription: L("Tieni in primo piano"))
        button.contentTintColor = on ? .controlAccentColor : .secondaryLabelColor
        button.toolTip = on ? L("In primo piano: clic per lasciarla tra le altre finestre") : L("Tieni in primo piano")
        button.setAccessibilityValue(on ? L("Sì") : L("No"))
    }
}

// MARK: Contenuto

struct CardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var card: CardState

    var body: some View {
        EditorView(model: model, card: card)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Group {
                    switch card.document.kind {
                    case .todo: todoBar
                    case .meeting: meetingBar
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .frame(minWidth: 320, minHeight: 240)
    }

    /// Pagina di to-do: quante ne restano e la vista Oggi.
    private var todoBar: some View {
        HStack(spacing: 10) {
            Text(counts)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button {
                model.sidebar = .today
                model.showMainWindow()
            } label: {
                Label(L("Oggi"), systemImage: "sun.max")
            }
            .buttonStyle(.glass)
            .help(L("Tutte le to-do da fare, di ogni pagina e riunione"))
        }
    }

    private var counts: String {
        if card.openCount == 0 && card.doneCount == 0 { return L("Nessuna to-do") }
        if card.doneCount == 0 { return card.openCount == 1 ? L("1 da fare") : L("%d da fare", card.openCount) }
        return L("%d da fare, %d fatte", card.openCount, card.doneCount)
    }

    /// Riunione: "Concludi riunione" scrive il riassunto; dopo, si può rifare o togliere.
    private var meetingBar: some View {
        let ai = prefs.useAppleIntelligence && Intelligence.isAvailable
        return HStack(spacing: 10) {
            if card.busy {
                ProgressView().controlSize(.small)
                Text(ai ? L("Apple Intelligence sta riassumendo…") : L("Sto riassumendo…"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let message = card.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if card.hasSummary && !card.busy {
                        Button { card.removeSummary() } label: {
                            Label(L("Togli il riassunto"), systemImage: "xmark")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.glass)
                        .help(L("Togli il riassunto (⌘Z lo rimette)"))
                    }
                    Button { card.conclude(model: model) } label: {
                        Label(card.hasSummary ? L("Rifai il riassunto") : L("Concludi riunione"),
                              systemImage: ai ? "sparkles" : "checklist")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(card.busy)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(ai ? L("Riassunto e to-do in cima, scritti da Apple Intelligence sul Mac (⌘Invio)")
                             : L("Riassunto e to-do in cima, dalle righe numerate (⌘Invio)"))
                }
            }
        }
    }
}
