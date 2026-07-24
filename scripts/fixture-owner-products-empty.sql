-- Local E2E only: remove all course products for empty-catalog UI tests.
-- Alpha fixture products are restored by seed-owner-alpha.sql.

BEGIN;

DELETE FROM public.course_products;

COMMIT;
