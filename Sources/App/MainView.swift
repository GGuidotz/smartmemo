// La finestra principale, minimal: a sinistra Oggi, To-do, Riunioni e i progetti; a destra l'elenco. Le note non si
// scrivono qui: ogni pagina e ogni riunione si apre nella sua scheda (CardWindow.swift).
// Componenti di sistema per navigazione e controlli; la personalità sta nelle schede.

import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            content
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.quickOpen(.todo) } label: { Label(L("To-do"), systemImage: NoteKind.todo.symbol) }
                    .help(L("La pagina di to-do di oggi (⌘T)"))
                Button { model.quickOpen(.meeting) } label: { Label(L("Nuova riunione"), systemImage: NoteKind.meeting.symbol) }
                    .help(L("Una riunione nuova (⌘N)"))
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch model.sidebar ?? .today {
        case .today: TodayList(model: model)
        case .todos: NoteList(model: model, kind: .todo, refs: model.todoPages)
        case .meetings: NoteList(model: model, kind: .meeting, refs: model.meetings)
        case .project(let sigla): ProjectList(model: model, sigla: sigla)
        }
    }
}

// MARK: Barra laterale

private struct Sidebar: View {
    @ObservedObject var model: AppModel
    @State private var adding = false

    var body: some View {
        List(selection: $model.sidebar) {
            Section {
                Label(L("Oggi"), systemImage: "sun.max").badge(model.board.open.count).tag(SidebarItem.today)
                Label(L("To-do"), systemImage: NoteKind.todo.symbol).tag(SidebarItem.todos)
                Label(L("Riunioni"), systemImage: NoteKind.meeting.symbol).tag(SidebarItem.meetings)
            }
            Section {
                ForEach(model.sidebarProjects) { p in
                    Label {
                        Text(model.projectTitle(p.sigla)).lineLimit(1)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(Color.project(p.sigla, knowledge: model.knowledge))
                            .font(.system(size: 9))
                    }
                    .badge(p.open)
                    .tag(SidebarItem.project(p.sigla))
                    .contextMenu {
                        Button(L("Non è un progetto")) { model.forgetProject(p.sigla) }
                    }
                }
            } header: {
                HStack {
                    Text(L("Progetti"))
                    Spacer()
                    PlusButton(help: L("Aggiungi un progetto o una persona")) { adding = true }
                        .popover(isPresented: $adding, arrowEdge: .trailing) {
                            AddEntityPopover(model: model) { adding = false }
                        }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: Oggi

private struct TodayList: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let board = model.board
        List {
            if board.open.isEmpty && board.upcoming.isEmpty {
                ContentUnavailableView(L("Niente da fare"), systemImage: "checkmark.circle",
                                       description: Text(L("Scrivi le to-do nella pagina di oggi, o premi %@.", HotKey.display)))
            }
            let urgent = board.open.filter(\.item.urgent)
            if !urgent.isEmpty {
                Section(L("Urgenti")) { rows(urgent, showProject: true) }
            }
            ForEach(groups(board.open.filter { !$0.item.urgent })) { group in
                Section { rows(group.items, showProject: false) } header: { ProjectHeader(model: model, sigla: group.project) }
            }
            if !board.upcoming.isEmpty {
                Section(L("Prossimi giorni")) { rows(board.upcoming, showProject: true) }
            }
            if !board.doneToday.isEmpty {
                Section(L("Fatte oggi")) {
                    ForEach(board.doneToday) { item in
                        DoneRow(model: model, item: item)
                    }
                }
            }
        }
        .navigationTitle(L("Oggi"))
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button { model.openTodo(Calendar.current.startOfDay(for: Date())) } label: { Label(L("Pagina di oggi"), systemImage: "doc.text") }
                Button {
                    let cal = Calendar.current
                    model.openTodo(cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date())
                } label: { Label(L("Pagina di domani"), systemImage: "sunrise") }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func rows(_ items: [BoardItem], showProject: Bool) -> some View {
        ForEach(items) { b in TaskRow(model: model, board: b, showProject: showProject) }
    }

    private struct Group: Identifiable {
        let key: String
        let project: String?
        let items: [BoardItem]
        var id: String { key }
    }

    private func groups(_ items: [BoardItem]) -> [Group] {
        var order: [String] = []
        var map: [String: [BoardItem]] = [:]
        for b in items {
            let key = b.item.project ?? ""
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(b)
        }
        // Senza progetto in fondo.
        order.sort { a, b in a.isEmpty == b.isEmpty ? false : !a.isEmpty }
        return order.map { Group(key: $0, project: $0.isEmpty ? nil : $0, items: map[$0] ?? []) }
    }
}

private struct ProjectHeader: View {
    @ObservedObject var model: AppModel
    let sigla: String?

    var body: some View {
        if let sigla {
            HStack(spacing: 6) {
                Circle().fill(Color.project(sigla, knowledge: model.knowledge)).frame(width: 8, height: 8)
                Text(model.projectTitle(sigla))
            }
        } else {
            Text(L("Senza progetto"))
        }
    }
}

/// Una to-do aperta: cerchio da spuntare, testo, progetto se serve, da quanti giorni è riportata.
private struct TaskRow: View {
    @ObservedObject var model: AppModel
    let board: BoardItem
    var showProject = false

    var body: some View {
        let item = board.item
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button { model.toggle(board) } label: {
                Image(systemName: "circle")
                    .foregroundStyle(item.urgent ? Color.red : Color.secondary)
                    .font(.system(size: 15))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L("Segna come fatta"))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if item.urgent {
                        Text("URGENTE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red, in: .capsule)
                    }
                    if showProject, let p = item.project {
                        Text(p).font(.caption.weight(.semibold))
                            .padding(.horizontal, 5)
                            .background(Color.project(p, knowledge: model.knowledge).opacity(0.16), in: .capsule)
                    }
                    Text(item.text).lineLimit(3)
                }
                if board.carriedDays > 0 {
                    Label(board.carriedDays == 1 ? L("da ieri") : L("da %d giorni", board.carriedDays),
                          systemImage: "arrow.uturn.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture(count: 2) { model.open(item) }
        .help(L("Doppio clic: apri la pagina"))
        .contextMenu {
            Button(L("Segna come fatta")) { model.toggle(board) }
            Button(L("Apri la pagina")) { model.open(item) }
        }
    }
}

private struct DoneRow: View {
    @ObservedObject var model: AppModel
    let item: TodoItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button { model.reopen(item) } label: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).font(.system(size: 15))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L("Segna da fare"))
            Text(item.text).strikethrough().foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

// MARK: Progetto

private struct ProjectList: View {
    @ObservedObject var model: AppModel
    let sigla: String
    @State private var longName = ""

    var body: some View {
        let open = model.board.open(in: sigla)
        List {
            Section {
                TextField(L("Nome del progetto (facoltativo)"), text: $longName)
                    .onSubmit { model.setProjectName(sigla, longName) }
                    .textFieldStyle(.roundedBorder)
            }
            if open.isEmpty {
                ContentUnavailableView(L("Niente da fare per %@", sigla), systemImage: "checkmark.circle")
            } else {
                Section(L("Da fare")) {
                    ForEach(open) { b in TaskRow(model: model, board: b) }
                }
            }
        }
        .navigationTitle(model.projectTitle(sigla))
        .onAppear { longName = model.knowledge.projectNames[sigla] ?? "" }
        .onChange(of: sigla) { longName = model.knowledge.projectNames[sigla] ?? "" }
    }
}

// MARK: Elenco di pagine e riunioni

/// Un clic apre la scheda.
private struct NoteList: View {
    @ObservedObject var model: AppModel
    let kind: NoteKind
    let refs: [NoteRef]
    @State private var selection: URL?

    var body: some View {
        List(selection: $selection) {
            if refs.isEmpty {
                ContentUnavailableView(kind == .todo ? L("Nessuna pagina di to-do") : L("Nessuna riunione"),
                                       systemImage: kind.symbol,
                                       description: Text(L("Premi %@ da qualsiasi app per cominciare.", HotKey.display)))
            }
            ForEach(refs) { ref in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.title).lineLimit(1)
                    if kind == .meeting {
                        Text(ref.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .tag(ref.url)
                .contextMenu {
                    Button(L("Apri")) { model.open(ref) }
                    Button(L("Mostra nel Finder")) { NSWorkspace.shared.activateFileViewerSelecting([ref.url]) }
                }
            }
        }
        .navigationTitle(kind.title)
        .onChange(of: selection) {
            guard let url = selection, let ref = refs.first(where: { $0.url == url }) else { return }
            model.open(ref)
            selection = nil   // così un altro clic sulla stessa riga la riapre
        }
    }
}
