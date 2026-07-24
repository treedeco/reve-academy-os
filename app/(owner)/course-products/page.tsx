import { CourseProductsPanel } from '@/components/owner/course-products-panel';
import { ErrorState } from '@/components/ui/state-blocks';
import {
  fetchOwnerActiveCourses,
  fetchOwnerCourseProductList,
} from '@/lib/data/owner-course-products';
import { createClient } from '@/lib/supabase/server';

export default async function OwnerCourseProductsPage() {
  const supabase = await createClient();

  try {
    const [products, activeCourses] = await Promise.all([
      fetchOwnerCourseProductList(supabase),
      fetchOwnerActiveCourses(supabase),
    ]);

    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">수강 상품</h1>
          <p className="mt-1 text-sm text-slate-600">
            과목별 수강 상품을 등록하고 수정합니다. 초기 등록 화면에서는 활성 상품만 선택할 수
            있습니다.
          </p>
        </div>

        <CourseProductsPanel initialProducts={products} activeCourses={activeCourses} />
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}
