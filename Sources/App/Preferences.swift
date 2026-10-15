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

    /// Chiamato dopo ogni cambio che tocca menu, scorciatoia, icona o schede.
    var onChange: () -> Void = {}

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["hotKeyEnabled": true, "menuBarIcon": true, "eveningHour": 17, "cardsOnTop": false,
                              "useAppleIntelligence": true, "autoCheckUpdates": true])
        hotKeyEnabled = d.bool(forKey: "hotKeyEnabled")
        menuBarIcon = d.bool(forKey: "menuBarIcon")
        eveningHour = d.integer(forKey: "eveningHour")
        cardsOnTop = d.bool(forKey: "cardsOnTop")
        useAppleIntelligence = d.bool(forKey: "useAppleIntelligence")
        autoCheckUpdates = d.bool(forKey: "autoCheckUpdates")
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
