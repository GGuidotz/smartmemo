// Apple Intelligence per le riunioni: "Concludi riunione" chiede al modello che sta sul Mac (FoundationModels,
// macOS 26) un riassunto esecutivo e le to-do minimal con il responsabile. Niente rete, niente dati che escono.
// Il modello legge poche migliaia di parole: le riunioni lunghe si accorciano prima di chiedere.
// Senza Apple Intelligence (spenta, Mac non adatto, SDK senza FoundationModels) c'è il riassunto fatto con le regole.
// HIG, Generative AI: si dice dove c'è l'AI, si può rigenerare o togliere, e c'è sempre un'alternativa.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
enum Intelligence {
    /// nil se Apple Intelligence si può usare adesso, altrimenti perché no.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return L("Questo Mac non supporta Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return L("Apple Intelligence è spenta: Impostazioni di Sistema › Apple Intelligence e Siri.")
            case .unavailable(.modelNotReady):
                return L("Il modello di Apple Intelligence si sta ancora scaricando.")
            default:
                return L("Apple Intelligence non è disponibile adesso.")
            }
        }
        #endif
        return L("Serve macOS 26 con Apple Intelligence.")
    }

    static var isAvailable: Bool { unavailableReason == nil }

    /// Il riassunto di una riunione: con Apple Intelligence se si può e se è accesa nelle impostazioni, altrimenti con
    /// le regole. Non fallisce mai: in caso di errore torna il riassunto con le regole e il motivo.
    static func summarize(_ text: String, knowledge: Knowledge, useAI: Bool) async -> (MeetingSummary, String?) {
        let fallback = MeetingSummary.fallback(for: text, knowledge: knowledge)
        guard useAI, isAvailable else { return (fallback, nil) }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            var body = MeetingSummary.body(of: text)
            if body.count > 6000 { body = String(body.prefix(6000)) }
            // Le chiavi SINTESI, PROSSIMO, SCADENZE restano fisse in ogni lingua: le legge MeetingSummary.parse.
            let prompt = """
                Meeting notes:
                \"\"\"
                \(body)
                \"\"\"

                Write the executive summary in exactly this format, in the same language as the notes, with no other lines:
                SINTESI: two or three sentences on decisions and key points
                PROSSIMO: date and time of the next meeting, or none
                SCADENZE: deadlines separated by semicolons, or none
                - short action that starts with a verb | person responsible, or none
                (one "- " line per action, at most 8)
                """
            do {
                let session = LanguageModelSession(instructions: """
                    You turn quick meeting notes into an executive summary. Use only facts written in the notes: \
                    never invent people, dates, numbers or tasks. Keep the names exactly as written. Each action is \
                    short (under 15 words) and starts with a verb. Write in the language of the notes. Follow the \
                    output format exactly, with no introduction and no closing remarks.
                    """)
                let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.2))
                let summary = MeetingSummary.parse(response.content)
                diag(.intelligence, "meeting summarized: \(summary.actions.count) actions")
                if summary.synthesis.isEmpty && summary.actions.isEmpty {
                    return (fallback, L("Apple Intelligence non ha dato un riassunto leggibile: uso quello con le regole."))
                }
                return (summary, nil)
            } catch {
                diag(.intelligence, "summary failed: \(error)")
                return (fallback, L("Apple Intelligence non ha risposto (%@): uso il riassunto con le regole.", error.localizedDescription))
            }
        }
        #endif
        return (fallback, nil)
    }

    /// La punteggiatura di righe di appunti (spesso dettati): Apple Intelligence aggiunge virgole, punti e maiuscole senza
    /// toccare le parole. Torna una riga per ogni riga data; quelle che il modello salta restano com'erano. Le righe
    /// che cambiano parole le scarta chi chiama (`PunctuationGuard`). Solo sul Mac, niente rete.
    static func punctuate(_ bodies: [String]) async throws -> [String] {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            var result = bodies
            // A pezzi di circa 2500 caratteri: il modello legge poche migliaia di parole.
            var chunk: [Int] = []
            var size = 0
            var chunks: [[Int]] = []
            for (i, body) in bodies.enumerated() {
                if size + body.count > 2500, !chunk.isEmpty {
                    chunks.append(chunk)
                    chunk = []
                    size = 0
                }
                chunk.append(i)
                size += body.count
            }
            if !chunk.isEmpty { chunks.append(chunk) }

            let session = LanguageModelSession(instructions: """
                You add punctuation and capital letters to quick notes, often dictated. Never add, remove, reorder or \
                translate words. Never merge or split lines. Keep names, numbers, dates, hashtags and codes exactly as \
                written. Write in the language of the notes. Return every input line, keeping its number and the "|" \
                separator, with no other text.
                """)
            let line = try NSRegularExpression(pattern: #"^\s*(\d+)\s*\|\s?(.*)$"#)
            for indexes in chunks {
                let prompt = indexes.enumerated().map { "\($0.offset + 1)|\(bodies[$0.element])" }.joined(separator: "\n")
                let response = try await session.respond(to: "Notes:\n" + prompt, options: GenerationOptions(temperature: 0))
                for row in response.content.components(separatedBy: .newlines) {
                    let ns = row as NSString
                    guard let m = line.firstMatch(in: row, range: NSRange(location: 0, length: ns.length)),
                          let n = Int(ns.substring(with: m.range(at: 1))), n >= 1, n <= indexes.count else { continue }
                    result[indexes[n - 1]] = ns.substring(with: m.range(at: 2))
                }
            }
            diag(.intelligence, "punctuation fixed: \(bodies.count) lines")
            return result
        }
        #endif
        return bodies
    }
}
