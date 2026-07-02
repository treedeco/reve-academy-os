import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const baselinePath = path.join(repoRoot, 'scripts', 'db-lint-baseline.json');
const capturePath = path.join(repoRoot, 'artifacts', 'db-lint-current.json');

function extractLintPayload(output) {
  const line = output
    .split(/\r?\n/)
    .find((entry) => entry.includes('"results"') && entry.includes('"message":"db lint"'));

  if (!line) {
    throw new Error('Could not locate db lint JSON payload in command output');
  }

  return JSON.parse(line.trim());
}

function normalizeFindings(payload) {
  const findings = [];

  for (const result of payload.results ?? []) {
    const [schema, name] = result.function.includes('.')
      ? result.function.split('.', 2)
      : ['public', result.function];

    for (const issue of result.issues ?? []) {
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
  return findings;
}

function main() {
  if (!fs.existsSync(baselinePath)) {
    console.error(`Missing baseline file: ${baselinePath}`);
    process.exit(1);
  }

  const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
  const baselineById = new Map(baseline.findings.map((finding) => [finding.id, finding]));

  const lint = spawnSync('npx', ['supabase', 'db', 'lint'], {
    cwd: repoRoot,
    encoding: 'utf8',
    shell: process.platform === 'win32',
  });

  const combinedOutput = `${lint.stdout ?? ''}\n${lint.stderr ?? ''}`;
  fs.mkdirSync(path.dirname(capturePath), { recursive: true });

  let currentFindings;
  try {
    const payload = extractLintPayload(combinedOutput);
    currentFindings = normalizeFindings(payload);
    fs.writeFileSync(
      capturePath,
      `${JSON.stringify({ capturedAt: new Date().toISOString(), findingCount: currentFindings.length, findings: currentFindings }, null, 2)}\n`,
    );
  } catch (error) {
    console.error(String(error));
    console.error(combinedOutput);
    process.exit(lint.status ?? 1);
  }

  const currentById = new Map(currentFindings.map((finding) => [finding.id, finding]));
  const newFindings = currentFindings.filter((finding) => !baselineById.has(finding.id));
  const removedFindings = baseline.findings.filter((finding) => !currentById.has(finding.id));
  const changedFindings = baseline.findings
    .filter((finding) => currentById.has(finding.id))
    .filter((finding) => {
      const current = currentById.get(finding.id);
      return (
        current.level !== finding.level ||
        current.message !== finding.message ||
        current.sqlState !== finding.sqlState
      );
    })
    .map((finding) => ({
      id: finding.id,
      baseline: finding,
      current: currentById.get(finding.id),
    }));

  console.log(`db lint raw exit code: ${lint.status ?? 'unknown'}`);
  console.log(`allowlisted baseline findings: ${baseline.findings.length}`);
  console.log(`current findings: ${currentFindings.length}`);
  console.log(`new findings: ${newFindings.length}`);
  console.log(`removed baseline findings: ${removedFindings.length}`);
  console.log(`changed baseline findings: ${changedFindings.length}`);

  if (newFindings.length > 0) {
    console.error('\nNew findings (not allowlisted):');
    for (const finding of newFindings) {
      console.error(`- [${finding.level}] ${finding.schema}.${finding.object}: ${finding.message}`);
    }
  }

  if (changedFindings.length > 0) {
    console.error('\nChanged allowlisted findings:');
    for (const finding of changedFindings) {
      console.error(`- ${finding.id}`);
      console.error(`  baseline: ${finding.baseline.level} / ${finding.baseline.message}`);
      console.error(`  current:  ${finding.current.level} / ${finding.current.message}`);
    }
  }

  if (removedFindings.length > 0) {
    console.warn('\nBaseline findings no longer reported (update baseline if intentional):');
    for (const finding of removedFindings) {
      console.warn(`- [${finding.level}] ${finding.schema}.${finding.object}: ${finding.message}`);
    }
  }

  const phase1aObjects = new Set([
    'reve_owner_get_pass_usage',
    'trg_deferred_validate_lessons',
    'trg_deferred_validate_pass_status',
  ]);
  const phase1aFindings = currentFindings.filter((finding) => phase1aObjects.has(finding.object));
  if (phase1aFindings.length > 0) {
    console.error('\nPhase 1A objects reported lint findings:');
    for (const finding of phase1aFindings) {
      console.error(`- [${finding.level}] ${finding.schema}.${finding.object}: ${finding.message}`);
    }
    process.exit(1);
  }

  if (newFindings.length > 0 || changedFindings.length > 0) {
    process.exit(1);
  }

  console.log('Database lint baseline verification passed.');
  process.exit(0);
}

main();
