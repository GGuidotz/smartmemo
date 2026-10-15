// Le note sono file Markdown in una cartella di iCloud Drive (SmartMemo), leggibili e modificabili anche senza l'app:
//   To-do/2026-10-15.md            una pagina di to-do per giorno
//   Riunioni/2026-10-02 17.00.md   note di riunione
// Senza iCloud Drive la cartella sta in Documenti. Nessun indice da tenere in pari: si rilegge dai file, che sono
// pochi e piccoli.

import Foundation

final class NoteStore {
    let root: URL
    private let fm = FileManager.default

    init(root: URL? = nil) {
        self.root = root ?? NoteStore.defaultRoot()
    }

    static func defaultRoot() -> URL {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: iCloud.path, isDirectory: &isDir), isDir.boolValue {
            return iCloud.appendingPathComponent("SmartMemo")
        }
        return home.appendingPathComponent("Documents/SmartMemo")
    }

    var isInICloud: Bool { root.path.contains("Mobile Documents") }

    func folder(_ kind: NoteKind) -> URL {
        let url = root.appendingPathComponent(kind.folderName, isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Leggere e scrivere

    func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Scrive solo se il testo è cambiato. Una pagina di to-do vuota e mai salvata non crea il file.
    func write(_ text: String, to url: URL) throws {
        let exists = fm.fileExists(atPath: url.path)
        if !exists && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        if exists, read(url) == text { return }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Pagine di to-do

    func todoURL(for day: Date) -> URL {
        folder(.todo).appendingPathComponent(Self.dayFormatter.string(from: day) + ".md")
    }

    func day(of url: URL) -> Date? {
        Self.dayFormatter.date(from: url.deletingPathExtension().lastPathComponent)
    }

    /// Tutte le to-do: quelle delle pagine di to-do e le caselle delle riunioni, dalla più recente.
    func allTasks(knowledge: Knowledge) -> [TodoItem] {
        var items: [TodoItem] = []
        func add(_ url: URL, day: Date, text: String, lines: [ParsedLine]) {
            let ns = text as NSString
            for line in lines where line.kind == .task && !line.body.isEmpty {
                items.append(TodoItem(fileURL: url, day: day, lineRange: line.range, line: ns.substring(with: line.range),
                                      project: line.project, text: line.body, done: line.done, urgent: line.urgent))
            }
        }
        for url in markdownFiles(in: folder(.todo)) {
            guard let day = day(of: url) else { continue }
            let text = read(url)
            add(url, day: day, text: text, lines: TodoParser.parse(text, knowledge: knowledge))
        }
        for url in markdownFiles(in: folder(.meeting)) {
            let text = read(url)
            guard text.contains("[ ]") || text.contains("[x]") || text.contains("[X]") else { continue }
            let day = meetingDay(of: url)
            add(url, day: day, text: text, lines: TodoParser.parseMeeting(text))
        }
        return items.sorted { $0.day > $1.day }
    }

    func isMeeting(_ url: URL) -> Bool {
        url.deletingLastPathComponent().lastPathComponent == NoteKind.meeting.folderName
    }

    /// Il giorno di una riunione, dal nome del file ("2026-10-02 17.00.md").
    func meetingDay(of url: URL) -> Date {
        let name = url.deletingPathExtension().lastPathComponent
        return Self.dayFormatter.date(from: String(name.prefix(10)))
            ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }

    /// Segna fatta o da fare una to-do nel suo file. Ritrova la riga dal testo, non solo dalla posizione: il file può
    /// essere cambiato nel frattempo. Dice se ha trovato la riga.
    @discardableResult
    func setDone(_ item: TodoItem, _ done: Bool) throws -> Bool {
        let text = read(item.fileURL)
        let ns = NSMutableString(string: text)
        var range = item.lineRange
        if range.upperBound > ns.length || ns.substring(with: range) != item.line {
            let found = ns.range(of: item.line)
            guard found.location != NSNotFound else { return false }
            range = found
        }
        let line = ns.substring(with: range)
        // Casella Markdown ("- [ ] " o "* [x] "): si cambia solo il carattere tra le parentesi.
        if let m = TodoParser.boxRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
            ns.replaceCharacters(in: NSRange(location: range.location + m.range(at: 1).location, length: 1), with: done ? "x" : " ")
            try write(ns as String, to: item.fileURL)
            return true
        }
        let isDone = line.hasPrefix("✓")
        guard isDone != done else { return true }
        if done {
            ns.insert(TodoParser.doneMark, at: range.location)
        } else {
            let length = line.hasPrefix(TodoParser.doneMark) ? (TodoParser.doneMark as NSString).length : 1
            ns.deleteCharacters(in: NSRange(location: range.location, length: length))
        }
        try write(ns as String, to: item.fileURL)
        return true
    }

    // MARK: Elenchi e riunioni

    func notes(_ kind: NoteKind) -> [NoteRef] {
        markdownFiles(in: folder(kind)).map { url in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return NoteRef(url: url, kind: kind, title: title(of: url, kind: kind), date: date)
        }
        .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    /// Il titolo: la data per le pagine di to-do, la prima riga per le riunioni.
    func title(of url: URL, kind: NoteKind) -> String {
        if kind == .todo, let day = day(of: url) { return Self.longDay(day) }
        let first = read(url).split(separator: "\n").lazy
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces)) }
            .first { !$0.isEmpty }
        if let first { return String(first.prefix(80)) }
        return L("Riunione senza titolo")
    }

    /// Una riunione nuova con il suo modello; restituisce dove sta, il testo iniziale e dove mettere il cursore.
    func createMeeting(now: Date = Date()) -> (url: URL, text: String, caret: Int) {
        let kind = NoteKind.meeting
        let base = Self.stampFormatter.string(from: now)
        var url = folder(kind).appendingPathComponent(base + ".md")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = folder(kind).appendingPathComponent("\(base) \(n).md")
            n += 1
        }
        // "Riunione #" con il cursore dopo il cancelletto: scrivi la sigla del progetto e si accende.
        let first = L("Riunione") + " #"
        let text = first + "\n" + Self.longDayTime(now) + "\n\n"
        return (url, text, (first as NSString).length)
    }

    // MARK: Utilità

    private func markdownFiles(in folder: URL) -> [URL] {
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                options: [.skipsHiddenFiles])) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "md" }
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return f
    }()

    /// "giovedì 15 ottobre"
    static func longDay(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(locale: Localization.locale).weekday(.wide).day().month(.wide))
    }

    /// "14 ottobre 2026, 20:15"
    static func longDayTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: Localization.locale).day().month(.wide).year().hour().minute())
    }
}
