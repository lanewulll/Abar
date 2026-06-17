import { RotateCw } from 'lucide-react';
import type { AppState } from '../types/app';
import { SkillList } from '../components/SkillList';

type SkillsProps = {
  state: AppState;
  actions: {
    rescanSkills: () => Promise<void>;
    openPath: (path: string) => Promise<void>;
  };
  busy: string | null;
};

export function Skills({ state, actions, busy }: SkillsProps): JSX.Element {
  return (
    <div className="page-stack">
      <section className="surface">
        <div className="section-header">
          <div>
            <h2>Skills</h2>
            <p className="muted">{state.skills.length} available skill(s) from project, user, and system locations.</p>
          </div>
          <button type="button" onClick={actions.rescanSkills} disabled={busy === 'skills'}>
            <RotateCw size={16} />
            Rescan
          </button>
        </div>
      </section>
      <SkillList skills={state.skills} onOpenPath={actions.openPath} />
    </div>
  );
}
