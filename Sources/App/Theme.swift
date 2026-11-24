// Colori e caratteri, in un posto solo. Solo colori di sistema: si adattano da soli a chiaro, scuro e Aumenta
// contrasto. Ogni tipo riconosciuto ha una forma sua, oltre al colore (HIG, Accessibilità: mai il colore da solo):
//   progetto   capsula con bordo, sigla in semibold
//   persona    testo indaco con sottolineatura a puntini
//   data       sottolineatura spessa arancione
//   URGENTE    capsula rossa piena, testo bianco
// Rosso, arancione e indaco sono riservati: i progetti prendono gli altri colori.
// Le forme, i riempimenti e le molle dell'interfaccia (impostazioni, guida, schede) vengono da Sguardo, il sistema di
// design comune (github.com/GGuidotz/sguardo, submodule in Vendor/Sguardo, compilato insieme all'app da build.sh): qui
// restano i colori di SmartMemo e l'accento. Il vetro solo su ciò che galleggia (pannello rapido, barre delle schede,
// pulsanti in fondo alle schede); il contenuto usa i riempimenti di Sguardo.

import AppKit
import SwiftUI

enum Theme {
    static let bodySize: CGFloat = 15
    static var bodyFont: NSFont { .systemFont(ofSize: bodySize) }
    static var strongFont: NSFont { .systemFont(ofSize: bodySize, weight: .semibold) }

    /// Il colore del marchio, preso dall'icona: l'indaco delle persone, la forma colorata più grande del foglio.
    static let brandHex: UInt32 = 0x5E5CE6

    /// L'accento che si vede adesso, anche per il testo disegnato da AppKit (cerchi, riquadro del riassunto, puntina):
    /// la scelta di Impostazioni › Generale (colore dell'app, di macOS o personalizzato), letta com'è salvata da Sguardo.
    static var accent: NSColor {
        let d = UserDefaults.standard
        let choice = SGAccentChoice(rawValue: d.string(forKey: SGAccentStore.choiceKey) ?? "") ?? .app
        let custom = d.object(forKey: SGAccentStore.customKey) as? Int ?? -1
        switch choice {
        case .app: return NSColor(sgHex: brandHex)
        case .system: return .controlAccentColor
        case .custom: return custom >= 0 ? NSColor(sgHex: UInt32(custom)) : NSColor(sgHex: brandHex)
        }
    }

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

    /// Una voce di elenco: le righe a capo stanno sotto il testo, non sotto il segno.
    static func listParagraph(headIndent: CGFloat) -> NSParagraphStyle {
        let p = paragraph.mutableCopy() as! NSMutableParagraphStyle
        p.firstLineHeadIndent = 0
        p.headIndent = headIndent
        return p
    }

    /// I numeri degli elenchi: cifre tutte larghe uguali, così i numeri si allineano.
    static var numberFont: NSFont { .monospacedDigitSystemFont(ofSize: bodySize, weight: .regular) }

    /// "# " è un titolo grande, "## " uno medio; altrimenti nil.
    static func headingLevel(of line: String) -> Int? {
        if line.hasPrefix("# ") { return 1 }
        if line.hasPrefix("## ") { return 2 }
        return nil
    }

    static func headingFont(_ level: Int) -> NSFont {
        .systemFont(ofSize: level == 1 ? bodySize + 5 : bodySize + 2, weight: .semibold)
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

extension SG.Accent {
    /// L'accento di SmartMemo per Sguardo: l'indaco dell'icona (Theme.brandHex). L'icona è un foglio chiaro senza un
    /// colore proprio; tra le forme colorate (capsula blu, barra indaco, scintilla gialla, sottolineatura arancione)
    /// la più estesa è la barra indaco, ed è anche l'unica su cui il bianco regge (circa 5:1).
    static let smartmemo = SG.Accent(hex: Theme.brandHex)
}

extension View {
    /// Pulsante di vetro (secondario), solo sulle barre che galleggiano. Nel contenuto: `.buttonStyle(.sgSecondary)`.
    func floatingGlassButton() -> some View { buttonStyle(.glass) }

    /// Il pulsante principale di una barra che galleggia: vetro colorato con l'accento. Nel contenuto: `.buttonStyle(.sgPrimary)`.
    func floatingGlassProminentButton() -> some View { buttonStyle(.glassProminent) }

    /// Vetro per i controlli che galleggiano. Mai per il contenuto.
    func glassSurface(in shape: some InsettableShape, interactive: Bool = false) -> some View {
        sgFloatingChrome(in: shape, interactive: interactive)
    }

    /// Campo di testo a capsula per le finestre (Sguardo ha solo quello nero delle isole): riempimento e filo dei menu.
    func capsuleField(height: CGFloat = 28) -> some View {
        textFieldStyle(.plain)
            .font(SG.Font.field)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(Capsule().fill(SG.Fill.pickerPill))
            .overlay(Capsule().strokeBorder(SG.Fill.rowBorder, lineWidth: SG.Stroke.hairline))
    }
}

extension Color {
    static func project(_ sigla: String, knowledge: Knowledge) -> Color {
        Color(nsColor: Theme.projectColor(sigla, knowledge: knowledge))
    }
}
