import { BaseSequencer, type TestSpecification } from 'vitest/node';

const integrationOrder = [
  'owner-lesson-operations.test.ts',
  'owner-queries.test.ts',
];

function integrationRank(moduleId: string): number {
  const index = integrationOrder.findIndex((name) => moduleId.replace(/\\/g, '/').includes(name));
  return index === -1 ? integrationOrder.length : index;
}

export default class ReveIntegrationSequencer extends BaseSequencer {
  async sort(files: TestSpecification[]): Promise<TestSpecification[]> {
    return [...files].sort((a, b) => {
      const rankDiff = integrationRank(a.moduleId) - integrationRank(b.moduleId);
      if (rankDiff !== 0) {
        return rankDiff;
      }
      return a.moduleId.localeCompare(b.moduleId);
    });
  }
}
