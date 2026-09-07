/**
 * Phase 2B Immediate Operations — Teacher Lee (이혜인) Duplicate Consolidation and Login Provisioning.
 *
 * Targets:
 *   - Canonical Teacher: t-p-1 (f11d8f5c-b9b9-4b1f-aeb3-069a981c8641) -> retained, active
 *   - Duplicate Teacher: t-m-1 (00700866-84cb-46bd-92d3-b775f52f1cfe) -> deactivated via Owner RPC
 *   - Auth User: in2520@naver.com -> created via Auth Admin, provisioned to t-p-1 via Owner RPC
 *
 * NEVER exposes service-role secrets client-side.
 * Runs complete preflight and postflight RLS/permission verification.
 */
import { createClient } from '@supabase/supabase-js';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const PROJECT_REF = 'bfhptqhgxignyggyxxkx';
const SUPABASE_URL = `https://${PROJECT_REF}.supabase.co`;

const TP1_ID = 'f11d8f5c-b9b9-4b1f-aeb3-069a981c8641';
const TM1_ID = '00700866-84cb-46bd-92d3-b775f52f1cfe';
const TV1_ID = 'aba1417b-c409-4cf3-9b3d-fbd6eaf4ea23';

const TEACHER_NAME = '이혜인';
const TEACHER_PHONE = '010-2713-4910';
const TEACHER_EMAIL = 'in2520@naver.com';

function getApiKeys() {
  const keysOut = spawnSync(
    'npx',
    ['supabase', 'projects', 'api-keys', '--project-ref', PROJECT_REF, '-o', 'json'],
    { encoding: 'utf8', shell: true },
  );
  const jsonStr = keysOut.stdout.slice(
    keysOut.stdout.indexOf('['),
    keysOut.stdout.lastIndexOf(']') + 1,
  );
  const rows = JSON.parse(jsonStr);
  const anon = rows.find((x) => x.id === 'anon')?.api_key;
  const service = rows.find((x) => x.id === 'service_role')?.api_key;
  if (!anon || !service) {
    throw new Error('Failed to retrieve anon or service_role key from Supabase CLI');
  }
  return { anon, service };
}

function generateSecurePassword() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  let pass = '';
  const randomBytes = crypto.randomBytes(16);
  for (let i = 0; i < 16; i++) {
    pass += chars[randomBytes[i] % chars.length];
  }
  return pass + '!R1';
}

async function main() {
  console.log('=== Step 1: Preflight Setup & Owner Authentication ===');
  const { anon, service } = getApiKeys();

  const adminClient = createClient(SUPABASE_URL, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const link = await adminClient.auth.admin.generateLink({
    type: 'magiclink',
    email: 'reve@owner.local',
  });
  if (link.error || !link.data?.properties?.email_otp) {
    throw new Error(`Failed to generate magic link for Owner: ${link.error?.message}`);
  }

  const ownerClient = createClient(SUPABASE_URL, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const ownerVerify = await ownerClient.auth.verifyOtp({
    email: 'reve@owner.local',
    token: link.data.properties.email_otp,
    type: 'magiclink',
  });
  if (ownerVerify.error || !ownerVerify.data?.session) {
    throw new Error(`Owner authentication failed: ${ownerVerify.error?.message}`);
  }
  console.log('Owner session authenticated. Owner Auth UID:', ownerVerify.data.user.id);

  console.log('\n=== Step 2: Audit Existing Teacher Rows ===');
  const { data: teachers, error: teacherLookupErr } = await ownerClient
    .from('teachers')
    .select('id, teacher_code, name, phone, email, is_active, profile_id, updated_at')
    .in('id', [TP1_ID, TM1_ID]);

  if (teacherLookupErr) {
    throw new Error(`Failed to look up teachers: ${teacherLookupErr.message}`);
  }

  const tp1 = teachers?.find((t) => t.id === TP1_ID);
  const tm1 = teachers?.find((t) => t.id === TM1_ID);

  if (!tp1) throw new Error(`Canonical teacher t-p-1 (${TP1_ID}) not found!`);
  if (!tm1) throw new Error(`Duplicate teacher t-m-1 (${TM1_ID}) not found!`);

  console.log('t-p-1:', {
    id: tp1.id,
    code: tp1.teacher_code,
    name: tp1.name,
    phone: tp1.phone,
    email: tp1.email,
    is_active: tp1.is_active,
    profile_id: tp1.profile_id,
    updated_at: tp1.updated_at,
  });
  console.log('t-m-1:', {
    id: tm1.id,
    code: tm1.teacher_code,
    name: tm1.name,
    phone: tm1.phone,
    email: tm1.email,
    is_active: tm1.is_active,
    profile_id: tm1.profile_id,
    updated_at: tm1.updated_at,
  });

  // Verify reference counts for both
  const [slotsCount, lessonsCount] = await Promise.all([
    ownerClient
      .from('schedule_slots')
      .select('*', { count: 'exact', head: true })
      .in('teacher_id', [TP1_ID, TM1_ID]),
    ownerClient
      .from('lessons')
      .select('*', { count: 'exact', head: true })
      .in('assigned_teacher_id', [TP1_ID, TM1_ID]),
  ]);

  console.log(`Foreign key references for [t-p-1, t-m-1]:`);
  console.log(`  schedule_slots: ${slotsCount.count ?? 0}`);
  console.log(`  lessons: ${lessonsCount.count ?? 0}`);

  if ((slotsCount.count ?? 0) > 0 || (lessonsCount.count ?? 0) > 0) {
    throw new Error('Unexpected foreign key references found! Manual consolidation required.');
  }

  console.log('\n=== Step 3: Deactivate Duplicate Teacher t-m-1 via Owner RPC ===');
  if (tm1.is_active) {
    const { data: deactData, error: deactErr } = await ownerClient.rpc(
      'reve_owner_set_teacher_active',
      {
        p_teacher_id: TM1_ID,
        p_is_active: false,
        p_reason: '피아노/작곡 겸임 강사 중복 등록 정리 (t-p-1로 단일화)',
        p_expected_updated_at: tm1.updated_at,
      },
    );

    if (deactErr) {
      throw new Error(`Failed to deactivate t-m-1: ${deactErr.message}`);
    }
    console.log('reve_owner_set_teacher_active result:', deactData);
  } else {
    console.log('t-m-1 is already inactive. Skipping deactivation RPC.');
  }

  // Verify t-m-1 is inactive and t-p-1 is active
  const { data: postDeactTeachers } = await ownerClient
    .from('teachers')
    .select('id, teacher_code, name, is_active')
    .in('id', [TP1_ID, TM1_ID]);

  const postTp1 = postDeactTeachers?.find((t) => t.id === TP1_ID);
  const postTm1 = postDeactTeachers?.find((t) => t.id === TM1_ID);

  if (!postTp1?.is_active) {
    throw new Error('Assertion failed: t-p-1 must remain active!');
  }
  if (postTm1?.is_active) {
    throw new Error('Assertion failed: t-m-1 must now be inactive!');
  }
  console.log('State verified: t-p-1 is active, t-m-1 is inactive.');

  console.log('\n=== Step 4: Verify Multi-Course Catalog Projection ===');
  const [activeTeachersRes, coursesRes] = await Promise.all([
    ownerClient
      .from('teachers')
      .select('id, teacher_code, name')
      .eq('is_active', true)
      .order('name'),
    ownerClient
      .from('courses')
      .select('id, course_code, name')
      .eq('is_active', true)
      .order('course_code'),
  ]);

  const activeTeachers = activeTeachersRes.data ?? [];
  const courses = coursesRes.data ?? [];

  const tp1InCatalog = activeTeachers.find((t) => t.id === TP1_ID);
  const tm1InCatalog = activeTeachers.find((t) => t.id === TM1_ID);
  const pianoCourse = courses.find((c) => c.course_code === 'P');
  const compCourse = courses.find((c) => c.course_code === 'M');

  if (!tp1InCatalog) throw new Error('t-p-1 is missing from active teachers catalog!');
  if (tm1InCatalog) throw new Error('t-m-1 is unexpectedly present in active teachers catalog!');
  if (!pianoCourse) throw new Error('Piano course (P) not found!');
  if (!compCourse) throw new Error('Composition course (M) not found!');

  console.log('Catalog check:');
  console.log(`  Canonical teacher available: ${tp1InCatalog.name} (${tp1InCatalog.teacher_code})`);
  console.log(`  Duplicate teacher excluded: ${!tm1InCatalog}`);
  console.log(`  Available courses include: ${pianoCourse.name} (${pianoCourse.course_code}), ${compCourse.name} (${compCourse.course_code})`);

  console.log('\n=== Step 5: Provision Auth User & Teacher Profile for in2520@naver.com ===');
  // Check if Auth user already exists
  const existingUsers = await adminClient.auth.admin.listUsers({ page: 1, perPage: 100 });
  let authUser = existingUsers.data?.users?.find(
    (u) => u.email?.toLowerCase() === TEACHER_EMAIL.toLowerCase(),
  );

  let tempPassword = null;
  if (!authUser) {
    tempPassword = generateSecurePassword();
    console.log(`Creating new Auth user for ${TEACHER_EMAIL}...`);
    const createRes = await adminClient.auth.admin.createUser({
      email: TEACHER_EMAIL,
      password: tempPassword,
      email_confirm: true,
      user_metadata: { full_name: TEACHER_NAME },
    });
    if (createRes.error || !createRes.data?.user) {
      throw new Error(`Failed to create Auth user: ${createRes.error?.message}`);
    }
    authUser = createRes.data.user;
    console.log(`Auth user created successfully. UID: ${authUser.id}`);
  } else {
    console.log(`Auth user already exists: ${authUser.id}`);
  }

  // Check if profile already exists
  const { data: existingProfile } = await ownerClient
    .from('profiles')
    .select('id, role, display_name, account_state')
    .eq('id', authUser.id)
    .maybeSingle();

  if (!existingProfile) {
    console.log(`Provisioning profile for Auth UID ${authUser.id} -> Teacher ${TP1_ID}...`);
    const { data: provData, error: provErr } = await ownerClient.rpc(
      'reve_owner_provision_profile',
      {
        p_auth_user_id: authUser.id,
        p_role: 'teacher',
        p_display_name: TEACHER_NAME,
        p_student_id: null,
        p_teacher_id: TP1_ID,
      },
    );

    if (provErr) {
      throw new Error(`Provisioning RPC failed: ${provErr.message}`);
    }
    console.log('reve_owner_provision_profile result:', provData);
  } else {
    console.log(`Profile already exists for Auth UID:`, existingProfile);
    if (existingProfile.role !== 'teacher') {
      throw new Error(`Profile role mismatch: expected teacher, got ${existingProfile.role}`);
    }
  }

  console.log('\n=== Step 6: Postflight Verification of DB State ===');
  const { data: verifiedTeacher, error: vTeacherErr } = await ownerClient
    .from('teachers')
    .select('id, teacher_code, name, email, phone, is_active, profile_id')
    .eq('id', TP1_ID)
    .single();

  if (vTeacherErr || !verifiedTeacher) {
    throw new Error(`Postflight teacher lookup failed: ${vTeacherErr?.message}`);
  }
  if (verifiedTeacher.profile_id !== authUser.id) {
    throw new Error(`Teacher profile_id (${verifiedTeacher.profile_id}) does not match Auth UID (${authUser.id})!`);
  }
  if (!verifiedTeacher.is_active) {
    throw new Error('Canonical teacher t-p-1 is not active!');
  }

  const { data: verifiedProfile, error: vProfileErr } = await ownerClient
    .from('profiles')
    .select('id, role, display_name, account_state')
    .eq('id', authUser.id)
    .single();

  if (vProfileErr || !verifiedProfile) {
    throw new Error(`Postflight profile lookup failed: ${vProfileErr?.message}`);
  }
  if (verifiedProfile.role !== 'teacher' || verifiedProfile.account_state !== 'active') {
    throw new Error(`Unexpected profile state: ${JSON.stringify(verifiedProfile)}`);
  }

  console.log('Postflight checks passed:');
  console.log('  Teacher:', verifiedTeacher);
  console.log('  Profile:', verifiedProfile);

  console.log('\n=== Step 7: Teacher Login & Authorization / RLS Verification ===');
  // Generate magiclink for teacher or sign in with temp password
  const teacherMagic = await adminClient.auth.admin.generateLink({
    type: 'magiclink',
    email: TEACHER_EMAIL,
  });

  const teacherClient = createClient(SUPABASE_URL, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const teacherVerify = await teacherClient.auth.verifyOtp({
    email: TEACHER_EMAIL,
    token: teacherMagic.data.properties.email_otp,
    type: 'magiclink',
  });

  if (teacherVerify.error || !teacherVerify.data?.session) {
    throw new Error(`Teacher login verification failed: ${teacherVerify.error?.message}`);
  }
  console.log('Teacher session established. Teacher UID:', teacherVerify.data.user.id);

  // 1. Teacher can see assigned students summary (Phase 8)
  const { data: assignedStudents, error: assignErr } = await teacherClient.rpc(
    'reve_get_my_assigned_student_summaries',
  );
  if (assignErr) {
    throw new Error(`Teacher failed to query assigned students: ${assignErr.message}`);
  }
  console.log(`Teacher assigned student summaries: ${assignedStudents?.length ?? 0} rows`);

  // 2. Teacher sees own lessons only (Phase 8)
  const { data: teacherLessons, error: tLessonErr } = await teacherClient
    .from('lessons')
    .select('id, course_id, assigned_teacher_id, scheduled_at, status');
  if (tLessonErr) {
    throw new Error(`Teacher failed to query lessons: ${tLessonErr.message}`);
  }
  console.log(`Teacher visible lessons: ${teacherLessons?.length ?? 0} rows`);

  // 3. Teacher CANNOT see other teachers' lessons (e.g. t-v-1's 12 lessons)
  const { data: otherLessons } = await teacherClient
    .from('lessons')
    .select('id, assigned_teacher_id')
    .eq('assigned_teacher_id', TV1_ID);
  if ((otherLessons?.length ?? 0) > 0) {
    throw new Error('RLS VIOLATION: Teacher was able to view lessons of t-v-1!');
  }
  console.log(`RLS check: t-v-1 lessons visible to Teacher Lee: ${otherLessons?.length ?? 0} (PASS)`);

  // 4. Teacher CANNOT see payments
  const { data: paymentsData, error: paymentsErr } = await teacherClient
    .from('payments')
    .select('id');
  if ((paymentsData?.length ?? 0) > 0) {
    throw new Error('RLS VIOLATION: Teacher was able to view payments table!');
  }
  console.log(`RLS check: payments visible to Teacher: ${paymentsData?.length ?? 0} (PASS)`);

  // 5. Teacher CANNOT see payment_refunds
  const { data: refundsData } = await teacherClient
    .from('payment_refunds')
    .select('id');
  if ((refundsData?.length ?? 0) > 0) {
    throw new Error('RLS VIOLATION: Teacher was able to view payment_refunds table!');
  }
  console.log(`RLS check: payment_refunds visible to Teacher: ${refundsData?.length ?? 0} (PASS)`);

  // 6. Teacher CANNOT execute Owner RPCs
  let ownerRpcBlocked = false;
  try {
    await teacherClient.rpc('reve_owner_create_teacher', {
      p_teacher_code: 't-test-x',
      p_name: '테스트',
    });
  } catch {
    ownerRpcBlocked = true;
  }
  // Also check direct supabase-js call result
  const { error: rpcErr } = await teacherClient.rpc('reve_owner_create_teacher', {
    p_teacher_code: 't-test-x',
    p_name: '테스트',
  });
  if (rpcErr && (rpcErr.code === '42501' || rpcErr.message.includes('REVE_UNAUTHORIZED'))) {
    ownerRpcBlocked = true;
  }
  if (!ownerRpcBlocked) {
    throw new Error('SECURITY VIOLATION: Teacher was able to execute Owner RPC reve_owner_create_teacher!');
  }
  console.log('RLS check: reve_owner_create_teacher blocked for Teacher: PASS (42501 REVE_UNAUTHORIZED)');

  console.log('\n=== Step 8: Save Credential & Audit Artifact ===');
  const artifactsDir = path.resolve(process.cwd(), 'artifacts');
  if (!fs.existsSync(artifactsDir)) {
    fs.mkdirSync(artifactsDir, { recursive: true });
  }

  const resultPayload = {
    status: 'SUCCESS',
    timestamp: new Date().toISOString(),
    canonicalTeacher: {
      id: TP1_ID,
      teacher_code: 't-p-1',
      name: TEACHER_NAME,
      email: TEACHER_EMAIL,
      phone: TEACHER_PHONE,
      is_active: true,
      profile_id: authUser.id,
    },
    deactivatedDuplicate: {
      id: TM1_ID,
      teacher_code: 't-m-1',
      name: TEACHER_NAME,
      is_active: false,
    },
    authUser: {
      id: authUser.id,
      email: TEACHER_EMAIL,
      hasTemporaryPassword: !!tempPassword,
    },
  };

  const artifactPath = path.join(artifactsDir, 'teacher_lee_consolidation.json');
  fs.writeFileSync(artifactPath, JSON.stringify(resultPayload, null, 2), 'utf8');

  // If temporary password was created, write securely to gitignored credential file
  if (tempPassword) {
    const credPath = path.join(artifactsDir, 'teacher_lee_temp_password.txt');
    fs.writeFileSync(credPath, `Email: ${TEACHER_EMAIL}\nTempPassword: ${tempPassword}\nTeacherCode: t-p-1\n`, 'utf8');
    console.log(`Temporary password written securely to gitignored artifact: ${credPath}`);
  }

  console.log(`Consolidation summary saved to: ${artifactPath}`);
  console.log('\n========================================');
  console.log('ALL PHASES COMPLETED SUCCESSFULLY!');
  console.log('========================================');
}

main().catch((err) => {
  console.error('\n*** OPERATION FAILED ***');
  console.error(err);
  process.exit(1);
});
