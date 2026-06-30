# Phase 0B-3B-2B-3D-3B — SMS sent confirmation concurrency verification
# Run after the main pgTAP suite and before phase_0b3b2b3d3b_z_owner_sms_concurrency.test.sql

$ErrorActionPreference = 'Stop'

$container = 'supabase_db_reve-academy-os'
$owner = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa039'
$sms = '88888888-8888-8888-8888-888888888039'
$pass = '66666666-6666-6666-6666-666666666039'
$student = '44444444-4444-4444-4444-444444444039'
$course = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee39'
$product = 'ffffffff-ffff-ffff-ffff-ffffffffff39'

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

Write-Host 'Preparing concurrency fixture...'
Invoke-AdminSql @"
DELETE FROM reve_test.concurrency_assertions WHERE test_name = 'sms_confirm_concurrency';
DELETE FROM public.sms_notifications WHERE id = '$sms'::uuid;
DELETE FROM public.passes WHERE id = '$pass'::uuid;
DELETE FROM public.students WHERE id = '$student'::uuid;
DELETE FROM public.course_products WHERE id = '$product'::uuid;
DELETE FROM public.courses WHERE id = '$course'::uuid;
DELETE FROM public.profiles WHERE id = '$owner'::uuid;
DELETE FROM auth.users WHERE id = '$owner'::uuid;

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

Write-Host "Local no_change: $localResult"
Write-Host "Remote no_change: $remoteResult"

$auditCount = (Invoke-AdminSql "SELECT count(*) FROM public.audit_logs WHERE action = 'sms_notification.sent_confirmed' AND resource_id = '$sms'::uuid;" -TuplesOnly).Trim()
$status = (Invoke-AdminSql "SELECT status FROM public.sms_notifications WHERE id = '$sms'::uuid;" -TuplesOnly).Trim()

$localNoChange = $localResult -in @('t', 'true')
$localFirstTransition = $localResult -in @('f', 'false')
$remoteNoChange = $remoteResult -in @('t', 'true')
$remoteFirstTransition = $remoteResult -in @('f', 'false')

$passed = ($auditCount -eq '1') -and ($status -eq 'sent') -and (
  ($localFirstTransition -and $remoteNoChange) -or ($remoteFirstTransition -and $localNoChange)
)
$detail = "audit=$auditCount status=$status local=$localResult remote=$remoteResult"
$detailSql = $detail.Replace("'", "''")

Invoke-AdminSql "INSERT INTO reve_test.concurrency_assertions (test_name, passed, detail) VALUES ('sms_confirm_concurrency', $($passed.ToString().ToLower()), '$detailSql') ON CONFLICT (test_name) DO UPDATE SET passed = EXCLUDED.passed, detail = EXCLUDED.detail, checked_at = now();"

if (-not $passed) {
  Write-Error "SMS concurrency verification failed: $detail"
}

Write-Host "SMS concurrency verification passed: $detail"
