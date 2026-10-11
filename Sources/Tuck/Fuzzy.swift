enum Fuzzy {
    /// Scores `query` as an in-order subsequence of `text`; nil when it does not match. Higher is better.
    static func score(_ query: String, in text: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        let haystack = Array(text.lowercased())
        guard !needle.isEmpty else { return 0 }

        var score = 0
        var matched = 0
        var previous = -2
        for (index, character) in haystack.enumerated() where matched < needle.count && character == needle[matched] {
            score += 1
            if index == previous + 1 { score += 5 }
            if index == 0 || !(haystack[index - 1].isLetter || haystack[index - 1].isNumber) { score += 8 }
            if matched == 0 { score -= min(index, 10) }
            previous = index
            matched += 1
        }
        return matched == needle.count ? score : nil
    }
}
