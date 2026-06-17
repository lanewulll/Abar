import { RefreshCcw } from 'lucide-react';
import type { AppState } from '../types/app';
import { QuotaCard } from '../components/QuotaCard';
import { formatTime, quotaWindow } from '../utils/format';

type QuotaProps = {
  state: AppState;
  actions: {
    refreshQuota: () => Promise<void>;
  };
  busy: string | null;
};

export function Quota({ state, actions, busy }: QuotaProps): JSX.Element {
  return (
    <div className="page-grid">
      <QuotaCard title="5h limit" window={quotaWindow(state.quota, '5h')} error={state.quota?.error} />
      <QuotaCard title="Weekly limit" window={quotaWindow(state.quota, 'weekly')} error={state.quota?.error} />
      <section className="surface">
        <h2>Credits</h2>
        <p className="large-value">{state.quota?.credits?.remaining ?? 'Not available'}</p>
        <p className="muted">{state.quota?.credits?.unit ?? 'credits'}</p>
      </section>
      <section className="surface">
        <h2>Provider</h2>
        <p className="large-value">{state.quota?.source ?? 'unknown'}</p>
        <p className="muted">Confidence: {state.quota?.confidence ?? 'low'}</p>
      </section>
      <section className="surface span-2">
        <div className="section-header">
          <div>
            <h2>Snapshot</h2>
            <p className="muted">Last updated: {formatTime(state.quota?.updatedAt)}</p>
          </div>
          <button type="button" onClick={actions.refreshQuota} disabled={busy === 'quota'}>
            <RefreshCcw size={16} />
            Refresh
          </button>
        </div>
        {state.quota?.error ? <p className="error-text">{state.quota.error}</p> : null}
      </section>
    </div>
  );
}
