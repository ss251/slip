/// Spoken summaries follow the content's meaning rather than its visual layout.
enum RowAccessibility {
    static func slip(question: String, crew: String, status: String? = nil, metadata: String) -> String {
        joined([question, crew, status, metadata])
    }

    static func sealStatus(sealed: Bool) -> String {
        sealed ? "Sealed" : "Waiting"
    }

    static func member(
        name: String,
        detail: String? = nil,
        value: String? = nil,
        score: String? = nil,
        sealed: Bool? = nil
    ) -> String {
        // A status-only row must never speak the value hidden behind that status.
        let spokenValue = sealed.map { sealStatus(sealed: $0) } ?? value
        return joined([name, detail, spokenValue, score.map(points)])
    }

    static func points(_ score: String) -> String {
        guard score != "—" else { return "No score" }
        let singular = score == "1" || score == "+1" || score == "-1"
        return "\(score) \(singular ? "point" : "points")"
    }

    static func statistic(value: String, label: String) -> String {
        "\(value) \(label)"
    }

    static func invitationMembers(names: [String], additionalCount: Int) -> String {
        let additional = additionalCount > 0 ? "and \(additionalCount) more" : nil
        return joined(names.map(Optional.some) + [additional])
    }

    static func crewPicker(crew: String, members: [String]) -> String {
        joined([crew, invitationMembers(names: members, additionalCount: 0)])
    }

    private static func joined(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
