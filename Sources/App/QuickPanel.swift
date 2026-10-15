// Il pannello rapido: ⌃⌥Spazio da qualsiasi app, e subito la scelta tra To-do e Riunione, che si aprono in una scheda.
// Tasti T e R; Invio sceglie To-do; Esc o un clic fuori lo chiude. Galleggia sopra tutto, anche a schermo intero.
// È un controllo che galleggia: per questo è di vetro (HIG, Liquid Glass).

import AppKit
import SwiftUI

@MainActor
final class QuickPanelController: NSObject, NSWindowDelegate {
    private var panel: QuickPanel?
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    func toggle() {
        if let panel, panel.isVisible { close() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY + frame.height * 0.12))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func pick(_ kind: NoteKind) {
        close()
        model.quickOpen(kind)
    }

    private func makePanel() -> QuickPanel {
        let view = QuickChooser(pick: { [weak self] kind in self?.pick(kind) },
                                cancel: { [weak self] in self?.close() })
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let panel = QuickPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        panel.setAccessibilityLabel(L("Apertura rapida"))
        return panel
    }

    /// Un clic fuori: il pannello si chiude, come Spotlight.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.close() } }
    }
}

final class QuickPanel: NSPanel {
    var onCancel: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

struct QuickChooser: View {
    let pick: (NoteKind) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Smart(Me)mo")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    choice(.todo, key: "t", hint: "T")
                    choice(.meeting, key: "r", hint: "R")
                }
            }
            // Invio sceglie To-do: un pulsante invisibile, perché ogni pulsante ha una sola scorciatoia.
            Button("") { pick(.todo) }
                .keyboardShortcut(.defaultAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            Button(L("Annulla"), action: cancel)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .fixedSize()
    }

    private func choice(_ kind: NoteKind, key: Character, hint: String) -> some View {
        Button { pick(kind) } label: {
            VStack(spacing: 8) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 30, weight: .medium))
                    .frame(height: 36)
                Text(kind.newTitle)
                    .font(.headline)
                Text(hint)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .rect(cornerRadius: 4))
                    .accessibilityHidden(true)
            }
            .frame(width: 118, height: 118)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
        .help(L("%@ (tasto %@)", kind.newTitle, hint))
    }
}
