export type Bounds = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export type Size = {
  width: number;
  height: number;
};

export type PopoverPlacement = {
  bounds: Bounds;
  arrowOffsetX: number;
};

export function calculatePopoverBounds(options: {
  trayBounds: Bounds;
  windowSize: Size;
  workArea: Bounds;
  gap?: number;
  margin?: number;
}): Bounds {
  const placement = calculatePopoverPlacement(options);
  if (!placement) {
    throw new Error('Cannot position popover without a valid menu bar anchor.');
  }
  return placement.bounds;
}

export function calculatePopoverPlacement(options: {
  trayBounds: Bounds;
  windowSize: Size;
  workArea: Bounds;
  gap?: number;
  margin?: number;
}): PopoverPlacement | null {
  const gap = options.gap ?? 8;
  const margin = options.margin ?? 12;
  if (!hasUsableTrayAnchor(options.trayBounds, options.workArea, margin)) {
    return null;
  }

  const trayCenterX = options.trayBounds.x + options.trayBounds.width / 2;
  const preferredX = Math.round(trayCenterX - options.windowSize.width / 2);
  const trayInsideWorkArea =
    options.trayBounds.y >= options.workArea.y - 80 &&
    options.trayBounds.y <= options.workArea.y + options.workArea.height;
  const preferredY = trayInsideWorkArea
    ? Math.round(options.trayBounds.y + options.trayBounds.height + gap)
    : Math.round(options.workArea.y + gap);
  const minX = options.workArea.x + margin;
  const maxX = options.workArea.x + options.workArea.width - options.windowSize.width - margin;
  const minY = options.workArea.y;
  const maxY = options.workArea.y + options.workArea.height - options.windowSize.height - margin;
  const x = clamp(preferredX, minX, maxX);
  const y = clamp(preferredY, minY, maxY);

  return {
    bounds: {
      x,
      y,
      width: options.windowSize.width,
      height: options.windowSize.height
    },
    arrowOffsetX: Math.round(clamp(trayCenterX - x, 28, options.windowSize.width - 28))
  };
}

function hasUsableTrayAnchor(trayBounds: Bounds, workArea: Bounds, margin: number): boolean {
  const values = [trayBounds.x, trayBounds.y, trayBounds.width, trayBounds.height];
  if (!values.every((value) => Number.isFinite(value))) {
    return false;
  }
  if (trayBounds.width <= 0 || trayBounds.height <= 0) {
    return false;
  }

  const trayIsFarOutsideVerticalWorkArea =
    trayBounds.y > workArea.y + workArea.height || trayBounds.y + trayBounds.height < workArea.y - 80;
  const trayLooksLikeLeftEdgeFallback = trayBounds.x <= workArea.x + margin;
  return !(trayIsFarOutsideVerticalWorkArea && trayLooksLikeLeftEdgeFallback);
}

function clamp(value: number, min: number, max: number): number {
  if (max < min) {
    return min;
  }
  return Math.max(min, Math.min(max, value));
}
