// Mette in ordine le to-do di tutte le pagine per la vista Oggi e per i progetti.
// Riporto: una to-do non fatta di un giorno passato resta in Oggi con "da N giorni", finché non la spunti. Se la
// riscrivi in una pagina nuova (stesso progetto, stesso testo) vale come la stessa: si vede una volta sola e spuntarla
// la segna fatta in tutte le pagine.

import Foundation

struct BoardItem: Identifiable, Hashable {
    /// La copia più recente.
    let item: TodoItem
    /// Le altre copie non fatte nelle pagine precedenti.
    let older: [TodoItem]
    /// Giorni dalla prima volta che compare, contati da oggi (0 se è di oggi o di domani).
    let carriedDays: Int

    var id: String { item.id }
    var all: [TodoItem] { [item] + older }
}

struct TaskBoard {
    /// Aperte, di oggi o dei giorni passati.
    var open: [BoardItem] = []
    /// Aperte, scritte per i prossimi giorni.
    var upcoming: [BoardItem] = []
    /// Fatte oggi (nella pagina di oggi).
    var doneToday: [TodoItem] = []

    init() {}

    init(items: [TodoItem], today: Date = Date(), calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: today)
        let undone = items.filter { !$0.done }
        let groups = Dictionary(grouping: undone, by: \.identity)
        var open: [BoardItem] = []
        var upcoming: [BoardItem] = []
        for (_, copies) in groups {
            let sorted = copies.sorted { $0.day > $1.day }
            guard let newest = sorted.first, let oldest = sorted.last else { continue }
            let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: oldest.day), to: start).day ?? 0)
            let board = BoardItem(item: newest, older: Array(sorted.dropFirst()), carriedDays: days)
            if calendar.startOfDay(for: newest.day) > start, oldest.day > start {
                upcoming.append(board)
            } else {
                open.append(board)
            }
        }
        self.open = open.sorted(by: Self.order)
        self.upcoming = upcoming.sorted(by: Self.order)
        doneToday = items.filter { $0.done && calendar.isDate($0.day, inSameDayAs: start) }
    }

    /// URGENTE prima, poi le pagine più recenti, e nella stessa pagina l'ordine in cui sono scritte.
    private static func order(_ a: BoardItem, _ b: BoardItem) -> Bool {
        if a.item.urgent != b.item.urgent { return a.item.urgent }
        if a.item.day != b.item.day { return a.item.day > b.item.day }
        return a.item.lineRange.location < b.item.lineRange.location
    }

    /// Le aperte di un progetto (nil: senza progetto).
    func open(in project: String?) -> [BoardItem] {
        (open + upcoming).filter { $0.item.project == project }
    }

    /// Progetti con almeno una to-do aperta, con il conteggio.
    var openCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for b in open + upcoming { if let p = b.item.project { counts[p, default: 0] += 1 } }
        return counts
    }
}
