// Lo stato dell'app: la cartella delle note, ciò che l'app ha imparato, le to-do di tutte le pagine e la nota aperta.
// Si rilegge dai file dopo ogni salvataggio e quando l'app torna in primo piano (le note possono cambiare da fuori,
// anche da iCloud).

import AppKit
import Combine
import SwiftUI

enum SidebarItem: Hashable {
    case today, todos, meetings, project(String)
}

struct ProjectCount: Identifiable, Hashable {
    let sigla: String
    let open: Int
    var id: String { sigla }
}

/// Una nota da aprire in una scheda.
struct OpenDocument: Equatable, Identifiable {
    let url: URL
    let kind: NoteKind
    let title: String
    /// Il testo con cui comincia se il file non esiste ancora (il modello di una riunione).
    var template: String = ""
    var caret: Int? = nil
    var id: URL { url }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let prefs: Preferences
    let updater: Updater
    let store = NoteStore()
    private let knowledgeStore = KnowledgeStore()

    @Published private(set) var knowledge: Knowledge
    @Published private(set) var knowledgeVersion = 0
    @Published private(set) var board = TaskBoard()
    @Published private(set) var todoPages: [NoteRef] = []
    @Published private(set) var meetings: [NoteRef] = []

    @Published var sidebar: SidebarItem? = .today
    @Published var settingsTab: SettingsTab = .general

    /// Cambia quando un file aperto in una scheda è stato cambiato da fuori (una spunta data dalla vista Oggi).
    @Published private(set) var reloadToken = 0
    private(set) var reloadedURLs: Set<URL> = []

    /// Le schede aperte: per salvare tutto prima di toccare i file da fuori o di uscire.
    private var editors: [URL: () -> Void] = [:]

    /// Impostati dalle finestre (Main.swift).
    var showMainWindow: () -> Void = {}
    var showCard: (OpenDocument) -> Void = { _ in }
    var showSettings: (SettingsTab) -> Void = { _ in }
    var showOnboarding: () -> Void = {}

    private var refreshWork: DispatchWorkItem?

    private init() {
        let prefs = Preferences()
        self.prefs = prefs
        updater = Updater(prefs: prefs)
        knowledge = knowledgeStore.load()
        refresh()
    }

    // MARK: Schede

    func registerEditor(_ url: URL, flush: @escaping () -> Void) { editors[url] = flush }
    func unregisterEditor(_ url: URL) { editors[url] = nil }

    func flushEditor(_ url: URL) { editors[url]?() }

    /// Salva subito le schede aperte.
    func flushEditors() {
        for flush in editors.values { flush() }
    }

    // MARK: Aprire

    /// La pagina di to-do che serve adesso: oggi, oppure domani dopo l'ora scelta (di sera si scrive per domani).
    var targetDay: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard cal.component(.hour, from: Date()) >= prefs.eveningHour else { return today }
        return cal.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// Dal pannello rapido, dal menu nella barra, dal Dock o dalla barra strumenti: una scheda pronta per scrivere.
    func quickOpen(_ kind: NoteKind) {
        switch kind {
        case .todo:
            openTodo(targetDay)
        case .meeting:
            let new = store.createMeeting()
            showCard(OpenDocument(url: new.url, kind: .meeting, title: L("Riunione"), template: new.text, caret: new.caret))
        }
    }

    func openTodo(_ day: Date) {
        showCard(OpenDocument(url: store.todoURL(for: day), kind: .todo, title: Self.dayTitle(day)))
    }

    func open(_ ref: NoteRef) {
        if ref.kind == .todo, let day = store.day(of: ref.url) {
            openTodo(day)
        } else {
            showCard(OpenDocument(url: ref.url, kind: ref.kind, title: ref.title))
        }
    }

    /// La pagina (o la riunione) dove sta una to-do.
    func open(_ item: TodoItem) {
        if store.isMeeting(item.fileURL) {
            showCard(OpenDocument(url: item.fileURL, kind: .meeting, title: store.title(of: item.fileURL, kind: .meeting)))
        } else {
            openTodo(item.day)
        }
    }

    static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        let name = NoteStore.longDay(day)
        if cal.isDateInToday(day) { return L("Oggi, %@", name) }
        if cal.isDateInTomorrow(day) { return L("Domani, %@", name) }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    // MARK: To-do

    /// Spunta dalla vista Oggi o da un progetto: tutte le copie della stessa to-do.
    func toggle(_ board: BoardItem) {
        flushEditors()
        let done = !board.item.done
        var changed: Set<URL> = []
        for item in board.all {
            if (try? store.setDone(item, done)) == true { changed.insert(item.fileURL) }
        }
        afterExternalChange(changed)
    }

    /// Riporta da fare una to-do fatta oggi.
    func reopen(_ item: TodoItem) {
        flushEditors()
        if (try? store.setDone(item, false)) == true { afterExternalChange([item.fileURL]) }
    }

    private func afterExternalChange(_ urls: Set<URL>) {
        let open = urls.filter { editors[$0] != nil }
        if !open.isEmpty {
            reloadedURLs = open
            reloadToken += 1
        }
        refresh()
    }

    // MARK: Salvare e imparare

    func saved(text: String, to url: URL, kind: NoteKind) {
        do {
            try store.write(text, to: url)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        learn(from: text, kind: kind)
        scheduleRefresh()
    }

    /// Le sigle dei progetti e le persone trovate restano: la prossima volta si riconoscono ovunque.
    private func learn(from text: String, kind: NoteKind) {
        var k = knowledge
        var changed = false
        let lines = kind == .todo ? TodoParser.parse(text, knowledge: k) : TodoParser.parseMeeting(text)
        if kind == .meeting, let p = TodoParser.meetingProject(text) { changed = k.learnProject(p) || changed }
        for line in lines { if let p = line.project { changed = k.learnProject(p) || changed } }
        for e in EntityRecognizer.entities(in: text, kind: kind, lines: lines, knowledge: k) {
            switch e.kind {
            case .project: changed = k.learnProject(e.name) || changed
            case .person: changed = k.learnPerson(e.name) || changed
            default: break
            }
        }
        if changed { setKnowledge(k) }
    }

    func correct(_ correction: Correction) {
        var k = knowledge
        k.apply(correction)
        setKnowledge(k)
        refresh()
    }

    func forgetProject(_ sigla: String) { correct(.notProject(sigla)) }
    func forgetPerson(_ name: String) { correct(.notPerson(name)) }

    func setProjectName(_ sigla: String, _ name: String) {
        var k = knowledge
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        k.projectNames[sigla] = trimmed.isEmpty ? nil : trimmed
        setKnowledge(k)
    }

    private func setKnowledge(_ k: Knowledge) {
        guard k != knowledge else { return }
        knowledge = k
        knowledgeVersion += 1
        knowledgeStore.save(k)
    }

    // MARK: Rileggere

    func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func refresh() {
        board = TaskBoard(items: store.allTasks(knowledge: knowledge))
        todoPages = store.notes(.todo)
        meetings = store.notes(.meeting)
    }

    /// Progetti per la barra laterale: quelli con to-do aperte prima, poi gli altri che l'app conosce.
    var sidebarProjects: [ProjectCount] {
        let counts = board.openCounts
        let known = knowledge.projects
        let extra = counts.keys.filter { !known.contains($0) }.sorted()
        let all = (known + extra).map { ProjectCount(sigla: $0, open: counts[$0] ?? 0) }
        return all.filter { $0.open > 0 } + all.filter { $0.open == 0 }
    }

    func projectTitle(_ sigla: String) -> String {
        knowledge.projectNames[sigla].map { "\(sigla) · \($0)" } ?? sigla
    }
}
