// La configurazione iniziale dalle note di chi usa l'app. Incolli (o apri da un file) qualche pagina di to-do o di
// riunione scritta come la scrivi di solito; SmartMemo propone cosa sono le parole che spiccano (sigle, nomi) e tu
// decidi: progetto, persona o cliente, niente. Il testo si legge e basta: non si salva e non esce dal Mac.
// La configurazione (ciò che l'app sa e cosa evidenziare) si può anche esportare e importare come file JSON, per
// portarla su un altro Mac o ripartire da lì. È un file dell'utente: non sta nel repository né nell'app.

import Foundation

struct SetupCandidate: Identifiable, Hashable {
    enum Role: String, CaseIterable, Identifiable {
        case project, person, ignore
        var id: String { rawValue }
    }

    let name: String
    var role: Role
    /// Quante volte compare nel testo.
    let count: Int
    /// La prima riga in cui compare, per riconoscerla.
    let example: String
    var id: String { name }
}

enum SetupAnalyzer {
    /// Le sigle e i nomi del testo, con la proposta di cosa sono. Prima i progetti, poi le persone; i più frequenti prima.
    static func candidates(in text: String, knowledge: Knowledge) -> [SetupCandidate] {
        let ns = text as NSString
        var order: [String] = []
        var roles: [String: SetupCandidate.Role] = [:]
        var counts: [String: Int] = [:]
        var examples: [String: String] = [:]

        func add(_ name: String, _ role: SetupCandidate.Role, at location: Int) {
            let key = name.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return }
            if roles[key] == nil {
                order.append(key)
                roles[key] = role
                let line = ns.substring(with: ns.lineRange(for: NSRange(location: location, length: 0)))
                examples[key] = String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(90))
            }
            counts[key, default: 0] += 1
        }

        let lines = TodoParser.parse(text, knowledge: knowledge)
        for e in EntityRecognizer.entities(in: text, kind: .todo, lines: lines, knowledge: knowledge) {
            switch e.kind {
            case .project: add(e.name, .project, at: e.range.location)
            case .person: add(e.name, .person, at: e.range.location)
            default: break
            }
        }
        let all = order.map { SetupCandidate(name: $0, role: roles[$0] ?? .ignore, count: counts[$0] ?? 1, example: examples[$0] ?? "") }
        func rank(_ r: SetupCandidate.Role) -> Int { r == .project ? 0 : (r == .person ? 1 : 2) }
        return all.sorted {
            if rank($0.role) != rank($1.role) { return rank($0.role) < rank($1.role) }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Ciò che l'app sa, con le scelte fatte nella procedura.
    static func apply(_ candidates: [SetupCandidate], to knowledge: Knowledge) -> Knowledge {
        var k = knowledge
        for c in candidates {
            switch c.role {
            case .project: k.apply(.project(c.name))
            case .person: k.apply(.person(c.name))
            case .ignore:
                k.apply(.notProject(c.name))
                k.apply(.notPerson(c.name))
            }
        }
        return k
    }
}

/// Il file di configurazione esportato: ciò che l'app sa e cosa evidenziare. Resta dove lo salvi tu.
struct SetupFile: Codable {
    var format = "smartmemo-config"
    var version = 1
    var knowledge: Knowledge
    /// "project", "person", "date", "urgent" → evidenziare o no.
    var highlight: [String: Bool]?
}

extension Knowledge {
    /// Unisce un'altra configurazione a questa: aggiunge senza togliere, e le correzioni valgono.
    func merged(with other: Knowledge) -> Knowledge {
        var k = self
        for s in other.notProjects where !k.notProjects.contains(s) { k.notProjects.append(s) }
        for s in other.notPeople where !k.notPeople.contains(s) { k.notPeople.append(s) }
        for p in other.projects { k.learnProject(p) }
        for p in other.people { k.learnPerson(p) }
        for (sigla, name) in other.projectNames where k.projectNames[sigla] == nil { k.projectNames[sigla] = name }
        return k
    }
}
