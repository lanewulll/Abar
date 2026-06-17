import { RefreshCcw, RotateCw } from 'lucide-react';
import type { AppState } from '../types/app';
import { ActivityTimeline } from '../components/ActivityTimeline';
import { QuotaCard } from '../components/QuotaCard';
import { StatusBadge } from '../components/StatusBadge';
import { compactPath, latestToolCall, quotaWindow, statusFromEvents } from '../utils/format';

type OverviewProps = {
  state: AppState;
  actions: {
    refreshQuota: () => Promise<void>;
    rescanSkills: () => Promise<void>;
  };
  busy: string | null;
};

export function Overview({ state, actions, busy }: OverviewProps): JSX.Element {
  const recentTool = latestToolCall(state.events);
  return (
    <div className="page-grid">
      <section className="summary-band">
        <div>
          <p className="eyebrow">Status</p>
          <h2>Codex is {statusFromEvents(state.events).toLowerCase()}</h2>
        </div>
        <StatusBadge status={statusFromEvents(state.events)} />
      </section>

      <QuotaCard title="5h quota" window={quotaWindow(state.quota, '5h')} error={state.quota?.error} />
      <QuotaCard title="Weekly quota" window={quotaWindow(state.quota, 'weekly')} error={state.quota?.error} />

      <section className="surface">
        <h2>Project</h2>
        <p className="muted">{compactPath(state.config.projectPath)}</p>
        <div className="inline-stats">
          <span>{state.skills.length} skills</span>
          <span>{state.events.length} recent events</span>
        </div>
      </section>

      <section className="surface">
        <h2>Recent Tool</h2>
        <p className="large-value">{recentTool?.toolName ?? 'None'}</p>
        <p className="muted">{recentTool ? recentTool.eventType : 'Waiting for hook events.'}</p>
      </section>

      <section className="surface span-2">
        <div className="section-header">
          <h2>Actions</h2>
          <div className="button-row">
            <button type="button" onClick={actions.refreshQuota} disabled={busy === 'quota'}>
              <RefreshCcw size={16} />
              Refresh quota
            </button>
            <button type="button" onClick={actions.rescanSkills} disabled={busy === 'skills'}>
              <RotateCw size={16} />
              Rescan skills
            </button>
          </div>
        </div>
      </section>

      <section className="surface span-2">
        <h2>Recent Activity</h2>
        <ActivityTimeline events={state.events.slice(0, 5)} />
      </section>
    </div>
  );
}
