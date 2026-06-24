#!/usr/bin/env node

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { buildAbarHookConfig, mergeAbarHooks, removeOwnedAbarHooks } from './lib/hook-config.js';
import { redactDiagnosticValue, redactPath } from './lib/diagnostic.js';
import { buildFullUninstallPlan } from './lib/uninstall.js';
import { compareUpdateState } from './lib/update-check.js';

const args = process.argv.slice(2);
const home = os.homedir();
const codexHome = process.env.CODEX_HOME || path.join(home, '.codex');
const installDir = process.env.ABAR_INSTALL_DIR || path.join(home, 'Applications');
const appPath = path.join(installDir, 'Abar.app');
const hooksPath = path.join(codexHome, 'hooks.json');
const reporterPath = path.join(appPath, 'Contents', 'Resources', 'reporter', 'reporter.js');
const databasePath = process.env.ABAR_NATIVE_DB_PATH ||
  path.join(home, 'Library', 'Application Support', 'abar', 'abar.sqlite');
const port = validPort(process.env.ABAR_SERVER_PORT) ?? 3987;

try {
  await main();
} catch (error) {
  console.error(`错误：${error.message}`);
  process.exitCode = 1;
}

async function main() {
  const [area, action] = args;
  if (area === 'hooks' && ['preview', 'install'].includes(action)) {
    return handleHooks(action);
  }
  if (area === 'diagnostic') {
    return handleDiagnostic(args.includes('--json'));
  }
  if (area === 'uninstall' && action === 'full') {
    return handleFullUninstall();
  }
  if (area === 'uninstall' && action === 'app') {
    return handleAppUninstall();
  }
  if (area === 'update' && action === 'check') {
    return handleUpdateCheck(args.includes('--json'));
  }
  throw new Error('未知命令。支持 hooks preview|install、diagnostic、uninstall app|full、update check。');
}

function validPort(value) {
  const portValue = Number(value);
  return Number.isInteger(portValue) && portValue > 0 && portValue <= 65535 ? portValue : undefined;
}

function readHooks() {
  if (!fs.existsSync(hooksPath)) {
    return {};
  }
  const raw = fs.readFileSync(hooksPath, 'utf8');
  try {
    return JSON.parse(raw);
  } catch {
    throw new Error(`${hooksPath} 是无效 JSON；未做任何修改。请先修复或移走该文件。`);
  }
}

function backupFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return undefined;
  }
  const stamp = new Date().toISOString().replaceAll(':', '-');
  const backupPath = `${filePath}.abar-backup-${stamp}`;
  fs.copyFileSync(filePath, backupPath, fs.constants.COPYFILE_EXCL);
  return backupPath;
}

function writeJSONAtomically(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const temporaryPath = `${filePath}.abar-tmp-${process.pid}`;
  fs.writeFileSync(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  JSON.parse(fs.readFileSync(temporaryPath, 'utf8'));
  fs.renameSync(temporaryPath, filePath);
}

function handleHooks(action) {
  const existing = readHooks();
  const generated = buildAbarHookConfig(reporterPath, port);
  const merged = mergeAbarHooks(existing, generated);
  if (action === 'preview') {
    process.stdout.write(`${JSON.stringify(merged, null, 2)}\n`);
    return;
  }
  if (!fs.existsSync(reporterPath)) {
    throw new Error(`未找到安装后的 Reporter：${reporterPath}；请先运行 npm run setup。`);
  }
  const backupPath = backupFile(hooksPath);
  writeJSONAtomically(hooksPath, merged);
  console.log(`Abar Hook 已安全合并到：${hooksPath}`);
  if (backupPath) {
    console.log(`原配置备份：${backupPath}`);
  }
  console.log('下一步必须由用户在 Codex 中运行 /hooks，检查并信任 Abar Hook。');
}

function command(name, commandArgs = []) {
  const result = spawnSync(name, commandArgs, { encoding: 'utf8', timeout: 5000 });
  return {
    available: !result.error || result.error.code !== 'ENOENT',
    status: result.status,
    stdout: result.stdout?.trim() ?? '',
    stderr: result.stderr?.trim() ?? ''
  };
}

function inspectHooks() {
  if (!fs.existsSync(hooksPath)) {
    return { exists: false, valid: false, configured: false, reporterPathValid: false };
  }
  try {
    const config = JSON.parse(fs.readFileSync(hooksPath, 'utf8'));
    const commands = Object.values(config.hooks ?? {})
      .flatMap((groups) => Array.isArray(groups) ? groups : [])
      .flatMap((group) => Array.isArray(group?.hooks) ? group.hooks : [])
      .map((hook) => String(hook?.command ?? ''));
    const abarCommands = commands.filter((value) => value.includes('ABAR_HOOK_OWNER=abar-v1'));
    const legacyCommands = commands.filter((value) =>
      value.includes('codex-hook-reporter/reporter.js') && !value.includes('ABAR_HOOK_OWNER=abar-v1')
    );
    const configuredReporterPaths = abarCommands
      .map((value) => value.match(/node '([^']+reporter\.js)'/)?.[1])
      .filter(Boolean);
    const legacyReporterPaths = legacyCommands
      .map((value) => value.match(/node '([^']+reporter\.js)'/)?.[1])
      .filter(Boolean);
    return {
      exists: true,
      valid: true,
      configured: abarCommands.length >= 2,
      trust: 'unknown',
      reporterPathValid: configuredReporterPaths.length > 0 &&
        configuredReporterPaths.every((value) => fs.existsSync(value)),
      reporterPaths: configuredReporterPaths,
      legacyConfigured: legacyCommands.length > 0,
      legacyReporterPaths
    };
  } catch (error) {
    return { exists: true, valid: false, configured: false, reporterPathValid: false, error: error.message };
  }
}

function inspectHealth() {
  const result = command('/usr/bin/curl', [
    '--silent', '--show-error', '--max-time', '1', `http://127.0.0.1:${port}/health`
  ]);
  const healthy = result.status === 0 && result.stdout.includes('"service":"abar"');
  const listeners = command('/usr/sbin/lsof', ['-nP', '-Fpcn', `-iTCP:${port}`, '-sTCP:LISTEN']);
  return {
    healthy,
    endpoint: `http://127.0.0.1:${port}/health`,
    response: result.stdout || result.stderr,
    portInUse: listeners.status === 0,
    listener: listeners.stdout.split('\n').filter((line) => /^[pcn]/.test(line)).slice(0, 6).join('\n')
  };
}

function inspectDatabase() {
  if (!fs.existsSync(databasePath)) {
    return { exists: false, readable: false, path: databasePath };
  }
  try {
    fs.accessSync(databasePath, fs.constants.R_OK | fs.constants.W_OK);
    const quota = command('/usr/bin/sqlite3', [
      databasePath,
      "SELECT created_at || '|' || COALESCE(error, '') FROM quota_snapshots ORDER BY created_at DESC LIMIT 1;"
    ]);
    const [lastQuotaSnapshot, lastQuotaError] = quota.stdout.split('|');
    const successful = command('/usr/bin/sqlite3', [
      databasePath,
      "SELECT created_at FROM quota_snapshots WHERE error IS NULL OR error = '' ORDER BY created_at DESC LIMIT 1;"
    ]);
    return {
      exists: true,
      readable: true,
      writable: true,
      path: databasePath,
      sizeBytes: fs.statSync(databasePath).size,
      lastQuotaSnapshot: lastQuotaSnapshot || undefined,
      lastSuccessfulQuotaRefresh: successful.stdout || undefined,
      lastQuotaError: lastQuotaError || undefined
    };
  } catch (error) {
    return { exists: true, readable: false, writable: false, path: databasePath, error: error.message };
  }
}

function diagnosticReport() {
  const codexVersion = command('codex', ['--version']);
  const login = command('codex', ['login', 'status']);
  const nodeVersion = command('node', ['--version']);
  const npmVersion = command('npm', ['--version']);
  const swiftVersion = command('swift', ['--version']);
  const macOSVersion = command('/usr/bin/sw_vers', ['-productVersion']);
  const hooks = inspectHooks();
  const health = inspectHealth();
  const database = inspectDatabase();
  const quotaStatus = !database.exists
    ? 'unavailable'
    : database.lastQuotaError
      ? (database.lastSuccessfulQuotaRefresh ? 'cached' : 'failed')
      : database.lastQuotaSnapshot
        ? 'live'
        : fs.existsSync(path.join(codexHome, 'auth.json')) ? 'waiting' : 'unavailable-file-auth';

  const broken = [
    process.platform !== 'darwin',
    process.arch !== 'arm64',
    !fs.existsSync(appPath),
    !hooks.valid,
    !hooks.configured,
    !hooks.reporterPathValid,
    !health.healthy,
    database.exists && !database.readable
  ].some(Boolean);
  const degraded = !broken && (login.status !== 0 || ['cached', 'failed', 'unavailable', 'unavailable-file-auth'].includes(quotaStatus));

  return redactDiagnosticValue({
    overall: broken ? 'broken' : degraded ? 'degraded' : 'healthy',
    abarVersion: process.env.npm_package_version ?? readPackageVersion(),
    macOSVersion: macOSVersion.stdout,
    chip: process.arch,
    nodeVersion: nodeVersion.stdout,
    npmVersion: npmVersion.stdout,
    swiftVersion: swiftVersion.stdout.split('\n')[0],
    codexCLI: { installed: codexVersion.available, version: codexVersion.stdout },
    codexLogin: { loggedIn: login.status === 0, detail: login.stdout || login.stderr },
    hooks,
    localServer: health,
    database,
    quotaStatus,
    hookTrust: 'unknown; run /hooks in Codex',
    appInstallPath: appPath,
    logPath: path.join(home, 'Library', 'Logs', 'Abar'),
    cachePath: path.join(home, 'Library', 'Caches', 'dev.abar.native-overlay')
  }, home);
}

function readPackageVersion() {
  const candidates = [
    path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', 'package.json'),
    path.join(appPath, 'Contents', 'Resources', 'package.json')
  ];
  for (const candidate of candidates) {
    try {
      return JSON.parse(fs.readFileSync(candidate, 'utf8')).version;
    } catch {
      // Continue to the packaged fallback.
    }
  }
  return 'unknown';
}

function handleDiagnostic(asJSON) {
  const report = diagnosticReport();
  if (asJSON) {
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  } else {
    console.log(`Abar 状态：${report.overall}`);
    console.log(`应用：${report.appInstallPath}`);
    console.log(`Codex CLI：${report.codexCLI.installed ? report.codexCLI.version : '未安装'}`);
    console.log(`Codex 登录：${report.codexLogin.loggedIn ? '已登录' : '未登录或无法确认'}`);
    console.log(`Hook：${report.hooks.configured ? '已配置' : '未完成'}；信任状态需在 /hooks 确认`);
    console.log(`本地服务：${report.localServer.healthy ? '正常' : '异常'}`);
    console.log(`数据库：${report.database.readable ? '可用' : '不可用或尚未创建'}`);
    console.log('使用 npm run diagnostic -- --json 可复制完整脱敏报告。');
  }
  if (report.overall === 'broken') {
    process.exitCode = 2;
  } else if (report.overall === 'degraded') {
    process.exitCode = 1;
  }
}

function handleFullUninstall() {
  const dryRun = args.includes('--dry-run');
  const confirmed = args.includes('--yes');
  const plan = buildFullUninstallPlan({ home, installDir, codexHome });
  console.log(dryRun ? '完整卸载预览：' : '完整卸载：');
  plan.paths.forEach((value) => console.log(`- ${redactPath(value, home)}`));
  console.log(`- 从 ${redactPath(plan.hooksPath, home)} 中移除带 Abar 所有权标记的 Hook`);
  if (dryRun) {
    return;
  }
  if (!confirmed) {
    throw new Error('实际执行需要显式传入 --yes；请先使用 --dry-run 预览。');
  }

  if (fs.existsSync(plan.hooksPath)) {
    const config = readHooks();
    const result = removeOwnedAbarHooks(config);
    const backupPath = backupFile(plan.hooksPath);
    writeJSONAtomically(plan.hooksPath, result.config);
    console.log(`Hook 备份：${redactPath(backupPath, home)}`);
    console.log(`已移除 ${result.removedCount} 个带所有权标记的 Abar Hook 组。`);
    if (result.legacyEntries.length > 0) {
      console.log(`检测到 ${result.legacyEntries.length} 个旧版无标记 Abar Hook，未自动删除，请人工确认。`);
    }
  }

  for (const target of plan.paths) {
    fs.rmSync(target, { recursive: true, force: true });
  }
  console.log('完整卸载完成。用户原有 Hook 已保留。');
}

function handleAppUninstall() {
  const dryRun = args.includes('--dry-run');
  const confirmed = args.includes('--yes');
  console.log(`${dryRun ? '仅移除应用预览' : '仅移除应用'}：${redactPath(appPath, home)}`);
  console.log('本地数据和 Codex Hook 将保留。');
  if (dryRun) {
    return;
  }
  if (!confirmed) {
    throw new Error('实际执行需要显式传入 --yes；请先使用 --dry-run 预览。');
  }
  fs.rmSync(appPath, { recursive: true, force: true });
  console.log('Abar 应用已移除，本地数据和 Hook 已保留。');
}

async function handleUpdateCheck(asJSON) {
  const currentCommit = process.env.ABAR_CURRENT_COMMIT || command('git', ['rev-parse', 'HEAD']).stdout;
  let latestCommit = process.env.ABAR_LATEST_COMMIT;
  let latestDate;
  let compareURL;
  if (!latestCommit) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 5000);
    try {
      const response = await fetch('https://api.github.com/repos/lanewulll/Abar/commits/main', {
        headers: { accept: 'application/vnd.github+json', 'user-agent': 'Abar update checker' },
        signal: controller.signal
      });
      if (!response.ok) {
        throw new Error(`GitHub 返回 HTTP ${response.status}`);
      }
      const payload = await response.json();
      latestCommit = payload.sha;
      latestDate = payload.commit?.committer?.date;
    } finally {
      clearTimeout(timer);
    }
  }
  const state = compareUpdateState({ currentCommit, latestCommit });
  state.latestDate = latestDate;
  state.compareURL = state.status === 'available'
    ? `https://github.com/lanewulll/Abar/compare/${currentCommit}...${latestCommit}`
    : undefined;
  state.updateCommand = 'git pull --ff-only && npm run setup && npm run hooks:preview && npm run doctor';
  if (asJSON) {
    process.stdout.write(`${JSON.stringify(state, null, 2)}\n`);
  } else {
    console.log(state.status === 'available' ? '发现 Abar 更新。' :
      state.status === 'current' ? 'Abar 已是当前版本。' : '无法判断更新状态。');
    console.log(`当前提交：${state.currentCommit || 'unknown'}`);
    console.log(`最新提交：${state.latestCommit || 'unknown'}`);
    if (state.status === 'available') {
      console.log(`更新命令：${state.updateCommand}`);
      console.log('更新后请重新运行 npm run doctor，并在路径变化时重新安装 Hook。');
    }
  }
}
