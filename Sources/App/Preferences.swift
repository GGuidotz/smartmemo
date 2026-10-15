// Le scelte di chi usa l'app, in UserDefaults. Predefiniti pronti: si usa senza toccare nulla.

import Foundation

@MainActor
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard

    /// ⌃⌥Spazio da qualsiasi app apre il pannello rapido.
    @Published var hotKeyEnabled: Bool { didSet { defaults.set(hotKeyEnabled, forKey: "hotKeyEnabled"); onChange() } }
    /// L'icona nella barra dei menu (le stesse voci sono anche nel Dock e nel menu Archivio).
    @Published var menuBarIcon: Bool { didSet { defaults.set(menuBarIcon, forKey: "menuBarIcon"); onChange() } }
    /// Da quest'ora le to-do nuove vanno nella pagina di domani.
    @Published var eveningHour: Int { didSet { defaults.set(eveningHour, forKey: "eveningHour") } }
    /// Le schede delle note restano sopra le altre finestre.
    @Published var cardsOnTop: Bool { didSet { defaults.set(cardsOnTop, forKey: "cardsOnTop"); onChange() } }
    /// Riassunti delle riunioni con Apple Intelligence (sul Mac). Spento: riassunto con le regole.
    @Published var useAppleIntelligence: Bool { didSet { defaults.set(useAppleIntelligence, forKey: "useAppleIntelligence") } }
    @Published var autoCheckUpdates: Bool { didSet { defaults.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }
    /// Cosa si evidenzia nelle schede (si riconosce comunque: serve a Oggi e ai progetti).
    @Published var highlightProjects: Bool { didSet { defaults.set(highlightProjects, forKey: "highlightProjects"); onChange() } }
    @Published var highlightPeople: Bool { didSet { defaults.set(highlightPeople, forKey: "highlightPeople"); onChange() } }
    @Published var highlightDates: Bool { didSet { defaults.set(highlightDates, forKey: "highlightDates"); onChange() } }
    @Published var highlightUrgent: Bool { didSet { defaults.set(highlightUrgent, forKey: "highlightUrgent"); onChange() } }
    /// La guida iniziale è stata vista (chiusa o finita).
    @Published var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    /// L'ultima versione di cui si sono viste le novità.
    var lastSeenVersion: String {
        get { defaults.string(forKey: "lastSeenVersion") ?? "0" }
        set { defaults.set(newValue, forKey: "lastSeenVersion") }
    }
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            Localization.language = language
            onChange()
        }
    }

    func highlights(_ kind: EntityKind) -> Bool {
        switch kind {
        case .project: highlightProjects
        case .person: highlightPeople
        case .date: highlightDates
        case .urgent: highlightUrgent
        }
    }

    /// Per il file di configurazione.
    var highlightMap: [String: Bool] {
        [EntityKind.project.rawValue: highlightProjects, EntityKind.person.rawValue: highlightPeople,
         EntityKind.date.rawValue: highlightDates, EntityKind.urgent.rawValue: highlightUrgent]
    }

    func setHighlights(_ map: [String: Bool]) {
        if let v = map[EntityKind.project.rawValue] { highlightProjects = v }
        if let v = map[EntityKind.person.rawValue] { highlightPeople = v }
        if let v = map[EntityKind.date.rawValue] { highlightDates = v }
        if let v = map[EntityKind.urgent.rawValue] { highlightUrgent = v }
    }

    /// Chiamato dopo ogni cambio che tocca menu, scorciatoia, icona o schede.
    var onChange: () -> Void = {}

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["hotKeyEnabled": true, "menuBarIcon": true, "eveningHour": 17, "cardsOnTop": false,
                              "useAppleIntelligence": true, "autoCheckUpdates": true, "highlightProjects": true,
                              "highlightPeople": true, "highlightDates": true, "highlightUrgent": true])
        hotKeyEnabled = d.bool(forKey: "hotKeyEnabled")
        menuBarIcon = d.bool(forKey: "menuBarIcon")
        eveningHour = d.integer(forKey: "eveningHour")
        cardsOnTop = d.bool(forKey: "cardsOnTop")
        useAppleIntelligence = d.bool(forKey: "useAppleIntelligence")
        autoCheckUpdates = d.bool(forKey: "autoCheckUpdates")
        highlightProjects = d.bool(forKey: "highlightProjects")
        highlightPeople = d.bool(forKey: "highlightPeople")
        highlightDates = d.bool(forKey: "highlightDates")
        highlightUrgent = d.bool(forKey: "highlightUrgent")
        onboardingDone = d.bool(forKey: "onboardingDone")
        language = AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .system
        Localization.language = language
    }
}

/// Confronto numerico tra versioni ("0.10.0" > "0.9.2").
struct Version: Comparable {
    let parts: [Int]
    init(_ string: String) { parts = string.split(separator: ".").map { Int($0) ?? 0 } }

    static func < (a: Version, b: Version) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: Version, b: Version) -> Bool { !(a < b) && !(b < a) }
}
