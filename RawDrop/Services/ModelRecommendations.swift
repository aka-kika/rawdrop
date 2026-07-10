import Foundation

/// Ranks installed Ollama models for RawDrop's compile/summarize job.
/// Only returns models that are actually available — never invents names.
enum ModelRecommendations {
    struct Pick: Identifiable, Hashable {
        var id: String { model.name }
        let model: LocalModel
        let reason: String
        let score: Int
    }

    /// Patterns that tend to work well for wiki synthesis (general chat / instruct).
    /// Higher score = stronger preference. Matched against lowercase model name.
    private static let preferred: [(pattern: String, score: Int, reason: String)] = [
        ("ministral", 100, "Strong default for local summarization"),
        ("mistral", 90, "Good general writing / synthesis"),
        ("gemma", 88, "Solid open model for structured notes"),
        ("llama", 85, "Reliable general chat model"),
        ("qwen", 84, "Strong reasoning and summarization"),
        ("phi", 80, "Fast, capable small model"),
        ("glm", 78, "Good cloud / hybrid chat model"),
        ("command-r", 76, "Built for RAG-style synthesis"),
        ("deepseek", 74, "Strong reasoning; may be slower"),
        ("ornith", 72, "Available general model"),
        ("laguna", 70, "Large local model — high quality, slower"),
        ("oh-llama", 66, "Llama-family chat model"),
    ]

    /// Demote pure code / embedding / vision-only style names for this job.
    private static let demote: [(pattern: String, penalty: Int)] = [
        ("embed", 80),
        ("code", 40),
        ("coder", 40),
        ("nomic", 60),
        ("bge", 60),
        ("vision", 25),
        ("llava", 20),
    ]

    /// Recommended subset of `available`, sorted best-first.
    static func recommended(from available: [LocalModel], limit: Int = 6) -> [Pick] {
        guard !available.isEmpty else { return [] }

        var picks: [Pick] = []
        for model in available {
            let name = model.name.lowercased()
            var score = 10 // baseline: every installed model can be used
            var reason = "Installed and available"

            for pref in preferred {
                if name.contains(pref.pattern) {
                    if pref.score > score {
                        score = pref.score
                        reason = pref.reason
                    }
                }
            }
            for dem in demote {
                if name.contains(dem.pattern) {
                    score -= dem.penalty
                    if name.contains("code") || name.contains("coder") {
                        reason = "Available, but code-oriented (less ideal for wiki prose)"
                    } else if name.contains("embed") {
                        reason = "Embedding model — not for compile chat"
                    }
                }
            }

            // Slight boost for explicit chat/instruct tags
            if name.contains("instruct") || name.contains("chat") {
                score += 8
            }
            // Prefer tagged :latest lightly for simpler ops
            if name.hasSuffix(":latest") {
                score += 3
            }

            picks.append(Pick(model: model, reason: reason, score: score))
        }

        // Drop very low (e.g. pure embed after heavy demote)
        picks = picks.filter { $0.score > 0 }
        picks.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.model.name.localizedCaseInsensitiveCompare(rhs.model.name) == .orderedAscending
        }

        // De-dupe by base name (keep highest score)
        var seenBases = Set<String>()
        var unique: [Pick] = []
        for pick in picks {
            let base = pick.model.name.split(separator: ":").first.map(String.init) ?? pick.model.name
            if seenBases.contains(base) { continue }
            seenBases.insert(base)
            unique.append(pick)
            if unique.count >= limit { break }
        }
        return unique
    }

    /// Best single recommendation, if any.
    static func topPick(from available: [LocalModel]) -> Pick? {
        recommended(from: available, limit: 1).first
    }
}
