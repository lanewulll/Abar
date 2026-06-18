export function findAbarProcessIds(processList, repoRoot, currentPid) {
  return processList
    .split('\n')
    .filter((line) => {
      if (!line.includes(repoRoot)) {
        return false;
      }
      return (
        line.includes('/dist/mac-arm64/Abar.app/Contents/MacOS/Abar') ||
        line.includes('/dist/mac-arm64/Abar.app/Contents/Frameworks/Abar Helper') ||
        line.includes('electron-vite dev') ||
        line.includes('npm run dev:electron') ||
        line.includes('node_modules/electron/dist/Electron.app/Contents/MacOS/Electron .')
      );
    })
    .map((line) => Number(line.trim().split(/\s+/, 1)[0]))
    .filter((pid) => Number.isInteger(pid) && pid > 0 && pid !== currentPid);
}
