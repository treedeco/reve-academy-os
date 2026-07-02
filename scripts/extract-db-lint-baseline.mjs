import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const outPath = path.join(repoRoot, 'scripts', 'db-lint-baseline.json');

function extractLintPayload(output) {
  const line = output
    .split(/\r?\n/)
    .find((entry) => entry.includes('"results"') && entry.includes('"message":"db lint"'));

  if (!line) {
    throw new Error('Could not locate db lint JSON payload in command output');
  }

  return JSON.parse(line.trim());
}

const lint = spawnSync('npx', ['supabase', 'db', 'lint'], {
  cwd: repoRoot,
  encoding: 'utf8',
  shell: process.platform === 'win32',
});

const combinedOutput = `${lint.stdout ?? ''}\n${lint.stderr ?? ''}`;
const payload = extractLintPayload(combinedOutput);
const findings = [];

for (const result of payload.results) {
  const [schema, name] = result.function.includes('.')
    ? result.function.split('.', 2)
    : ['public', result.function];

  for (const issue of result.issues) {
    findings.push({
      id: `${schema}.${name}|${issue.level}|${issue.message}`,
      schema,
      object: name,
      level: issue.level,
      message: issue.message,
      sqlState: issue.sqlState ?? '',
    });
  }
}

findings.sort((a, b) => a.id.localeCompare(b.id));

const document = {
  version: 1,
  description:
    'Allowlisted pre-existing Supabase db lint findings. Any finding not listed here fails verification.',
  sourceCommand: 'npx supabase db lint',
  capturedAt: new Date().toISOString(),
  findingCount: findings.length,
  findings,
};

fs.writeFileSync(outPath, `${JSON.stringify(document, null, 2)}\n`);
console.log(`Captured ${findings.length} findings (raw exit ${lint.status ?? 'unknown'}) to ${outPath}`);
