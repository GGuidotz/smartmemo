// Il + per aggiungere a mano un progetto o una persona, nella barra laterale, nelle impostazioni e nella
// configurazione guidata. Il pulsante apre un campo: Invio aggiunge e lascia il campo aperto per il prossimo,
// Esc (o Invio a campo vuoto) lo chiude.

import AppKit
import SwiftUI

/// Il + nelle intestazioni delle sezioni.
struct PlusButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Il campo che compare col +. `add` aggiunge e dice il nome com'è stato salvato, o nil se non va bene.
struct NewNameField: View {
    let prompt: String
    let add: (String) -> String?
    let close: () -> Void

    @State private var text = ""
    @State private var added: String?
    @FocusState private var focused: Bool

    init(prompt: String, add: @escaping (String) -> String?, close: @escaping () -> Void) {
        self.prompt = prompt
        self.add = add
        self.close = close
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(prompt, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand(perform: close)
                Button(L("Aggiungi"), action: submit)
                    .disabled(trimmed.isEmpty)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("Chiudi"))
                .accessibilityLabel(L("Chiudi"))
            }
            if let added {
                Label(L("Aggiunto: %@", added), systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func submit() {
        guard !trimmed.isEmpty else { close(); return }
        if let name = add(trimmed) {
            added = name
            text = ""
        } else {
            NSSound.beep()
        }
        focused = true
    }
}

/// Il popover del + nella barra laterale: progetto o persona.
struct AddEntityPopover: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var role: SetupCandidate.Role = .project

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L("Tipo"), selection: $role) {
                Text(L("Progetto")).tag(SetupCandidate.Role.project)
                Text(L("Persona o cliente")).tag(SetupCandidate.Role.person)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            NewNameField(prompt: role == .project ? L("Sigla, es. SITO") : L("Nome, es. Marta")) { input in
                if role == .project {
                    guard let sigla = model.addProject(input) else { return nil }
                    model.sidebar = .project(sigla)
                    return sigla
                }
                return model.addPerson(input)
            } close: {
                close()
            }
            Text(role == .project ? L("Dopo la sigla puoi scrivere il nome lungo: SITO Nuovo sito.")
                                  : L("Si evidenzia in ogni nota, anche dove l'app da sola non l'avrebbe riconosciuto."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 320)
    }
}
