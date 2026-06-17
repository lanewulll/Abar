import { Send } from 'lucide-react';
import type { AppState } from '../types/app';
import { ActivityTimeline } from '../components/ActivityTimeline';

type ActivityProps = {
  state: AppState;
  actions: {
    createTestEvent: () => Promise<void>;
  };
  busy: string | null;
};

export function ActivityPage({ state, actions, busy }: ActivityProps): JSX.Element {
  return (
    <div className="page-stack">
      <section className="surface">
        <div className="section-header">
          <div>
            <h2>Activity Timeline</h2>
            <p className="muted">
              Server: {state.server.listening ? `${state.server.host}:${state.server.port}` : state.server.error ?? 'offline'}
            </p>
          </div>
          <button type="button" onClick={actions.createTestEvent} disabled={busy === 'event'}>
            <Send size={16} />
            Test event
          </button>
        </div>
      </section>
      <ActivityTimeline events={state.events} />
    </div>
  );
}
