// I tipi di base: i tre tipi di nota, una nota sul disco, una to-do e ciò che l'app ha imparato (progetti, persone,
// correzioni). Solo Foundation.

import Foundation

enum NoteKind: String, CaseIterable, Codable, Identifiable {
    case todo, meeting
    var id: String { rawValue }

    /// La cartella dentro la cartella delle note. Nomi fissi, non tradotti: sono sul disco.
    var folderName: String {
        switch self {
        case .todo: "To-do"
        case .meeting: "Riunioni"
        }
    }

    var title: String {
        switch self {
        case .todo: L("To-do")
        case .meeting: L("Riunioni")
        }
    }

    /// Il nome di una nota nuova di questo tipo, per menu e pulsanti.
    var newTitle: String {
        switch self {
        case .todo: L("To-do")
        case .meeting: L("Riunione")
        }
    }

    var symbol: String {
        switch self {
        case .todo: "checklist"
        case .meeting: "person.2"
        }
    }
}

/// Una nota sul disco.
struct NoteRef: Identifiable, Hashable {
    let url: URL
    let kind: NoteKind
    let title: String
    let date: Date
    var id: URL { url }
}

/// Una to-do letta da una pagina di to-do.
struct TodoItem: Identifiable, Hashable {
    let fileURL: URL
    /// Il giorno della pagina.
    let day: Date
    /// La riga nel testo della pagina (UTF-16), senza a capo.
    let lineRange: NSRange
    /// Il testo della riga com'è scritta: serve a ritrovarla prima di cambiarla.
    let line: String
    let project: String?
    /// Il testo da mostrare: senza segno di fatto, sigla e URGENTE.
    let text: String
    let done: Bool
    let urgent: Bool

    var id: String { "\(fileURL.lastPathComponent)#\(lineRange.location)#\(line)" }

    /// Chiave per riconoscere la stessa to-do riscritta in giorni diversi.
    var identity: String { "\(project?.lowercased() ?? "")|\(text.lowercased())" }
}

/// Correzioni dal menu contestuale dell'editor.
enum Correction: Hashable {
    case person(String), notPerson(String), project(String), notProject(String)
}

/// Ciò che SmartMemo ha imparato: sigle dei progetti, persone e clienti, e le correzioni di chi scrive.
struct Knowledge: Codable, Equatable {
    /// Sigle, nell'ordine in cui sono comparse (l'ordine decide il colore).
    var projects: [String] = []
    /// Nomi lunghi facoltativi: "SITO" → "Nuovo sito".
    var projectNames: [String: String] = [:]
    var people: [String] = []
    /// In minuscolo: parole che non sono persone o progetti, anche se sembrano.
    var notPeople: [String] = []
    var notProjects: [String] = []

    func isProject(_ s: String) -> Bool { projects.contains(s) }
    func isIgnoredProject(_ s: String) -> Bool { notProjects.contains(s.lowercased()) }
    func isIgnoredPerson(_ s: String) -> Bool { notPeople.contains(s.lowercased()) }

    /// Aggiunge senza duplicati; dice se qualcosa è cambiato.
    @discardableResult
    mutating func learnProject(_ sigla: String) -> Bool {
        guard !sigla.isEmpty, !projects.contains(sigla), !isIgnoredProject(sigla) else { return false }
        projects.append(sigla)
        return true
    }

    @discardableResult
    mutating func learnPerson(_ name: String) -> Bool {
        guard !name.isEmpty, !people.contains(name), !isIgnoredPerson(name) else { return false }
        people.append(name)
        return true
    }

    mutating func apply(_ correction: Correction) {
        switch correction {
        case .person(let n):
            notPeople.removeAll { $0 == n.lowercased() }
            notProjects.removeAll { $0 == n.lowercased() }
            projects.removeAll { $0 == n }
            learnPerson(n)
        case .notPerson(let n):
            people.removeAll { $0 == n }
            if !notPeople.contains(n.lowercased()) { notPeople.append(n.lowercased()) }
        case .project(let s):
            notProjects.removeAll { $0 == s.lowercased() }
            people.removeAll { $0 == s }
            learnProject(s)
        case .notProject(let s):
            projects.removeAll { $0 == s }
            projectNames[s] = nil
            if !notProjects.contains(s.lowercased()) { notProjects.append(s.lowercased()) }
        }
    }
}

/// Salva Knowledge in Application Support/SmartMemo/knowledge.json.
struct KnowledgeStore {
    let url: URL

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.url = base.appendingPathComponent("SmartMemo/knowledge.json")
        }
    }

    func load() -> Knowledge {
        guard let data = try? Data(contentsOf: url),
              let k = try? JSONDecoder().decode(Knowledge.self, from: data) else { return Knowledge() }
        return k
    }

    func save(_ k: Knowledge) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(k) { try? data.write(to: url, options: .atomic) }
    }
}
