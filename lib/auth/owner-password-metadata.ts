export const OWNER_MUST_CHANGE_PASSWORD_METADATA_KEY = 'must_change_password';

export function ownerMustChangePassword(
  metadata: Record<string, unknown> | null | undefined,
): boolean {
  return metadata?.[OWNER_MUST_CHANGE_PASSWORD_METADATA_KEY] === true;
}

export function buildPasswordChangeCompletedMetadata(
  metadata: Record<string, unknown> | null | undefined,
): Record<string, unknown> {
  return {
    ...(metadata ?? {}),
    [OWNER_MUST_CHANGE_PASSWORD_METADATA_KEY]: false,
  };
}
