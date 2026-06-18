import type { Rectangle } from 'electron';

export function recoverRightEdgeStatusBounds(bounds: Rectangle, workArea: Rectangle): Rectangle | null {
  const reportedAtLeftEdge = bounds.x <= workArea.x + 12;
  const reportedAtBottomEdge = bounds.y >= workArea.y + workArea.height - Math.max(bounds.height, 24);
  if (!reportedAtLeftEdge || !reportedAtBottomEdge || bounds.width <= 0) {
    return null;
  }

  return {
    x: Math.round(workArea.x + workArea.width - bounds.width - 12),
    y: Math.round(Math.max(0, workArea.y - Math.max(bounds.height, 24))),
    width: bounds.width,
    height: Math.max(bounds.height, 24)
  };
}
