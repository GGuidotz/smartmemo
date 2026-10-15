// Colori e caratteri, in un posto solo. Solo colori di sistema: si adattano da soli a chiaro, scuro e Aumenta
// contrasto. Ogni tipo riconosciuto ha una forma sua, oltre al colore (HIG, Accessibilità: mai il colore da solo):
//   progetto   capsula con bordo, sigla in semibold
//   persona    testo indaco con sottolineatura a puntini
//   data       sottolineatura spessa arancione
//   URGENTE    capsula rossa piena, testo bianco
// Rosso, arancione e indaco sono riservati: i progetti prendono gli altri colori.

import AppKit
import SwiftUI

enum Theme {
    static let bodySize: CGFloat = 15
    static var bodyFont: NSFont { .systemFont(ofSize: bodySize) }
    static var strongFont: NSFont { .systemFont(ofSize: bodySize, weight: .semibold) }

    static let person = NSColor.systemIndigo
    static let date = NSColor.systemOrange
    static let urgent = NSColor.systemRed

    private static let projectPalette: [NSColor] = [
        .systemBlue, .systemGreen, .systemPurple, .systemPink, .systemTeal, .systemBrown, .systemMint, .systemCyan,
    ]

    /// Il colore di un progetto: dall'ordine in cui è comparso, così non cambia da un giorno all'altro.
    static func projectColor(_ sigla: String, knowledge: Knowledge) -> NSColor {
        let key = sigla.hasPrefix("#") ? String(sigla.dropFirst()) : sigla
        let index = knowledge.projects.firstIndex(of: key)
            ?? Int(key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF })
        return projectPalette[index % projectPalette.count]
    }

    static func color(for entity: Entity, knowledge: Knowledge) -> NSColor {
        switch entity.kind {
        case .project: projectColor(entity.text, knowledge: knowledge)
        case .person: person
        case .date: date
        case .urgent: urgent
        }
    }

    static var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4
        p.paragraphSpacing = 3
        return p
    }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    /// Il segno "✓ " delle to-do fatte resta nel file ma non si vede: lo sostituisce il cerchio pieno a sinistra.
    static var hiddenAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear]
    }

    /// Una riga intera che non si vede (i commenti che aprono e chiudono il riassunto): alta quasi zero.
    static var hiddenLineAttributes: [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.maximumLineHeight = 1
        p.minimumLineHeight = 1
        return [.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear, .paragraphStyle: p]
    }

    /// La prima riga del riassunto lascia sopra lo spazio per l'etichetta del riquadro.
    static var summaryFirstParagraph: NSParagraphStyle {
        let p = paragraph.mutableCopy() as! NSMutableParagraphStyle
        p.paragraphSpacingBefore = 30
        return p
    }

    /// L'ultima riga del riassunto lascia un po' di spazio prima del bordo.
    static var summaryLastParagraph: NSParagraphStyle {
        let p = paragraph.mutableCopy() as! NSMutableParagraphStyle
        p.paragraphSpacing = 12
        return p
    }

    static var doneAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: NSColor.secondaryLabelColor,
         .strikethroughStyle: NSUnderlineStyle.single.rawValue,
         .strikethroughColor: NSColor.tertiaryLabelColor]
    }

    static func attributes(for entity: Entity, done: Bool) -> [NSAttributedString.Key: Any] {
        switch entity.kind {
        case .project:
            return [.font: strongFont]
        case .urgent:
            return [.font: NSFont.systemFont(ofSize: bodySize - 2, weight: .bold), .foregroundColor: NSColor.white,
                    .baselineOffset: 1]
        case .person:
            var a: [NSAttributedString.Key: Any] = [
                .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                .underlineColor: person,
            ]
            if !done { a[.foregroundColor] = person }
            return a
        case .date:
            return [.underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: date.withAlphaComponent(0.7)]
        }
    }
}

extension Color {
    static func project(_ sigla: String, knowledge: Knowledge) -> Color {
        Color(nsColor: Theme.projectColor(sigla, knowledge: knowledge))
    }
}
