import {
  DOWNLOAD_EXPIRY,
  downloadInput,
  HttpDependencies,
  lessonKeys,
  storageHttp,
} from '../_shared/storage.ts';
export interface DownloadDependencies extends HttpDependencies {
  sign(
    keys: string[],
    expiresIn: number,
  ): Promise<Record<string, string> | null>;
}
export function downloadHandler(deps: DownloadDependencies) {
  return storageHttp(deps, async (req, current, reply) => {
    const lessonId = downloadInput(await req.json());
    // Query each requested lesson under the verified caller's JWT/RLS before signing any key.
    const lesson = await current.lesson(lessonId);
    if (!lesson) return reply({ error: 'Forbidden' }, 403);
    const keys = lessonKeys(lesson);
    const urls = await deps.sign(keys, DOWNLOAD_EXPIRY);
    if (!urls) return reply({ error: 'Storage not configured' }, 503);
    return reply({ urls });
  });
}
