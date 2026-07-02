import { Suspense } from 'react';
import LoginForm from './login-form';

export default function LoginPage() {
  return (
    <Suspense fallback={<div className="flex min-h-screen items-center justify-center">로딩 중…</div>}>
      <LoginForm />
    </Suspense>
  );
}
