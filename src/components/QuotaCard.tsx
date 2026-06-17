import type { UsageWindow } from '../../backend/types';
import { formatPercent, formatReset } from '../utils/format';

type QuotaCardProps = {
  title: string;
  window?: UsageWindow;
  error?: string;
};

export function QuotaCard({ title, window, error }: QuotaCardProps): JSX.Element {
  const used = window?.usedPercent ?? 0;
  return (
    <section className="quota-card">
      <div className="quota-card-header">
        <h2>{title}</h2>
        <span>{formatPercent(window?.usedPercent)} used</span>
      </div>
      <div className="meter" aria-label={`${title} quota used`}>
        <div style={{ width: `${Math.max(0, Math.min(100, used))}%` }} />
      </div>
      <p>{window ? formatReset(window) : error ?? 'Quota provider not configured.'}</p>
    </section>
  );
}
