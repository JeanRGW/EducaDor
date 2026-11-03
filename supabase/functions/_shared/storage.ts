export const MAX_UPLOAD_SIZE = 50 * 1024 * 1024;
export const UPLOAD_EXPIRY = 900;
export const DOWNLOAD_EXPIRY = 3600;
const types: Record<string, string> = {
  'application/pdf': 'pdf',
  'audio/mpeg': 'mp3',
  'image/gif': 'gif',
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/webp': 'webp',
};
function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('Invalid payload');
  }
  return value as Record<string, unknown>;
}
export function uploadInput(value: unknown) {
  const { prefix, contentType, size } = object(value);
  if (
    typeof contentType !== 'string' || !Object.hasOwn(types, contentType) ||
    !(prefix === 'lessons' ||
      (prefix === 'covers' && contentType === 'image/webp')) ||
    typeof size !== 'number' || !Number.isInteger(size) || size < 1 ||
    size > MAX_UPLOAD_SIZE
  ) {
    throw new Error('Invalid upload');
  }
  return { prefix, contentType, size, extension: types[contentType] };
}
export function downloadInput(value: unknown): string {
  const { lessonId } = object(value);
  if (
    typeof lessonId !== 'string' ||
    !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(lessonId)
  ) {
    throw new Error('Invalid lesson');
  }
  return lessonId;
}
export type LessonFiles = { file_key: unknown; image_keys: unknown };
export function lessonKeys(lesson: LessonFiles): string[] {
  if (lesson.image_keys != null && !Array.isArray(lesson.image_keys)) {
    throw new Error('Invalid frames');
  }
  const keys: unknown[] = [
    ...(lesson.file_key == null ? [] : [lesson.file_key]),
    ...(lesson.image_keys as unknown[] | null ?? []),
  ];
  if (
    keys.length > 100 || keys.some((key) =>
      typeof key !== 'string' ||
      key.length > 256 ||
      !/^lessons\/[a-f0-9-]{36}\.(pdf|mp3|gif|png|jpg|webp)$/.test(key)
    )
  ) {
    throw new Error('Invalid files');
  }
  return [...new Set(keys as string[])];
}
export interface StorageCaller {
  isGestor(): Promise<boolean>;
  // Must use the verified caller JWT, never a service-role client.
  lesson(id: string): Promise<LessonFiles | null>;
}
export interface HttpDependencies {
  origins: string[];
  authenticate(req: Request): Promise<StorageCaller | null>;
}
export function storageHttp(
  deps: HttpDependencies,
  action: (
    req: Request,
    caller: StorageCaller,
    reply: (body: unknown, status?: number) => Response,
  ) => Promise<Response>,
) {
  return async (req: Request): Promise<Response> => {
    const origin = req.headers.get('origin');
    const allowed = origin !== null && deps.origins.includes(origin);
    const reply = (body: unknown, status = 200) =>
      new Response(status === 204 ? null : JSON.stringify(body), {
        status,
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'no-store',
          Vary: 'Origin',
          ...(allowed
            ? {
              'Access-Control-Allow-Origin': origin,
              'Access-Control-Allow-Headers':
                'authorization, x-client-info, apikey, content-type',
              'Access-Control-Allow-Methods': 'POST, OPTIONS',
            }
            : {}),
        },
      });
    if (req.method === 'OPTIONS') return reply({}, 204);
    if (req.method !== 'POST' || (origin && !allowed)) {
      return reply({ error: 'Forbidden' }, 403);
    }
    try {
      const current = await deps.authenticate(req);
      if (!current) return reply({ error: 'Authentication required' }, 401);
      return await action(req, current, reply);
    } catch {
      return reply({ error: 'Invalid request' }, 400);
    }
  };
}
