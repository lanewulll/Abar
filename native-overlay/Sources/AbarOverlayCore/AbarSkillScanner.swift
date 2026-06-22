import CryptoKit
import Foundation

public struct AbarSkillScanResult: Equatable {
    public var skills: [AbarStoredSkill]
    public var errors: [String]
    public var scannedAt: String
}

public enum AbarSkillScanner {
    public static func scan(projectPath: String?, homePath: String = NSHomeDirectory()) -> AbarSkillScanResult {
        var skills: [AbarStoredSkill] = []
        var errors: [String] = []
        for root in scanRoots(projectPath: projectPath, homePath: homePath) {
            let result = scanRoot(root)
            skills.append(contentsOf: result.skills)
            errors.append(contentsOf: result.errors)
        }

        skills.sort { left, right in
            let sourceDelta = sourceOrder(left.source) - sourceOrder(right.source)
            return sourceDelta == 0 ? left.name.localizedCompare(right.name) == .orderedAscending : sourceDelta < 0
        }

        return AbarSkillScanResult(
            skills: skills,
            errors: errors,
            scannedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    private static func scanRoots(projectPath: String?, homePath: String) -> [(directory: String, source: String)] {
        var roots: [(String, String)] = []
        if let projectPath, !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            roots.append(((projectPath as NSString).appendingPathComponent(".agents/skills"), "project"))
        }
        roots.append(((homePath as NSString).appendingPathComponent(".agents/skills"), "user"))
        roots.append(((homePath as NSString).appendingPathComponent(".codex/skills"), "user"))
        roots.append(((homePath as NSString).appendingPathComponent(".codex/skills/.system"), "system"))
        roots.append(("/etc/codex/skills", "system"))

        var seen = Set<String>()
        return roots.filter { root in
            if seen.contains(root.0) { return false }
            seen.insert(root.0)
            return true
        }
    }

    private static func scanRoot(_ root: (directory: String, source: String)) -> (skills: [AbarStoredSkill], errors: [String]) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: root.directory) else {
            return fileManager.fileExists(atPath: root.directory)
                ? ([], ["Unable to read \(root.directory)"])
                : ([], [])
        }

        var skills: [AbarStoredSkill] = []
        var errors: [String] = []
        for entry in entries {
            let skillPath = (root.directory as NSString).appendingPathComponent(entry)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: skillPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            let skillMDPath = (skillPath as NSString).appendingPathComponent("SKILL.md")
            guard fileManager.fileExists(atPath: skillMDPath) else {
                continue
            }

            do {
                let attributes = try fileManager.attributesOfItem(atPath: skillMDPath)
                let modifiedAt = (attributes[.modificationDate] as? Date).map {
                    ISO8601DateFormatter().string(from: $0)
                }
                let text = try String(contentsOfFile: skillMDPath, encoding: .utf8)
                let parsed = parseSkillMarkdown(text)
                skills.append(
                    AbarStoredSkill(
                        id: stableSkillID(skillMDPath: skillMDPath, source: root.source, name: parsed.name),
                        name: parsed.name,
                        description: parsed.description,
                        path: skillPath,
                        source: root.source,
                        skillMDPath: skillMDPath,
                        lastModifiedAt: modifiedAt
                    )
                )
            } catch {
                errors.append("Unable to scan \(skillPath): \(error)")
                skills.append(
                    AbarStoredSkill(
                        id: stableSkillID(skillMDPath: skillMDPath, source: root.source, name: "Unknown name"),
                        name: "Unknown name",
                        description: "Missing description",
                        path: skillPath,
                        source: root.source,
                        skillMDPath: skillMDPath,
                        lastModifiedAt: nil
                    )
                )
            }
        }
        return (skills, errors)
    }

    private static func parseSkillMarkdown(_ text: String) -> (name: String, description: String) {
        let frontmatter = parseFrontmatter(text)
        let body = stripFrontmatter(text)
        let title = body.components(separatedBy: .newlines)
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") }?
            .replacingOccurrences(of: #"^#\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraph = body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") && $0 != "---" }

        return (
            clean(frontmatter["name"]) ?? title ?? "Unknown name",
            clean(frontmatter["description"]) ?? paragraph ?? "Missing description"
        )
    }

    private static func parseFrontmatter(_ text: String) -> [String: String] {
        guard text.hasPrefix("---"), let close = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else {
            return [:]
        }
        let block = text[text.index(text.startIndex, offsetBy: 3)..<close.lowerBound]
        var values: [String: String] = [:]
        for line in block.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespacesAndNewlines)] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return values
    }

    private static func stripFrontmatter(_ text: String) -> String {
        guard text.hasPrefix("---"), let close = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else {
            return text
        }
        return String(text[close.upperBound...])
    }

    private static func clean(_ value: String?) -> String? {
        let cleaned = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    private static func stableSkillID(skillMDPath: String, source: String, name: String) -> String {
        let data = Data("\(source):\(skillMDPath):\(name)".utf8)
        return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sourceOrder(_ source: String) -> Int {
        switch source {
        case "project": return 0
        case "user": return 1
        case "system": return 2
        default: return 3
        }
    }
}
