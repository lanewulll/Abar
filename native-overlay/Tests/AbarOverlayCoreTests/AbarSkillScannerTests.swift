import AbarOverlayCore
import XCTest

final class AbarSkillScannerTests: XCTestCase {
    func testScansProjectAndUserSkillsFromSkillMarkdown() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("abar-skill-scan-\(UUID().uuidString)", isDirectory: true)
        let projectSkill = root.appendingPathComponent("project/.agents/skills/project-skill", isDirectory: true)
        let userSkill = root.appendingPathComponent("home/.codex/skills/user-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: projectSkill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userSkill, withIntermediateDirectories: true)
        try """
        ---
        name: Project Skill
        description: Project description
        ---
        # Ignored Title
        """.write(to: projectSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try """
        # User Skill

        User paragraph description.
        """.write(to: userSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let result = AbarSkillScanner.scan(
            projectPath: root.appendingPathComponent("project").path,
            homePath: root.appendingPathComponent("home").path
        )

        XCTAssertEqual(result.skills.map(\.name), ["Project Skill", "User Skill"])
        XCTAssertEqual(result.skills.map(\.source), ["project", "user"])
        XCTAssertEqual(result.skills.last?.description, "User paragraph description.")
        XCTAssertTrue(result.errors.isEmpty)
    }
}
