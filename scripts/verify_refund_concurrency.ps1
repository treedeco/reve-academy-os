# Phase 0B-3B-2B-3E — payment refund concurrency verification (RC-05 + duplicate refund)

$ErrorActionPreference = 'Stop'

$container = 'supabase_db_reve-academy-os'
$owner = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa049'
$teacher = 'dddddddd-dddd-dddd-dddd-ddddddddd049'
$student = '44444444-4444-4444-4444-444444444049'
$studentDup = '44444444-4444-4444-4444-44444444404a'
$course = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee49'
$product = 'ffffffff-ffff-ffff-ffff-ffffffffff49'
$teacherRow = '22222222-2222-2222-2222-222222222049'
$pass = '66666666-6666-6666-6666-666666666049'
$slot = '77777777-7777-7777-7777-777777777749'
$lessonDone1 = '99999999-9999-9999-9999-999999999949'
$lessonDone2 = '99999999-9999-9999-9999-99999999994a'
$lessonDone3 = '99999999-9999-9999-9999-99999999994b'
$lessonFuture = '99999999-9999-9999-9999-99999999994c'
$payment = '12121212-1212-1212-1212-121212121249'
$paymentDup = '12121212-1212-1212-1212-12121212124a'
$passDup = '66666666-6666-6666-6666-66666666604a'
$runtimeSchema = 'reve_concurrency_runtime'
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

function Test-DatabaseReachable {
  docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -t -A -c 'SELECT 1;' | Out-Null
}

function Initialize-RuntimeHarness {
  Invoke-AdminSql @"
CREATE SCHEMA IF NOT EXISTS $runtimeSchema;
CREATE TABLE IF NOT EXISTS $runtimeSchema.refund_session_results (
  scenario text PRIMARY KEY,
  outcome text NOT NULL,
  detail text,
  recorded_at timestamptz NOT NULL DEFAULT now()
);
TRUNCATE TABLE $runtimeSchema.refund_session_results;
"@ | Out-Null
}

function Remove-RuntimeHarness {
  Invoke-AdminSql "DROP SCHEMA IF EXISTS $runtimeSchema CASCADE;" | Out-Null
}

function Remove-RefundFixture {
  Invoke-AdminSql @"
DELETE FROM public.payment_refunds WHERE payment_id IN ('$payment'::uuid, '$paymentDup'::uuid);
DELETE FROM public.audit_logs WHERE resource_id IN ('$payment'::uuid, '$paymentDup'::uuid, '$pass'::uuid, '$passDup'::uuid, '$lessonFuture'::uuid);
DELETE FROM public.sms_notifications WHERE pass_id IN ('$pass'::uuid, '$passDup'::uuid);
DELETE FROM public.lessons WHERE pass_id IN ('$pass'::uuid, '$passDup'::uuid);
DELETE FROM public.schedule_slots WHERE pass_id IN ('$pass'::uuid, '$passDup'::uuid);
DELETE FROM public.payments WHERE id IN ('$payment'::uuid, '$paymentDup'::uuid);
DELETE FROM public.passes WHERE id IN ('$pass'::uuid, '$passDup'::uuid);
DELETE FROM public.students WHERE id IN ('$student'::uuid, '$studentDup'::uuid);
DELETE FROM public.course_products WHERE id = '$product'::uuid;
DELETE FROM public.courses WHERE id = '$course'::uuid;
DELETE FROM public.teachers WHERE id = '$teacherRow'::uuid;
DELETE FROM public.profiles WHERE id IN ('$owner'::uuid, '$teacher'::uuid);
DELETE FROM auth.users WHERE id IN ('$owner'::uuid, '$teacher'::uuid);
"@ | Out-Null
}

function Install-RefundFixture {
  Invoke-AdminSql @"
INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_user_meta_data, created_at, updated_at
) VALUES (
  '$owner'::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'owner-refund-conc@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()
);

INSERT INTO public.profiles (id, role, display_name, account_state)
VALUES ('$owner'::uuid, 'owner', 'Refund Concurrency Owner', 'active');

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_user_meta_data, created_at, updated_at
) VALUES (
  '$teacher'::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'teacher-refund-conc@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()
);

INSERT INTO public.profiles (id, role, display_name, account_state)
VALUES ('$teacher'::uuid, 'teacher', 'Refund Conc Teacher Profile', 'active');

INSERT INTO public.teachers (id, teacher_code, profile_id, name, is_active)
VALUES ('$teacherRow'::uuid, 'T-RC49', '$teacher'::uuid, 'Refund Conc Teacher', true);

INSERT INTO public.students (id, student_code, profile_id, name, operational_status)
VALUES
  ('$student'::uuid, 'S049', NULL, 'Refund Conc Student', 'active'),
  ('$studentDup'::uuid, 'S050', NULL, 'Refund Dup Student', 'active');

INSERT INTO public.courses (id, course_code, name, is_active)
VALUES ('$course'::uuid, 'VOC-RC49', 'Refund Conc Course', true);

INSERT INTO public.course_products (
  id, course_id, product_code, product_name,
  default_lesson_count, weekly_frequency, default_tuition_krw, is_active
) VALUES (
  '$product'::uuid, '$course'::uuid, 'VOC-4-RC49', 'Refund Conc Product', 4, 1, 200000, true
);

INSERT INTO public.passes (
  id, pass_code, student_id, course_id, course_product_id,
  sequence_number, status, registered_lesson_count_snapshot,
  weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
  start_date, activated_at
) VALUES
  (
    '$pass'::uuid, 'V-S049-A01', '$student'::uuid, '$course'::uuid, '$product'::uuid,
    1, 'active', 4, 1, 'Refund Conc Product', 200000,
    DATE '2026-08-01', now() - interval '90 days'
  ),
  (
    '$passDup'::uuid, 'V-S050-R01', '$studentDup'::uuid, '$course'::uuid, '$product'::uuid,
    1, 'reserved', 4, 1, 'Refund Conc Product', 200000,
    DATE '2026-10-01', NULL
  );

INSERT INTO public.schedule_slots (
  id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
  slot_order, is_active, effective_from
) VALUES (
  '$slot'::uuid, '$pass'::uuid, '$teacherRow'::uuid, 1, TIME '10:00', 60, 1, true, DATE '2026-08-01'
);

INSERT INTO public.lessons (
  id, pass_id, student_id, course_id, assigned_teacher_id, schedule_slot_id,
  sequence_number, scheduled_at, status, updated_at
) VALUES
  ('$lessonDone1'::uuid, '$pass'::uuid, '$student'::uuid, '$course'::uuid, '$teacherRow'::uuid, '$slot'::uuid,
    1, now() - interval '60 days', 'completed', now() - interval '60 days'),
  ('$lessonDone2'::uuid, '$pass'::uuid, '$student'::uuid, '$course'::uuid, '$teacherRow'::uuid, '$slot'::uuid,
    2, now() - interval '45 days', 'completed', now() - interval '45 days'),
  ('$lessonDone3'::uuid, '$pass'::uuid, '$student'::uuid, '$course'::uuid, '$teacherRow'::uuid, '$slot'::uuid,
    3, now() - interval '30 days', 'completed', now() - interval '30 days'),
  ('$lessonFuture'::uuid, '$pass'::uuid, '$student'::uuid, '$course'::uuid, '$teacherRow'::uuid, '$slot'::uuid,
    4, now() + interval '7 days', 'scheduled', now() - interval '30 days');

INSERT INTO public.lessons (
  id, pass_id, student_id, course_id, assigned_teacher_id,
  sequence_number, scheduled_at, status, updated_at
) VALUES
  (gen_random_uuid(), '$passDup'::uuid, '$studentDup'::uuid, '$course'::uuid, '$teacherRow'::uuid, 1, NULL, 'scheduled', now()),
  (gen_random_uuid(), '$passDup'::uuid, '$studentDup'::uuid, '$course'::uuid, '$teacherRow'::uuid, 2, NULL, 'scheduled', now()),
  (gen_random_uuid(), '$passDup'::uuid, '$studentDup'::uuid, '$course'::uuid, '$teacherRow'::uuid, 3, NULL, 'scheduled', now()),
  (gen_random_uuid(), '$passDup'::uuid, '$studentDup'::uuid, '$course'::uuid, '$teacherRow'::uuid, 4, NULL, 'scheduled', now());

INSERT INTO public.payments (
  id, student_id, course_id, course_product_id, related_pass_id, renewed_pass_id,
  paid_amount_krw, payment_method, status, paid_at, idempotency_key, processed_at
) VALUES
  (
    '$payment'::uuid, '$student'::uuid, '$course'::uuid, '$product'::uuid, NULL, '$pass'::uuid,
    200000, 'card', 'completed', now() - interval '80 days', 'refund-conc-key', now()
  ),
  (
    '$paymentDup'::uuid, '$studentDup'::uuid, '$course'::uuid, '$product'::uuid, NULL, '$passDup'::uuid,
    200000, 'card', 'completed', now() - interval '5 days', 'refund-dup-key', now()
  );

INSERT INTO public.sms_notifications (
  id, student_id, pass_id, notification_type, status, message_body_snapshot, target_date
) VALUES (
  gen_random_uuid(), '$student'::uuid, '$pass'::uuid, 'renewal_reminder', 'target',
  'Refund concurrency body', CURRENT_DATE + 7
);
"@ | Out-Null
}

function Invoke-OwnerRefund {
  param([string]$PaymentId, [string]$Label)
  $sql = @"
SELECT set_config('request.jwt.claim.sub', '$owner', false);
SELECT set_config('request.jwt.claim.role', 'authenticated', false);
SELECT pass_disposition::text FROM public.reve_process_payment_refund('$PaymentId'::uuid, 200000, 'Concurrency refund $Label');
"@
  $file = [System.IO.Path]::GetTempFileName()
  Set-Content -Path $file -Value $sql -Encoding UTF8
  docker cp $file "${container}:/tmp/refund_${Label}.sql" | Out-Null
  Remove-Item $file
  $output = docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -t -A -f "/tmp/refund_${Label}.sql" 2>&1 | Out-String
  return @{ Ok = ($LASTEXITCODE -eq 0); Output = $output.Trim() }
}

function Invoke-OwnerCompleteLesson {
  $sql = @"
SELECT set_config('request.jwt.claim.sub', '$owner', false);
SELECT set_config('request.jwt.claim.role', 'authenticated', false);
SELECT new_status::text FROM public.reve_transition_lesson_status(
  '$lessonFuture'::uuid,
  'completed',
  (SELECT updated_at FROM public.lessons WHERE id = '$lessonFuture'::uuid),
  now() - interval '1 hour',
  now(),
  'Concurrency complete'
);
"@
  $file = [System.IO.Path]::GetTempFileName()
  Set-Content -Path $file -Value $sql -Encoding UTF8
  docker cp $file "${container}:/tmp/refund_complete.sql" | Out-Null
  Remove-Item $file
  $result = docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -t -A -f /tmp/refund_complete.sql 2>&1
  return ($result | Out-String).Trim()
}

function Assert-NoHarnessObjects {
  $exists = (Invoke-AdminSql @"
SELECT EXISTS (
  SELECT 1 FROM pg_namespace WHERE nspname IN ('reve_test', '$runtimeSchema')
);
"@ -TuplesOnly).Trim()
  if ($exists -in @('t', 'true')) {
    throw 'Runtime or production test harness schema remains'
  }
}

$runtimeReady = $false
try {
  Write-Host 'Checking database reachability...'
  Test-DatabaseReachable

  Write-Host 'Initializing runtime harness...'
  Initialize-RuntimeHarness
  $runtimeReady = $true

  Write-Host 'Preparing refund concurrency fixture...'
  Install-RefundFixture

  Write-Host 'Scenario 1: refund versus lesson completion (RC-05)...'
  $rcJob = Start-Job -ScriptBlock {
    param($Container, $Owner, $Payment)
    $sql = @"
SELECT set_config('request.jwt.claim.sub', '$Owner', false);
SELECT set_config('request.jwt.claim.role', 'authenticated', false);
SELECT pass_disposition::text FROM public.reve_process_payment_refund('$Payment'::uuid, 200000, 'RC05 refund');
"@
    $file = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $file -Value $sql -Encoding UTF8
    docker cp $file "${Container}:/tmp/refund_rc05.sql" | Out-Null
    Remove-Item $file
    docker exec -i $Container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -t -A -f /tmp/refund_rc05.sql 2>&1
  } -ArgumentList $container, $owner, $payment

  Start-Sleep -Milliseconds 150
  $completeResult = Invoke-OwnerCompleteLesson
  $rcRemoteRaw = Receive-Job -Job $rcJob -Wait -AutoRemoveJob
  $rcRemote = ($rcRemoteRaw | Out-String).Trim()

  $refundRows = (Invoke-AdminSql "SELECT count(*) FROM public.payment_refunds WHERE payment_id = '$payment'::uuid;" -TuplesOnly).Trim()
  $passStatus = (Invoke-AdminSql "SELECT status FROM public.passes WHERE id = '$pass'::uuid;" -TuplesOnly).Trim()
  $paymentStatus = (Invoke-AdminSql "SELECT status FROM public.payments WHERE id = '$payment'::uuid;" -TuplesOnly).Trim()
  $futureStatus = (Invoke-AdminSql "SELECT status FROM public.lessons WHERE id = '$lessonFuture'::uuid;" -TuplesOnly).Trim()

  $refundWon = ($refundRows -eq '1' -and $passStatus -eq 'cancelled' -and $paymentStatus -eq 'refunded')
  $completeWon = ($refundRows -eq '0' -and $futureStatus -eq 'completed' -and $passStatus -in @('active', 'completed'))

  if (-not ($refundWon -xor $completeWon)) {
    throw "RC-05 ambiguous outcome: refundRows=$refundRows pass=$passStatus payment=$paymentStatus lesson=$futureStatus complete=$completeResult remote=$rcRemote"
  }

  Invoke-AdminSql @"
INSERT INTO $runtimeSchema.refund_session_results (scenario, outcome, detail)
VALUES (
  'refund_vs_complete',
  CASE WHEN '$refundRows' = '1' THEN 'refund_won' ELSE 'complete_won' END,
  'refund_rows=$refundRows pass=$passStatus lesson=$futureStatus'
);
"@ | Out-Null

  Write-Host 'Scenario 2: duplicate refund attempts on same payment...'
  $dupJob = Start-Job -ScriptBlock {
    param($Container, $Owner, $PaymentDup)
    $sql = @"
SELECT set_config('request.jwt.claim.sub', '$Owner', false);
SELECT set_config('request.jwt.claim.role', 'authenticated', false);
SELECT pass_disposition::text FROM public.reve_process_payment_refund('$PaymentDup'::uuid, 200000, 'Duplicate A');
"@
    $file = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $file -Value $sql -Encoding UTF8
    docker cp $file "${Container}:/tmp/refund_dup_a.sql" | Out-Null
    Remove-Item $file
    docker exec -i $Container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -t -A -f /tmp/refund_dup_a.sql 2>&1
  } -ArgumentList $container, $owner, $paymentDup

  Start-Sleep -Milliseconds 150
  $dupLocal = Invoke-OwnerRefund -PaymentId $paymentDup -Label 'dup_b'
  $dupRemoteRaw = Receive-Job -Job $dupJob -Wait -AutoRemoveJob
  $dupRemote = ($dupRemoteRaw | Out-String).Trim()

  $dupRefundCount = (Invoke-AdminSql "SELECT count(*) FROM public.payment_refunds WHERE payment_id = '$paymentDup'::uuid;" -TuplesOnly).Trim()
  $dupSuccessCount = 0
  if ($dupLocal.Output -match 'reserved_cancelled') { $dupSuccessCount++ }
  if ($dupRemote -match 'reserved_cancelled') { $dupSuccessCount++ }

  if ($dupRefundCount -ne '1') {
    throw "Expected exactly one duplicate-scenario refund row, got $dupRefundCount (local=$($dupLocal.Output) remote=$dupRemote)"
  }
  if ($dupSuccessCount -ne 1) {
    throw "Expected exactly one successful duplicate refund attempt, localOk=$($dupLocal.Ok) local=$($dupLocal.Output) remote=$dupRemote"
  }

  Invoke-AdminSql @"
INSERT INTO $runtimeSchema.refund_session_results (scenario, outcome, detail)
VALUES ('duplicate_refund', 'pass', 'refund_rows=$dupRefundCount');
"@ | Out-Null

  Write-Host 'Running dedicated concurrency pgTAP assertions...'
  Push-Location $repoRoot
  npx supabase test db scripts/concurrency/owner_payment_refund_concurrency.test.sql
  if ($LASTEXITCODE -ne 0) {
    throw "Refund concurrency pgTAP failed with exit code $LASTEXITCODE"
  }
  Pop-Location

  Write-Host "Refund concurrency verification passed: duplicate_refund_rows=$dupRefundCount RC-05 refundRows=$refundRows pass=$passStatus"
}
finally {
  if ($runtimeReady) {
    Write-Host 'Cleaning up runtime harness...'
    Remove-RuntimeHarness
  }
  Assert-NoHarnessObjects
}
