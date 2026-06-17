import { FolderOpen } from 'lucide-react';
import type { SkillInfo } from '../types/app';
import { compactPath } from '../utils/format';

type SkillListProps = {
  skills: SkillInfo[];
  onOpenPath: (path: string) => void;
};

export function SkillList({ skills, onOpenPath }: SkillListProps): JSX.Element {
  if (skills.length === 0) {
    return <p className="empty-state">No skills scanned yet.</p>;
  }

  return (
    <div className="data-list">
      {skills.map((skill) => (
        <article className="skill-row" key={skill.id}>
          <div>
            <div className="row-title">
              <strong>{skill.name}</strong>
              <span className={`source-pill ${skill.source}`}>{skill.source}</span>
            </div>
            <p>{skill.description}</p>
            <code>{compactPath(skill.path)}</code>
          </div>
          <button className="icon-button" type="button" title="Open skill folder" onClick={() => onOpenPath(skill.path)}>
            <FolderOpen size={18} />
          </button>
        </article>
      ))}
    </div>
  );
}
