import type { CodexEvent } from '../types/app';
import { formatEventTitle, formatTime } from '../utils/format';

type ActivityTimelineProps = {
  events: CodexEvent[];
  interactive?: boolean;
};

export function ActivityTimeline({ events, interactive = false }: ActivityTimelineProps): JSX.Element {
  if (events.length === 0) {
    return <p className="empty-state">No Codex hook events received yet.</p>;
  }

  return (
    <div className="timeline">
      {events.map((event) =>
        interactive ? (
          <details className="timeline-item" key={event.id}>
            <summary>
              <EventRow event={event} />
            </summary>
            <pre>{JSON.stringify(event.payload ?? {}, null, 2)}</pre>
          </details>
        ) : (
          <div className="timeline-item" key={event.id}>
            <div className="timeline-row">
              <EventRow event={event} />
            </div>
          </div>
        )
      )}
    </div>
  );
}

function EventRow({ event }: { event: CodexEvent }): JSX.Element {
  return (
    <>
            <span className={`event-dot ${event.status ?? 'unknown'}`} />
            <strong>{formatEventTitle(event)}</strong>
            <span>{event.status ?? 'unknown'}</span>
            <time>{formatTime(event.createdAt)}</time>
    </>
  );
}
