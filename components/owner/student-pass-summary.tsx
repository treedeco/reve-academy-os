import type { PassUsageSummary } from '@/lib/domain/types';
import { formatDateTimeSeoul } from '@/lib/domain/format';

export function StudentPassSummary({ pass }: { pass: PassUsageSummary }) {
  return (
    <dl className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <div>
        <dt className="text-sm text-slate-500">Pass 코드</dt>
        <dd className="font-medium">{pass.pass_code}</dd>
      </div>
      <div>
        <dt className="text-sm text-slate-500">등록 회차</dt>
        <dd className="font-medium">{pass.registered_lesson_count}</dd>
      </div>
      <div>
        <dt className="text-sm text-slate-500">사용</dt>
        <dd className="font-medium" data-testid="used-count">
          {pass.used_lesson_count}
        </dd>
      </div>
      <div>
        <dt className="text-sm text-slate-500">잔여</dt>
        <dd className="font-medium" data-testid="remaining-count">
          {pass.remaining_lesson_count}
        </dd>
      </div>
      <div className="sm:col-span-2">
        <dt className="text-sm text-slate-500">다음 수업</dt>
        <dd className="font-medium">
          {pass.next_lesson_at ? formatDateTimeSeoul(pass.next_lesson_at) : '-'}
        </dd>
      </div>
    </dl>
  );
}
