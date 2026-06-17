import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { mkdtempSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { scanSkills } from '../backend/codex/skillScanner';

function tempRoot(): string {
  return mkdtempSync(join(tmpdir(), 'abar-skills-'));
}

describe('scanSkills', () => {
  it('returns project and user skills without failing on missing directories', async () => {
    const root = tempRoot();
    const projectPath = join(root, 'project');
    const userHomePath = join(root, 'home');
    await mkdir(join(projectPath, '.agents', 'skills', 'repo-skill'), { recursive: true });
    await mkdir(join(userHomePath, '.agents', 'skills', 'user-skill'), { recursive: true });
    await writeFile(
      join(projectPath, '.agents', 'skills', 'repo-skill', 'SKILL.md'),
      '---\nname: repo-skill\ndescription: Repo level helper.\n---\n\nInstructions\n'
    );
    await writeFile(
      join(userHomePath, '.agents', 'skills', 'user-skill', 'SKILL.md'),
      '# User Skill\n\nUser helper description.\n'
    );

    const result = await scanSkills({ projectPath, userHomePath });

    expect(result.errors).toEqual([]);
    expect(result.skills.map((skill) => [skill.name, skill.source])).toEqual([
      ['repo-skill', 'project'],
      ['User Skill', 'user']
    ]);
    expect(result.skills[0]?.description).toBe('Repo level helper.');
  });

  it('keeps malformed and unreadable skill entries visible', async () => {
    const root = tempRoot();
    const projectPath = join(root, 'project');
    const userHomePath = join(root, 'home');
    const skillPath = join(projectPath, '.agents', 'skills', 'broken-skill');
    await mkdir(skillPath, { recursive: true });
    await writeFile(join(skillPath, 'SKILL.md'), '---\nname:\n---\n');

    const result = await scanSkills({ projectPath, userHomePath });

    expect(result.skills).toHaveLength(1);
    expect(result.skills[0]?.name).toBe('Unknown name');
    expect(result.skills[0]?.description).toBe('Missing description');
    expect(result.skills[0]?.hasSkillMd).toBe(true);
  });
});
