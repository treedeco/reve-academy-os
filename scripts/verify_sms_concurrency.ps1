# Phase 0B-3B-2B-3D-3B — Owner SMS sent confirmation concurrency verification
# Creates runtime-only objects, runs parallel PostgreSQL sessions, asserts, and cleans up.

$ErrorActionPreference = 'Stop'

$container = 'supabase_db_reve-academy-os'
$owner = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa039'
$sms = '88888888-8888-8888-8888-888888888039'
$pass = '66666666-6666-6666-6666-666666666039'
$student = '44444444-4444-4444-4444-444444444039'
$course = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee39'
$product = 'ffffffff-ffff-ffff-ffff-ffffffffff39'
$runtimeSchema = 'reve_concurrency_runtime'
$concurrencyTest = 'scripts/concurrency/owner_sms_sent_concurrency.test.sql'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-AdminSql {
  param(
    [Parameter(Mandatory = $true)][string]$Sql,
    [switch]$TuplesOnly
  )
  $args = @('exec', '-i', $container, 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1')
  if ($TuplesOnly) { $args += @('-t', '-A') }
  $args += @('-c', $Sql)
  & docker @args
}

function Invoke-PostgresSql {
  param(
    [Parameter(Mandatory = $true)][string]$Sql,
    [switch]$TuplesOnly
  )
  $args = @('exec', '-i', $container, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1')
  if ($TuplesOnly) { $args += @('-t', '-A') }
  $args += @('-c', $Sql)
  & docker @args
}

function Test-DatabaseReachable {
  docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -t -A -c 'SELECT 1;' | Out-Null
}

function Initialize-RuntimeHarness {
  Invoke-AdminSql @"
CREATE SCHEMA IF NOT EXISTS $runtimeSchema;
CREATE TABLE IF NOT EXISTS $runtimeSchema.session_results (
  session_label text PRIMARY KEY,
  no_change text NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);
TRUNCATE TABLE $runtimeSchema.session_results;
"@
}

function Remove-RuntimeHarness {
  Invoke-AdminSql "DROP SCHEMA IF EXISTS $runtimeSchema CASCADE;" | Out-Null
}

function Remove-ConcurrencyFixture {
  Invoke-AdminSql @"
DELETE FROM public.sms_notifications WHERE id = '$sms'::uuid;
DELETE FROM public.passes WHERE id = '$pass'::uuid;
DELETE FROM public.students WHERE id = '$student'::uuid;
DELETE FROM public.course_products WHERE id = '$product'::uuid;
DELETE FROM public.courses WHERE id = '$course'::uuid;
DELETE FROM public.profiles WHERE id = '$owner'::uuid;
DELETE FROM auth.users WHERE id = '$owner'::uuid;
"@ | Out-Null
}

function Invoke-OwnerConfirm {
  param([string]$Label)
  $sql = @"
SELECT set_config('request.jwt.claim.sub', '$owner', false);
SELECT set_config('request.jwt.claim.role', 'authenticated', false);
SET ROLE authenticated;
SELECT no_change::text FROM public.reve_owner_confirm_sms_sent('$sms'::uuid);
"@
  $file = [System.IO.Path]::GetTempFileName()
  Set-Content -Path $file -Value $sql -Encoding UTF8
  docker cp $file "${container}:/tmp/osc_${Label}_confirm.sql" | Out-Null
  Remove-Item $file
  $result = docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -t -A -f "/tmp/osc_${Label}_confirm.sql"
  return ($result | Select-Object -Last 1).Trim()
}

function Install-ConcurrencyFixture {
  Invoke-AdminSql @"
INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_user_meta_data, created_at, updated_at
) VALUES (
  '$owner'::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'owner-conc@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()
);

INSERT INTO public.profiles (id, role, display_name, account_state)
VALUES ('$owner'::uuid, 'owner', 'OSC Concurrency Owner', 'active');

INSERT INTO public.students (id, student_code, profile_id, name, operational_status)
VALUES ('$student'::uuid, 'S037', NULL, 'OSC Concurrency Student', 'active');

INSERT INTO public.courses (id, course_code, name, is_active)
VALUES ('$course'::uuid, 'VOCAL-CONC', 'OSC Concurrency Course', true);

INSERT INTO public.course_products (
  id, course_id, product_code, product_name,
  default_lesson_count, weekly_frequency, default_tuition_krw, is_active
) VALUES (
  '$product'::uuid, '$course'::uuid, 'VOCAL-4-CONC', 'OSC Concurrency Product', 4, 1, 200000, true
);

INSERT INTO public.passes (
  id, pass_code, student_id, course_id, course_product_id,
  sequence_number, status, registered_lesson_count_snapshot,
  weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
  start_date, activated_at, completed_at
) VALUES (
  '$pass'::uuid, 'V-S037-CNC', '$student'::uuid, '$course'::uuid, '$product'::uuid,
  1, 'completed', 4, 1, 'OSC Concurrency Product', 200000,
  DATE '2026-09-07', now() - interval '90 days', now() - interval '60 days'
);

INSERT INTO public.sms_notifications (
  id, student_id, pass_id, notification_type, status,
  message_body_snapshot, target_date
) VALUES (
  '$sms'::uuid, '$student'::uuid, '$pass'::uuid, 'renewal_reminder', 'scheduled',
  'OSC concurrent harness body', CURRENT_DATE + 2
);
"@
}

function Assert-NoProductionHarness {
  $exists = (Invoke-AdminSql @"
SELECT EXISTS (
  SELECT 1
  FROM information_schema.tables
  WHERE table_schema = 'reve_test'
    AND table_name = 'concurrency_assertions'
) OR EXISTS (
  SELECT 1
  FROM pg_namespace
  WHERE nspname = 'reve_test'
);
"@ -TuplesOnly).Trim()
  if ($exists -in @('t', 'true')) {
    throw 'Production test harness reve_test still exists after cleanup'
  }
}

$runtimeReady = $false
try {
  Write-Host 'Checking local Supabase database reachability...'
  Test-DatabaseReachable

  Write-Host 'Initializing runtime concurrency harness...'
  Initialize-RuntimeHarness
  $runtimeReady = $true

  Write-Host 'Preparing concurrency fixture...'
  Remove-ConcurrencyFixture
  Install-ConcurrencyFixture

  Write-Host 'Launching parallel confirm sessions...'
  $remoteJob = Start-Job -ScriptBlock {
    param($Container, $Owner, $Sms)
    $sql = @"
SELECT set_config('request.jwt.claim.sub', '$Owner', false);
SELECT set_config('request.jwt.claim.role', 'authenticated', false);
SET ROLE authenticated;
SELECT no_change::text FROM public.reve_owner_confirm_sms_sent('$Sms'::uuid);
"@
    $file = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $file -Value $sql -Encoding UTF8
    docker cp $file "${Container}:/tmp/osc_remote_confirm.sql" | Out-Null
    Remove-Item $file
    (docker exec -i $Container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -t -A -f /tmp/osc_remote_confirm.sql | Select-Object -Last 1).Trim()
  } -ArgumentList $container, $owner, $sms

  Start-Sleep -Milliseconds 150
  $localResult = Invoke-OwnerConfirm -Label 'local'
  $remoteResult = Receive-Job -Job $remoteJob -Wait -AutoRemoveJob

  Invoke-AdminSql @"
INSERT INTO $runtimeSchema.session_results (session_label, no_change) VALUES
  ('local', '$localResult'),
  ('remote', '$remoteResult')
ON CONFLICT (session_label) DO UPDATE
SET no_change = EXCLUDED.no_change, recorded_at = now();
"@ | Out-Null

  Write-Host "Local no_change: $localResult"
  Write-Host "Remote no_change: $remoteResult"

  $auditCount = (Invoke-AdminSql "SELECT count(*) FROM public.audit_logs WHERE action = 'sms_notification.sent_confirmed' AND resource_id = '$sms'::uuid;" -TuplesOnly).Trim()
  $status = (Invoke-AdminSql "SELECT status FROM public.sms_notifications WHERE id = '$sms'::uuid;" -TuplesOnly).Trim()
  $sentAt = (Invoke-AdminSql "SELECT sent_at::text FROM public.sms_notifications WHERE id = '$sms'::uuid;" -TuplesOnly).Trim()
  $confirmer = (Invoke-AdminSql "SELECT sent_confirmed_by_profile_id::text FROM public.sms_notifications WHERE id = '$sms'::uuid;" -TuplesOnly).Trim()

  $localNoChange = $localResult -in @('t', 'true')
  $localFirstTransition = $localResult -in @('f', 'false')
  $remoteNoChange = $remoteResult -in @('t', 'true')
  $remoteFirstTransition = $remoteResult -in @('f', 'false')

  if ($auditCount -ne '1') {
    throw "Expected exactly one audit record, got $auditCount"
  }
  if ($status -ne 'sent') {
    throw "Expected final SMS status sent, got $status"
  }
  if ([string]::IsNullOrWhiteSpace($sentAt)) {
    throw 'Expected authoritative sent_at to be recorded'
  }
  if ($confirmer -ne $owner) {
    throw "Expected confirming owner $owner, got $confirmer"
  }
  if (-not (($localFirstTransition -and $remoteNoChange) -or ($remoteFirstTransition -and $localNoChange))) {
    throw "Expected one transition and one idempotent retry, got local=$localResult remote=$remoteResult"
  }

  Write-Host 'Running dedicated concurrency pgTAP assertion...'
  Push-Location $repoRoot
  npx supabase test db $concurrencyTest
  if ($LASTEXITCODE -ne 0) {
    throw "Concurrency pgTAP assertion failed with exit code $LASTEXITCODE"
  }
  Pop-Location

  Write-Host "SMS concurrency verification passed: audit=$auditCount status=$status local=$localResult remote=$remoteResult sent_at=$sentAt confirmer=$confirmer"
}
finally {
  if ($runtimeReady) {
    Write-Host 'Cleaning up runtime concurrency harness...'
    Remove-RuntimeHarness
  }
  Assert-NoProductionHarness
}
