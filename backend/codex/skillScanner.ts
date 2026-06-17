import { createHash } from 'node:crypto';
import { readdir, readFile, stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import type { SkillInfo, SkillScanResult, SkillSource } from '../types';

export type ScanSkillsInput = {
  projectPath?: string;
  userHomePath: string;
};

type ScanRoot = {
  directory: string;
  source: SkillSource;
};

const SOURCE_ORDER: Record<SkillSource, number> = {
  project: 0,
  user: 1,
  system: 2,
  unknown: 3
};

export async function scanSkills(input: ScanSkillsInput): Promise<SkillScanResult> {
  const roots = buildScanRoots(input);
  const skills: SkillInfo[] = [];
  const errors: string[] = [];

  for (const root of roots) {
    const rootResult = await scanRoot(root);
    skills.push(...rootResult.skills);
    errors.push(...rootResult.errors);
  }

  skills.sort((left, right) => {
    const sourceDelta = SOURCE_ORDER[left.source] - SOURCE_ORDER[right.source];
    return sourceDelta === 0 ? left.name.localeCompare(right.name) : sourceDelta;
  });

  return {
    skills,
    errors,
    scannedAt: new Date().toISOString()
  };
}

function buildScanRoots(input: ScanSkillsInput): ScanRoot[] {
  const roots: ScanRoot[] = [];

  if (input.projectPath?.trim()) {
    roots.push({
      directory: join(resolve(input.projectPath), '.agents', 'skills'),
      source: 'project'
    });
  }

  const home = resolve(input.userHomePath);
  roots.push(
    { directory: join(home, '.agents', 'skills'), source: 'user' },
    { directory: join(home, '.codex', 'skills'), source: 'user' },
    { directory: join(home, '.codex', 'skills', '.system'), source: 'system' },
    { directory: '/etc/codex/skills', source: 'system' }
  );

  const seen = new Set<string>();
  return roots.filter((root) => {
    if (seen.has(root.directory)) {
      return false;
    }
    seen.add(root.directory);
    return true;
  });
}

async function scanRoot(root: ScanRoot): Promise<{ skills: SkillInfo[]; errors: string[] }> {
  let entries;
  try {
    entries = await readdir(root.directory, { withFileTypes: true });
  } catch (error) {
    if (isMissingPath(error)) {
      return { skills: [], errors: [] };
    }
    return {
      skills: [],
      errors: [`Unable to read ${root.directory}: ${errorMessage(error)}`]
    };
  }

  const skills: SkillInfo[] = [];
  const errors: string[] = [];

  for (const entry of entries) {
    if (!entry.isDirectory() && !entry.isSymbolicLink()) {
      continue;
    }

    const skillPath = join(root.directory, entry.name);
    const skillMdPath = join(skillPath, 'SKILL.md');
    try {
      const info = await readSkill(skillPath, skillMdPath, root.source);
      if (info) {
        skills.push(info);
      }
    } catch (error) {
      errors.push(`Unable to scan ${skillPath}: ${errorMessage(error)}`);
      skills.push(createFallbackSkill(skillPath, skillMdPath, root.source, errorMessage(error)));
    }
  }

  return { skills, errors };
}

async function readSkill(
  skillPath: string,
  skillMdPath: string,
  source: SkillSource
): Promise<SkillInfo | null> {
  let fileStat;
  try {
    fileStat = await stat(skillMdPath);
  } catch (error) {
    if (isMissingPath(error)) {
      return null;
    }
    return createFallbackSkill(skillPath, skillMdPath, source, errorMessage(error));
  }

  let text = '';
  let readError: string | undefined;
  try {
    text = await readFile(skillMdPath, 'utf8');
  } catch (error) {
    readError = errorMessage(error);
  }

  const parsed = parseSkillMarkdown(text);
  return {
    id: stableSkillId(skillMdPath, source, parsed.name),
    name: parsed.name,
    description: parsed.description,
    path: skillPath,
    source,
    skillMdPath,
    hasSkillMd: true,
    lastModifiedAt: fileStat.mtime.toISOString(),
    ...(readError ? { error: readError } : {})
  };
}

function createFallbackSkill(
  skillPath: string,
  skillMdPath: string,
  source: SkillSource,
  error: string
): SkillInfo {
  return {
    id: stableSkillId(skillMdPath, source, 'Unknown name'),
    name: 'Unknown name',
    description: 'Missing description',
    path: skillPath,
    source,
    skillMdPath,
    hasSkillMd: true,
    error
  };
}

function parseSkillMarkdown(text: string): { name: string; description: string } {
  const frontmatter = parseFrontmatter(text);
  const body = stripFrontmatter(text);

  const title = body.match(/^#\s+(.+)$/m)?.[1]?.trim();
  const paragraph = body
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find((line) => line && !line.startsWith('#') && !line.startsWith('---'));

  return {
    name: cleanMetadataValue(frontmatter.name) || title || 'Unknown name',
    description: cleanMetadataValue(frontmatter.description) || paragraph || 'Missing description'
  };
}

function parseFrontmatter(text: string): Record<string, string> {
  if (!text.startsWith('---')) {
    return {};
  }

  const closeIndex = text.indexOf('\n---', 3);
  if (closeIndex === -1) {
    return {};
  }

  const metadata: Record<string, string> = {};
  const block = text.slice(3, closeIndex);
  for (const line of block.split(/\r?\n/)) {
    const match = line.match(/^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$/);
    if (!match) {
      continue;
    }
    metadata[match[1] ?? ''] = match[2] ?? '';
  }

  return metadata;
}

function stripFrontmatter(text: string): string {
  if (!text.startsWith('---')) {
    return text;
  }

  const closeIndex = text.indexOf('\n---', 3);
  return closeIndex === -1 ? text : text.slice(closeIndex + 4);
}

function cleanMetadataValue(value: string | undefined): string | undefined {
  const cleaned = value?.trim().replace(/^['"]|['"]$/g, '');
  return cleaned ? cleaned : undefined;
}

function stableSkillId(skillMdPath: string, source: SkillSource, name: string): string {
  return createHash('sha1').update(`${source}:${skillMdPath}:${name}`).digest('hex');
}

function isMissingPath(error: unknown): boolean {
  return typeof error === 'object' && error !== null && 'code' in error && error.code === 'ENOENT';
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
