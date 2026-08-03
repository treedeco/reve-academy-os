/**
 * Stage logging, timed fetch, and child-process execution for production operator scripts.
 * Never log secrets, tokens, or full identifiers.
 */
import { spawn } from 'node:child_process';

export const DEFAULT_CHILD_PROCESS_TIMEOUT_MS = 120_000;
export const DEFAULT_FETCH_TIMEOUT_MS = 30_000;
export const DEFAULT_NODE_SCRIPT_TIMEOUT_MS = 180_000;

export class ProductionOperatorTimeoutError extends Error {
  constructor(kind, timeoutMs, stage = null) {
    const stageSuffix = stage ? ` at stage ${stage}` : '';
    super(`${kind} timed out after ${timeoutMs}ms${stageSuffix}`);
    this.name = 'ProductionOperatorTimeoutError';
    this.kind = kind;
    this.timeoutMs = timeoutMs;
    this.stage = stage;
  }
}

function isAbortError(error) {
  return error?.name === 'AbortError';
}

export function logStage(stage, detail = null) {
  const suffix = detail ? ` detail=${detail}` : '';
  process.stderr.write(`[production-operator] stage=${stage}${suffix}\n`);
}

export function createTimedFetch(timeoutMs = DEFAULT_FETCH_TIMEOUT_MS) {
  return async (input, init = {}) => {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    const parentSignal = init.signal;
    const abortFromParent = () => controller.abort();

    if (parentSignal) {
      if (parentSignal.aborted) {
        clearTimeout(timeoutId);
        controller.abort();
      } else {
        parentSignal.addEventListener('abort', abortFromParent, { once: true });
      }
    }

    try {
      return await fetch(input, { ...init, signal: controller.signal });
    } catch (error) {
      if (isAbortError(error)) {
        throw new ProductionOperatorTimeoutError('fetch', timeoutMs);
      }
      throw error;
    } finally {
      clearTimeout(timeoutId);
      if (parentSignal) {
        parentSignal.removeEventListener('abort', abortFromParent);
      }
    }
  };
}

function spawnCommand(command, args, options = {}) {
  if (process.platform === 'win32' && options.useCmdWrapper !== false) {
    return spawn('cmd.exe', ['/d', '/s', '/c', command, ...args], {
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
  }

  return spawn(command, args, {
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });
}

async function killProcessTree(child) {
  if (!child?.pid) {
    return;
  }

  if (process.platform === 'win32') {
    await new Promise((resolve) => {
      const killer = spawn('taskkill', ['/pid', String(child.pid), '/t', '/f'], {
        stdio: 'ignore',
        windowsHide: true,
      });
      killer.on('close', () => resolve());
      killer.on('error', () => resolve());
    });
    return;
  }

  child.kill('SIGKILL');
}

export function runCommandWithTimeout(command, args, timeoutMs, options = {}) {
  const stage = options.stage ?? 'child_process';
  logStage(`${stage}_start`, options.detail ?? command);

  return new Promise((resolve, reject) => {
    const child = spawnCommand(command, args, options);
    let stdout = '';
    let stderr = '';
    let settled = false;

    const timer = setTimeout(async () => {
      if (settled) {
        return;
      }
      settled = true;
      await killProcessTree(child);
      logStage(`${stage}_timeout`, `${timeoutMs}ms`);
      reject(new ProductionOperatorTimeoutError('child_process', timeoutMs, stage));
    }, timeoutMs);

    child.stdout?.on('data', (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr?.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    child.on('error', (error) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      reject(error);
    });

    child.on('close', (code) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      if (code === 0) {
        logStage(`${stage}_complete`);
        resolve({ stdout, stderr, exitCode: code });
      } else {
        const message = (stderr || stdout || `exit ${code}`).trim().slice(0, 240);
        reject(new Error(`Command failed (${code}): ${message}`));
      }
    });
  });
}

export function runNpxWithTimeout(args, timeoutMs = DEFAULT_CHILD_PROCESS_TIMEOUT_MS, options = {}) {
  return runCommandWithTimeout('npx', args, timeoutMs, {
    stage: options.stage ?? 'npx',
    detail: args[0] ?? 'npx',
    useCmdWrapper: true,
  });
}

export function mapFetchTimeoutError(error, stage, timeoutMs = DEFAULT_FETCH_TIMEOUT_MS) {
  if (error instanceof ProductionOperatorTimeoutError) {
    throw new ProductionOperatorTimeoutError('fetch', error.timeoutMs ?? timeoutMs, stage);
  }
  const message = error instanceof Error ? error.message : String(error);
  if (/aborted|timed out after \d+ms/i.test(message)) {
    throw new ProductionOperatorTimeoutError('fetch', timeoutMs, stage);
  }
  throw error;
}

export function extractJsonPayload(raw) {
  const jsonStart = raw.indexOf('{');
  const arrayStart = raw.indexOf('[');
  let start = -1;
  if (jsonStart >= 0 && arrayStart >= 0) {
    start = Math.min(jsonStart, arrayStart);
  } else {
    start = Math.max(jsonStart, arrayStart);
  }
  if (start < 0) {
    throw new Error(`Unexpected command output: ${raw.slice(0, 240).replace(/\s+/g, ' ')}`);
  }
  return JSON.parse(raw.slice(start));
}
