export function buildResetPopoverScrollScript(): string {
  return `
const popoverContent = document.querySelector('.popover-content');
if (popoverContent) {
  popoverContent.scrollTop = 0;
  popoverContent.scrollLeft = 0;
}
`;
}
