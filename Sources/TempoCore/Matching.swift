import Foundation

/// Whether a window should float, based on its AX subrole.
func isFloating(_ subrole: WindowSubrole) -> Bool {
    switch subrole {
    case .dialog, .floatingWindow: return true
    case .standardWindow, .other: return false
    }
}

/// Whether a matcher matches a window. All set fields must match; an empty matcher never matches.
func windowMatches(_ match: WindowMatch, _ window: WindowInfo) -> Bool {
    if match.bundleId == nil, match.titleRegex == nil { return false }
    if let bundleId = match.bundleId, bundleId != window.bundleId { return false }
    if let pattern = match.titleRegex {
        guard let regex = try? Regex(pattern), window.title.contains(regex) else { return false }
    }
    return true
}

/// Specificity score: a matcher with more set fields is more specific.
func matchSpecificity(_ match: WindowMatch) -> Int {
    (match.bundleId != nil ? 1 : 0) + (match.titleRegex != nil ? 1 : 0)
}

/// The most specific matching assignment, if any. On an equal-specificity tie the first wins.
func bestMatch(for window: WindowInfo, in assignments: [Assignment]) -> Assignment? {
    var best: Assignment?
    var bestSpecificity = -1
    for assignment in assignments where windowMatches(assignment.match, window) {
        let specificity = matchSpecificity(assignment.match)
        if specificity > bestSpecificity {
            best = assignment
            bestSpecificity = specificity
        }
    }
    return best
}
