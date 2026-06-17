type StatusBadgeProps = {
  status: 'Active' | 'Idle' | 'Inactive' | 'Not configured';
};

export function StatusBadge({ status }: StatusBadgeProps): JSX.Element {
  return <span className={`status-badge ${status.toLowerCase().replace(/\s+/g, '-')}`}>{status}</span>;
}
