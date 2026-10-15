// L'editor di una scheda, dentro SwiftUI. Salva da solo mezzo secondo dopo l'ultima modifica, e subito quando chiudi
// la scheda o l'app. Rilegge il file se è cambiato da fuori (una spunta data dalla vista Oggi).

import AppKit
import SwiftUI

struct EditorView: NSViewRepresentable {
    @ObservedObject var model: AppModel
    let card: CardState

    func makeCoordinator() -> Coordinator { Coordinator(model: model, card: card) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.borderType = .noBorder

        let text = NoteTextView(usingTextLayoutManager: false)
        text.configure()
        text.model = model
        text.delegate = context.coordinator
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text

        context.coordinator.textView = text
        card.textView = text
        context.coordinator.open(card.document)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update()
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.flush()
        coordinator.close()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        let card: CardState
        weak var textView: NoteTextView?
        private var document: OpenDocument?
        private var lastSaved = ""
        private var saveWork: DispatchWorkItem?
        private var styleWork: DispatchWorkItem?
        private var seenReload = 0
        private var seenKnowledge = 0

        init(model: AppModel, card: CardState) {
            self.model = model
            self.card = card
        }

        func open(_ doc: OpenDocument) {
            document = doc
            let text = model.store.read(doc.url)
            let initial = text.isEmpty ? doc.template : text
            lastSaved = initial   // il modello di una riunione si salva solo se ci scrivi
            textView?.load(initial, kind: doc.kind, caret: text.isEmpty ? doc.caret : nil)
            seenReload = model.reloadToken
            seenKnowledge = model.knowledgeVersion
            model.registerEditor(doc.url) { [weak self] in self?.flush() }
            DispatchQueue.main.async { [weak self] in
                guard let self, let tv = self.textView else { return }
                self.card.textChanged(tv.string)
                tv.window?.makeFirstResponder(tv)
            }
        }

        func close() {
            if let url = document?.url { model.unregisterEditor(url) }
        }

        func update() {
            guard let doc = document else { return }
            if model.reloadToken != seenReload {
                seenReload = model.reloadToken
                if model.reloadedURLs.contains(doc.url) { reloadFromDisk() }
            }
            if model.knowledgeVersion != seenKnowledge {
                seenKnowledge = model.knowledgeVersion
                textView?.restyle()
            }
        }

        private func reloadFromDisk() {
            guard let tv = textView, let doc = document else { return }
            let text = model.store.read(doc.url)
            guard !text.isEmpty, text != tv.string else { return }
            let selection = tv.selectedRange()
            lastSaved = text
            tv.load(text, kind: doc.kind)
            let length = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            card.textChanged(text)
        }

        func textDidChange(_ notification: Notification) {
            scheduleStyle()
            saveWork?.cancel()
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.save() } }
            saveWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            scheduleStyle()
        }

        private func scheduleStyle() {
            styleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let tv = self.textView else { return }
                    tv.restyle()
                    self.card.textChanged(tv.string)
                }
            }
            styleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }

        func flush() {
            saveWork?.cancel()
            save()
        }

        private func save() {
            guard let tv = textView, let doc = document else { return }
            let text = tv.string
            guard text != lastSaved else { return }
            lastSaved = text
            model.saved(text: text, to: doc.url, kind: doc.kind)
        }
    }
}
