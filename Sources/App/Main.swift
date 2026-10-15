// Avvio AppKit, come Nod e What's Going On: la scorciatoia globale, il pannello rapido e l'icona nella barra dei menu
// devono funzionare anche a finestra chiusa, e le schede si aprono da lì quando servono.
// L'app resta aperta quando chiudi le finestre (⌃⌥Spazio deve rispondere sempre); il Dock e il menu la riaprono.
// Al primo avvio la guida; dopo un aggiornamento, le note di rilascio.

import AppKit
import SwiftUI

@main
enum SmartMemoMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            app.delegate = AppDelegate.shared
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private var model: AppModel { AppModel.shared }
    private var window: NSWindow?
    private lazy var quickPanel = QuickPanelController(model: model)
    private let hotKey = HotKey()
    private var statusItem: NSStatusItem?
    private let settings = SettingsWindowController()
    private let onboarding = OnboardingWindowController()
    private lazy var cards = CardWindows(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.showMainWindow = { [weak self] in self?.showMainWindow() }
        model.showCard = { [weak self] doc in self?.cards.show(doc) }
        model.showSettings = { [weak self] tab in self?.showSettings(tab) }
        model.showOnboarding = { [weak self] in self?.showOnboarding() }
        model.prefs.onChange = { [weak self] in self?.applyPreferences() }
        applyPreferences()
        model.updater.start()
        diag(.app, "launched \(SystemInfo.version)")

        let prefs = model.prefs
        if !prefs.onboardingDone {
            showOnboarding()
        } else {
            showMainWindow()
            if Version(SystemInfo.version) > Version(prefs.lastSeenVersion) {
                prefs.lastSeenVersion = SystemInfo.version
                showSettings(.updates)   // le note di rilascio della versione appena installata
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refresh()   // le note possono essere cambiate da fuori (iCloud, un altro editor)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.flushEditors()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for item in newItems(withShortcuts: false) { menu.addItem(item) }
        return menu
    }

    // MARK: Preferenze

    private func applyPreferences() {
        NSApp.mainMenu = MainMenu.make()
        // Cambio di lingua: la finestra principale si ridisegna subito.
        (window?.contentViewController as? NSHostingController<MainView>)?.rootView = MainView(model: model)
        cards.applyPreferences()
        if model.prefs.hotKeyEnabled {
            hotKey.register { [weak self] in self?.quickPanel.toggle() }
        } else {
            hotKey.unregister()
        }
        if model.prefs.menuBarIcon {
            let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "SmartMemo")
            item.button?.image?.isTemplate = true
            item.menu = statusMenu()
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func statusMenu() -> NSMenu {
        let menu = NSMenu()
        for item in newItems(withShortcuts: false) { menu.addItem(item) }
        menu.addItem(.separator())
        menu.addItem(target(NSMenuItem(title: L("Apri SmartMemo"), action: #selector(showMainWindowAction(_:)), keyEquivalent: "")))
        menu.addItem(target(NSMenuItem(title: L("Impostazioni…"), action: #selector(openSettings(_:)), keyEquivalent: "")))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Esci da SmartMemo"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        return menu
    }

    /// To-do e Riunione: nel menu Archivio, nella barra dei menu e nel Dock.
    func newItems(withShortcuts: Bool) -> [NSMenuItem] {
        let specs: [(NoteKind, String, NSEvent.ModifierFlags)] = [
            (.todo, "t", [.command]), (.meeting, "n", [.command]),
        ]
        return specs.map { kind, key, mods in
            let title = kind == .todo ? L("To-do di oggi") : L("Nuova riunione")
            let item = NSMenuItem(title: title, action: #selector(newDocument(_:)), keyEquivalent: withShortcuts ? key : "")
            if withShortcuts { item.keyEquivalentModifierMask = mods }
            item.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
            item.representedObject = kind.rawValue
            item.target = self
            return item
        }
    }

    private func target(_ item: NSMenuItem) -> NSMenuItem {
        item.target = self
        return item
    }

    // MARK: Azioni

    @objc func newDocument(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = NoteKind(rawValue: raw) else { return }
        model.quickOpen(kind)
    }

    @objc func quickPanelAction(_ sender: Any?) { quickPanel.show() }
    @objc func showMainWindowAction(_ sender: Any?) { showMainWindow() }
    @objc func openSettings(_ sender: Any?) { showSettings(nil) }
    @objc func openReleaseNotes(_ sender: Any?) { showSettings(.updates) }
    @objc func openFeedback(_ sender: Any?) { showSettings(.feedback) }
    @objc func openOnboarding(_ sender: Any?) { showOnboarding() }
    @objc func reportProblem(_ sender: Any?) { Feedback.openIssue(.problem) }
    @objc func showAbout(_ sender: Any?) { AboutPanel.show() }

    func showSettings(_ tab: SettingsTab?) { settings.show(model: model, tab: tab) }
    func showOnboarding() { onboarding.show(model: model) }

    @objc func showSection(_ sender: NSMenuItem) {
        let sections: [SidebarItem] = [.today, .todos, .meetings]
        guard sections.indices.contains(sender.tag) else { return }
        showMainWindow()
        model.sidebar = sections[sender.tag]
    }

    // MARK: Finestra

    func showMainWindow() {
        if window == nil {
            let host = NSHostingController(rootView: MainView(model: model))
            host.sceneBridgingOptions = [.toolbars, .title]
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.title = "SmartMemo"
            w.setContentSize(NSSize(width: 760, height: 560))
            w.isReleasedWhenClosed = false
            // Torna dov'era e grande com'era (HIG, Avvio: ripristina lo stato).
            if !w.setFrameUsingName("SmartMemoMain") { w.center() }
            w.setFrameAutosaveName("SmartMemoMain")
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: Menu

enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let delegate = AppDelegate.shared
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: L("Informazioni su SmartMemo"), action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "").target = delegate
        app.addItem(.separator())
        app.addItem(withTitle: L("Impostazioni…"), action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ",").target = delegate
        app.addItem(.separator())
        app.addItem(withTitle: L("Nascondi SmartMemo"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: L("Nascondi altre"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: L("Mostra tutte"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: L("Esci da SmartMemo"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: app, title: "SmartMemo")

        let file = NSMenu(title: L("Archivio"))
        for item in delegate.newItems(withShortcuts: true) { file.addItem(item) }
        let quick = file.addItem(withTitle: L("Apertura rapida…"), action: #selector(AppDelegate.quickPanelAction(_:)), keyEquivalent: "")
        quick.target = delegate
        quick.toolTip = HotKey.display
        file.addItem(.separator())
        file.addItem(withTitle: L("Chiudi"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: file, title: file.title)

        let edit = NSMenu(title: L("Modifica"))
        edit.addItem(withTitle: L("Annulla"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("Ripeti"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L("Taglia"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("Copia"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Incolla"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("Seleziona tutto"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = edit.addItem(withTitle: L("Trova…"), action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        main.addItem(submenu: edit, title: edit.title)

        let todo = NSMenu(title: L("To-do"))
        todo.addItem(withTitle: L("Segna come fatta / da fare"), action: #selector(NoteTextView.toggleDone(_:)), keyEquivalent: "k")
        main.addItem(submenu: todo, title: todo.title)

        let view = NSMenu(title: L("Vista"))
        for (i, title) in [L("Oggi"), L("To-do"), L("Riunioni")].enumerated() {
            let item = view.addItem(withTitle: title, action: #selector(AppDelegate.showSection(_:)), keyEquivalent: "\(i + 1)")
            item.tag = i
            item.target = delegate
        }
        view.addItem(.separator())
        let sidebar = view.addItem(withTitle: L("Mostra o nascondi la barra laterale"),
                                   action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .control]
        main.addItem(submenu: view, title: view.title)

        let window = NSMenu(title: L("Finestra"))
        window.addItem(withTitle: L("Riduci"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: L("Ridimensiona"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "SmartMemo", action: #selector(AppDelegate.showMainWindowAction(_:)), keyEquivalent: "0").target = delegate
        main.addItem(submenu: window, title: window.title)
        NSApp.windowsMenu = window

        let help = NSMenu(title: L("Aiuto"))
        help.addItem(withTitle: L("Guida iniziale"), action: #selector(AppDelegate.openOnboarding(_:)), keyEquivalent: "").target = delegate
        help.addItem(withTitle: L("Note di rilascio"), action: #selector(AppDelegate.openReleaseNotes(_:)), keyEquivalent: "").target = delegate
        help.addItem(.separator())
        help.addItem(withTitle: L("Segnala un problema…"), action: #selector(AppDelegate.reportProblem(_:)), keyEquivalent: "").target = delegate
        help.addItem(withTitle: L("Feedback e diagnostica"), action: #selector(AppDelegate.openFeedback(_:)), keyEquivalent: "").target = delegate
        main.addItem(submenu: help, title: help.title)
        NSApp.helpMenu = help
        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
