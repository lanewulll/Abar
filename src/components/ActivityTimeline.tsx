import type { CodexEvent } from '../types/app';
import { formatEventTitle, formatTime } from '../utils/format';

type ActivityTimelineProps = {
  events: CodexEvent[];
};

export function ActivityTimeline({ events }: ActivityTimelineProps): JSX.Element {
  if (events.length === 0) {
    return <p className="empty-state">No Codex hook events received yet.</p>;
  }

  return (
    <div className="timeline">
      {events.map((event) => (
        <details className="timeline-item" key={event.id}>
          <summary>
            <span className={`event-dot ${event.status ?? 'unknown'}`} />
            <strong>{formatEventTitle(event)}</strong>
            <span>{event.status ?? 'unknown'}</span>
            <time>{formatTime(event.createdAt)}</time>
          </summary>
          <pre>{JSON.stringify(event.payload ?? {}, null, 2)}</pre>
        </details>
      ))}
    </div>
  );
}
