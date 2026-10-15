// L'editor: un NSTextView di testo semplice (il file resta Markdown puro) che a ogni pausa di scrittura rilegge il
// testo, riconosce progetti, persone, date e URGENTE e li segna con attributi e forme disegnate dietro al testo.
//
// L'accensione: quando una parola viene riconosciuta mentre scrivi, una luce la attraversa una volta (0,7 s) e poi
// resta segnata. Con Riduci movimento diventa una breve dissolvenza. Le parole già presenti all'apertura non si
// accendono, e quella che stai ancora scrivendo aspetta lo spazio.
//
// Nelle pagine di to-do: un cerchio a sinistra di ogni to-do (clic o ⌘K per spuntarla), e Invio divide la riga alle
// virgole dove comincia un'altra azione. Nelle riunioni sono to-do le righe con la casella "- [ ] " (la casella si
// nasconde e diventa il cerchio), e il riassunto in cima diventa un riquadro con le sue to-do.
// TextKit 1: serve la posizione esatta di ogni parola per disegnare.

import AppKit

final class NoteTextView: NSTextView {
    weak var model: AppModel?
    var kind: NoteKind = .todo

    private(set) var lines: [ParsedLine] = []
    private(set) var entities: [Entity] = []
    private var seenKeys: Set<String> = []
    private var styledOnce = false
    private var glows: [Glow] = []
    private var glowTimer: Timer?
    /// Le righe del riassunto (senza i commenti che lo aprono e lo chiudono), se la riunione ne ha uno.
    private var summaryContent: NSRange?
    private var summaryByAI = false
    private static let boldRegex = try! NSRegularExpression(pattern: #"(\*\*)(.+?)(\*\*)"#)

    private struct Glow {
        var range: NSRange
        var color: NSColor
        var start: TimeInterval
    }

    static let gutter: CGFloat = 38

    func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        // "---" deve restare tre trattini (è il separatore dei progetti) e le virgolette dritte restano dritte.
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isContinuousSpellCheckingEnabled = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textContainerInset = NSSize(width: Self.gutter, height: 22)
        font = Theme.bodyFont
        textColor = .labelColor
        typingAttributes = Theme.baseAttributes
        setAccessibilityLabel(L("Testo della nota"))
    }

    /// Un documento nuovo: niente accensioni per ciò che c'è già.
    func load(_ text: String, kind: NoteKind, caret: Int? = nil) {
        self.kind = kind
        seenKeys = []
        styledOnce = false
        glows = []
        string = text
        undoManager?.removeAllActions()
        restyle()
        let end = (text as NSString).length
        setSelectedRange(NSRange(location: min(caret ?? end, end), length: 0))
        scrollRangeToVisible(selectedRange())
    }

    // MARK: Riconoscimento e stile

    func restyle() {
        guard let storage = textStorage, let model, !hasMarkedText() else { return }
        let text = storage.string
        let knowledge = model.knowledge
        lines = kind == .todo ? TodoParser.parse(text, knowledge: knowledge) : TodoParser.parseMeeting(text)
        let all = EntityRecognizer.entities(in: text, kind: kind, lines: lines, knowledge: knowledge)

        // Una chiave per ogni risultato (tipo, testo, quale occorrenza), per sapere cosa è appena comparso.
        var counts: [String: Int] = [:]
        var keyed: [(key: String, entity: Entity)] = []
        for e in all {
            let base = "\(e.kind.rawValue):\(e.text.lowercased())"
            let n = counts[base, default: 0]
            counts[base] = n + 1
            keyed.append((key: "\(base)#\(n)", entity: e))
        }
        // La parola che stai scrivendo non si accende ancora: aspetta lo spazio o la punteggiatura. Quelle già accese
        // restano accese anche con il cursore subito dopo.
        let caret = selectedRange()
        if styledOnce, caret.length == 0, window?.firstResponder === self {
            keyed.removeAll { !seenKeys.contains($0.key) && $0.entity.range.upperBound == caret.location }
        }
        let found = keyed.map { $0.entity }

        storage.beginEditing()
        storage.setAttributes(Theme.baseAttributes, range: NSRange(location: 0, length: storage.length))
        var doneRanges: [NSRange] = []
        for line in lines {
            if line.kind == .separator {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: line.range)
            }
            if let mark = line.doneMarkRange {
                let rest = NSRange(location: mark.upperBound, length: line.range.upperBound - mark.upperBound)
                storage.addAttributes(Theme.doneAttributes, range: rest)
                storage.addAttributes(Theme.hiddenAttributes, range: mark)
                doneRanges.append(rest)
            }
            // La casella "- [ ] " resta nel file ma si vede solo il cerchio a sinistra.
            if let box = line.boxRange, line.kind == .task {
                storage.addAttributes(Theme.hiddenAttributes, range: box)
                if line.boxDone {
                    let rest = NSRange(location: box.upperBound, length: line.range.upperBound - box.upperBound)
                    storage.addAttributes(Theme.doneAttributes, range: rest)
                    doneRanges.append(rest)
                }
            }
        }
        styleSummary(storage)
        for e in found {
            let done = doneRanges.contains { NSIntersectionRange($0, e.range).length > 0 }
            storage.addAttributes(Theme.attributes(for: e, done: done), range: e.range)
        }
        storage.endEditing()
        typingAttributes = Theme.baseAttributes

        // Accensione per ciò che è appena comparso.
        if styledOnce {
            for k in keyed where !seenKeys.contains(k.key) {
                addGlow(k.entity.range, color: Theme.color(for: k.entity, knowledge: knowledge))
            }
        }
        seenKeys = Set(keyed.map { $0.key })
        styledOnce = true
        entities = found
        needsDisplay = true
    }

    /// Il riassunto di una riunione: i commenti che lo aprono e lo chiudono spariscono, i titoletti tra ** vanno in
    /// grassetto senza asterischi, e sopra la prima riga resta lo spazio per l'etichetta del riquadro.
    private func styleSummary(_ storage: NSTextStorage) {
        summaryContent = nil
        let text = storage.string
        guard kind == .meeting, let block = MeetingSummary.blockRange(in: text) else { return }
        let ns = text as NSString
        let first = ns.lineRange(for: NSRange(location: block.location, length: 0))
        let closeAt = ns.range(of: MeetingSummary.close, options: .backwards, range: block).location
        guard closeAt != NSNotFound else { return }
        let last = ns.lineRange(for: NSRange(location: closeAt, length: 0))
        storage.addAttributes(Theme.hiddenLineAttributes, range: first)
        storage.addAttributes(Theme.hiddenLineAttributes, range: last)
        guard last.location > first.upperBound else { return }
        let content = NSRange(location: first.upperBound, length: last.location - first.upperBound)
        for m in Self.boldRegex.matches(in: text, range: content) {
            storage.addAttributes(Theme.hiddenAttributes, range: m.range(at: 1))
            storage.addAttributes(Theme.hiddenAttributes, range: m.range(at: 3))
            storage.addAttribute(.font, value: Theme.strongFont, range: m.range(at: 2))
        }
        storage.addAttribute(.paragraphStyle, value: Theme.summaryFirstParagraph,
                             range: ns.lineRange(for: NSRange(location: content.location, length: 0)))
        let lastContent = ns.lineRange(for: NSRange(location: max(content.location, content.upperBound - 1), length: 0))
        if lastContent.location != content.location {
            storage.addAttribute(.paragraphStyle, value: Theme.summaryLastParagraph, range: lastContent)
        }
        summaryContent = content
        summaryByAI = MeetingSummary.isByAI(text)
    }

    /// Mette il testo intero in una volta sola (il riassunto), annullabile con ⌘Z.
    func replaceAll(with text: String, actionName: String) {
        let range = NSRange(location: 0, length: (string as NSString).length)
        guard text != string, shouldChangeText(in: range, replacementString: text) else { return }
        breakUndoCoalescing()
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        undoManager?.setActionName(actionName)
        restyle()
    }

    /// L'accensione del riassunto appena scritto.
    func glowSummary() {
        guard let summaryContent else { return }
        addGlow(summaryContent, color: summaryByAI ? .systemPurple : .controlAccentColor)
        scrollRangeToVisible(NSRange(location: summaryContent.location, length: 0))
    }

    // MARK: Disegno

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let model else { return }
        if (textStorage?.length ?? 0) == 0 { drawPlaceholder() }
        if let summaryContent { drawSummaryBox(summaryContent, dirty: rect) }
        for e in entities where e.kind == .project || e.kind == .urgent {
            let r = tokenRect(e.range).insetBy(dx: -4, dy: -1)
            guard r.intersects(rect), r.width > 0 else { continue }
            let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
            if e.kind == .urgent {
                Theme.urgent.setFill()
                path.fill()
            } else {
                let c = Theme.projectColor(e.text, knowledge: model.knowledge)
                c.withAlphaComponent(0.16).setFill()
                path.fill()
                c.withAlphaComponent(0.55).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
        for line in lines where line.kind == .task {
            let box = checkRect(line)
            if box.intersects(rect) { drawCheck(in: box, done: line.done, urgent: line.urgent) }
        }
        drawGlows()
    }

    private func drawPlaceholder() {
        let text: String
        switch kind {
        case .todo:
            text = L("Scrivi le to-do per progetto, come sempre:") + "\n\nSITO: " + L("chiama Marta, manda il preventivo a Nexa")
                + "\n-----\nLANCIO: URGENTE! " + L("rivedi le slide con i commenti") + "\n\n"
                + L("Progetti, persone e date si evidenziano da soli. Invio divide la riga alle virgole.")
        case .meeting:
            text = L("Scrivi gli appunti della riunione. Persone, date e #progetti si evidenziano da soli.")
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.bodyFont, .foregroundColor: NSColor.placeholderTextColor,
                                                    .paragraphStyle: Theme.paragraph]
        let origin = textContainerOrigin
        let width = bounds.width - origin.x * 2
        (text as NSString).draw(with: NSRect(x: origin.x + 5, y: origin.y, width: max(width, 100), height: 400),
                                options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
    }

    /// Il riquadro del riassunto, largo quanto la nota, con l'etichetta in alto. Fatto da Apple Intelligence: bordo
    /// con la sfumatura dei suoi colori; fatto con le regole: bordo del colore di sistema.
    private func drawSummaryBox(_ content: NSRange, dirty: NSRect) {
        guard let lm = layoutManager, let storage = textStorage, content.upperBound <= storage.length, content.length > 0 else { return }
        let origin = textContainerOrigin
        let firstGlyph = lm.glyphIndexForCharacter(at: content.location)
        let lastGlyph = lm.glyphIndexForCharacter(at: max(content.location, content.upperBound - 1))
        let top = lm.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil).minY + origin.y
        let bottom = lm.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil).maxY + origin.y
        let box = NSRect(x: 6, y: top, width: bounds.width - 12, height: bottom - top).insetBy(dx: 0, dy: -2)
        guard box.intersects(dirty), box.width > 40 else { return }
        let shape = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12)
        (summaryByAI ? NSColor.systemPurple : NSColor.controlAccentColor).withAlphaComponent(0.06).setFill()
        shape.fill()
        if summaryByAI, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.addPath(shape.cgPath)
            ctx.setLineWidth(1.5)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            let colors: [NSColor] = [.systemBlue, .systemPurple, .systemPink, .systemOrange]
            NSGradient(colors: colors.map { $0.withAlphaComponent(0.8) })?.draw(in: box, angle: 0)
            ctx.restoreGState()
        } else {
            NSColor.controlAccentColor.withAlphaComponent(0.3).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        let label = summaryByAI ? L("Riassunto · Apple Intelligence") : L("Riassunto")
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                                                    .foregroundColor: NSColor.secondaryLabelColor]
        var x = origin.x + 5
        if let symbol = NSImage(systemSymbolName: summaryByAI ? "sparkles" : "list.bullet.rectangle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold).applying(.init(paletteColors: [summaryByAI ? .systemPurple : .secondaryLabelColor]))) {
            symbol.draw(in: NSRect(x: x, y: box.minY + 9, width: symbol.size.width, height: symbol.size.height))
            x += symbol.size.width + 5
        }
        (label as NSString).draw(at: NSPoint(x: x, y: box.minY + 8), withAttributes: attrs)
    }

    /// Il rettangolo di un intervallo di testo, nelle coordinate della vista.
    private func tokenRect(_ range: NSRange) -> NSRect {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage,
              range.upperBound <= storage.length else { return .zero }
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let origin = textContainerOrigin
        return lm.boundingRect(forGlyphRange: glyphs, in: tc).offsetBy(dx: origin.x, dy: origin.y)
    }

    /// La riga intera (prima riga visiva) di una to-do.
    private func lineFragmentRect(_ line: ParsedLine) -> NSRect {
        guard let lm = layoutManager, let storage = textStorage, line.range.location < storage.length else { return .zero }
        let glyph = lm.glyphIndexForCharacter(at: line.range.location)
        let origin = textContainerOrigin
        return lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).offsetBy(dx: origin.x, dy: origin.y)
    }

    private func checkRect(_ line: ParsedLine) -> NSRect {
        let fragment = lineFragmentRect(line)
        guard fragment.height > 0, let lm = layoutManager else { return .zero }
        let size: CGFloat = 15
        let lineHeight = lm.defaultLineHeight(for: Theme.bodyFont)
        return NSRect(x: textContainerOrigin.x - size - 9, y: fragment.minY + (lineHeight - size) / 2, width: size, height: size)
    }

    private func drawCheck(in box: NSRect, done: Bool, urgent: Bool) {
        let circle = NSBezierPath(ovalIn: box.insetBy(dx: 0.75, dy: 0.75))
        if done {
            NSColor.controlAccentColor.setFill()
            circle.fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + box.width * 0.28, y: box.minY + box.height * 0.52))
            tick.line(to: NSPoint(x: box.minX + box.width * 0.44, y: box.minY + box.height * 0.68))
            tick.line(to: NSPoint(x: box.minX + box.width * 0.73, y: box.minY + box.height * 0.34))
            tick.lineWidth = 1.7
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.white.setStroke()
            tick.stroke()
        } else {
            (urgent ? Theme.urgent : NSColor.secondaryLabelColor).setStroke()
            circle.lineWidth = urgent ? 1.6 : 1.2
            circle.stroke()
        }
    }

    // MARK: Accensione

    private func addGlow(_ range: NSRange, color: NSColor) {
        glows.append(Glow(range: range, color: color, start: ProcessInfo.processInfo.systemUptime))
        guard glowTimer == nil else { return }
        glowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.setNeedsDisplay(self.visibleRect)
                if self.glows.isEmpty {
                    timer.invalidate()
                    self.glowTimer = nil
                }
            }
        }
    }

    private func drawGlows() {
        guard !glows.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduce ? 0.2 : 0.7
        glows.removeAll { now - $0.start > duration }
        for g in glows {
            let r = tokenRect(g.range).insetBy(dx: -5, dy: -2)
            guard r.width > 0 else { continue }
            let t = CGFloat((now - g.start) / duration)
            let radius = min(r.height / 2, 12)
            let shape = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
            NSGraphicsContext.saveGraphicsState()
            if reduce {
                g.color.withAlphaComponent(0.3 * (1 - t)).setFill()
                shape.fill()
            } else {
                shape.addClip()
                g.color.withAlphaComponent(0.25 * (1 - t)).setFill()
                shape.fill()
                let eased = 1 - pow(1 - t, 3)
                let band = max(r.width * 0.5, 28)
                let x = r.minX - band + (r.width + band) * eased
                let light = NSGradient(colors: [g.color.withAlphaComponent(0), g.color.withAlphaComponent(0.45),
                                                NSColor.white.withAlphaComponent(0.55), g.color.withAlphaComponent(0)])
                light?.draw(in: NSRect(x: x, y: r.minY, width: band, height: r.height), angle: 0)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: Spunte

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.x < textContainerOrigin.x - 2,
           let line = lines.first(where: { $0.kind == .task && checkRect($0).insetBy(dx: -8, dy: -4).contains(p) }) {
            toggle(line)
            return
        }
        super.mouseDown(with: event)
    }

    /// ⌘K: spunta la to-do dove sta il cursore.
    @objc func toggleDone(_ sender: Any?) {
        let caret = selectedRange().location
        guard let line = lines.first(where: {
            $0.kind == .task && caret >= $0.range.location && caret <= $0.range.upperBound
        }) else { NSSound.beep(); return }
        toggle(line)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(toggleDone(_:)) { return kind == .todo || lines.contains { $0.kind == .task } }
        return super.validateUserInterfaceItem(item)
    }

    private func toggle(_ line: ParsedLine) {
        let range: NSRange
        let replacement: String
        if let box = line.boxRange {
            // Casella Markdown: cambia solo il carattere tra le parentesi.
            let open = (string as NSString).range(of: "[", options: [], range: box)
            guard open.location != NSNotFound else { return }
            range = NSRange(location: open.location + 1, length: 1)
            replacement = line.boxDone ? " " : "x"
        } else if let mark = line.doneMarkRange {
            range = mark
            replacement = ""
        } else {
            range = NSRange(location: line.range.location, length: 0)
            replacement = TodoParser.doneMark
        }
        breakUndoCoalescing()
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        undoManager?.setActionName(line.done ? L("Segna da fare") : L("Segna come fatta"))
        if !line.done {
            let length = line.range.length + (line.boxRange == nil ? (replacement as NSString).length : 0)
            addGlow(NSRange(location: line.range.location, length: length), color: .controlAccentColor)
        }
    }

    // MARK: Invio divide alle virgole

    override func insertNewline(_ sender: Any?) {
        if kind == .todo { splitLineAtCaret() }
        super.insertNewline(sender)
    }

    private func splitLineAtCaret() {
        let caret = selectedRange()
        guard caret.length == 0, let storage = textStorage else { return }
        let ns = storage.string as NSString
        var start = 0, contentsEnd = 0
        ns.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: caret.location, length: 0))
        guard caret.location == contentsEnd, contentsEnd > start else { return }
        let range = NSRange(location: start, length: contentsEnd - start)
        guard let segments = TodoParser.splitSegments(ns.substring(with: range)) else { return }
        let replacement = segments.joined(separator: "\n")
        breakUndoCoalescing()
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        storage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        undoManager?.setActionName(L("Dividi to-do"))
        let newLength = (replacement as NSString).length
        setSelectedRange(NSRange(location: start + newLength, length: 0))
        // Le righe nuove si accendono insieme.
        var location = start
        for s in segments {
            let length = (s as NSString).length
            addGlow(NSRange(location: location, length: length), color: .controlAccentColor)
            location += length + 1
        }
    }

    // MARK: Correzioni

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let p = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: p)
        var items: [NSMenuItem] = []
        if let e = entities.first(where: { index >= $0.range.location && index <= $0.range.upperBound }) {
            switch e.kind {
            case .person:
                items.append(correctionItem(L("“%@” non è una persona", e.name), .notPerson(e.name)))
            case .project:
                items.append(correctionItem(L("“%@” non è un progetto", e.name), .notProject(e.name)))
            default: break
            }
        } else if let word = candidateWord(at: index) {
            items.append(correctionItem(L("“%@” è una persona", word), .person(word)))
            items.append(correctionItem(L("“%@” è un progetto", word), .project(word)))
        }
        guard !items.isEmpty else { return menu }
        menu.insertItem(.separator(), at: 0)
        for item in items.reversed() { menu.insertItem(item, at: 0) }
        return menu
    }

    /// La selezione (se il clic è dentro) o la parola sotto il puntatore, se comincia con una maiuscola.
    private func candidateWord(at index: Int) -> String? {
        let ns = string as NSString
        var range = selectedRange()
        if range.length == 0 || index < range.location || index > range.upperBound {
            range = selectionRange(forProposedRange: NSRange(location: index, length: 0), granularity: .selectByWord)
        }
        guard range.length > 0, range.upperBound <= ns.length else { return nil }
        let word = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard let first = word.first, first.isUppercase, word.count <= 40 else { return nil }
        return word
    }

    private func correctionItem(_ title: String, _ correction: Correction) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(applyCorrection(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = CorrectionBox(correction)
        return item
    }

    @objc private func applyCorrection(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? CorrectionBox else { return }
        model?.correct(box.correction)
    }
}

private final class CorrectionBox: NSObject {
    let correction: Correction
    init(_ c: Correction) { correction = c }
}
