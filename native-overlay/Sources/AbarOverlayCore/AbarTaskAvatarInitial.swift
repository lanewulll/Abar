import Foundation

public enum AbarTaskAvatarInitial {
    public static func initial(for projectName: String) -> String {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "C" }
        return String(first).uppercased()
    }
}
