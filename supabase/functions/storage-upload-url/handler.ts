import {
  HttpDependencies,
  storageHttp,
  UPLOAD_EXPIRY,
  uploadInput,
} from '../_shared/storage.ts';
export interface UploadDependencies extends HttpDependencies {
  uuid(): string;
  sign(
    input: {
      key: string;
      contentType: string;
      size: number;
      public: boolean;
      expiresIn: number;
    },
  ): Promise<{ putUrl: string; publicUrl?: string } | null>;
}
export function uploadHandler(deps: UploadDependencies) {
  return storageHttp(deps, async (req, current, reply) => {
    if (!await current.isGestor()) return reply({ error: 'Forbidden' }, 403);
    const input = uploadInput(await req.json());
    const key = `${input.prefix}/${deps.uuid()}.${input.extension}`;
    const signed = await deps.sign({
      key,
      contentType: input.contentType,
      size: input.size,
      public: input.prefix === 'covers',
      expiresIn: UPLOAD_EXPIRY,
    });
    if (!signed) return reply({ error: 'Storage upload not configured' }, 503);
    return reply({ key, ...signed });
  });
}
