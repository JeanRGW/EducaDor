import { storageAuth } from '../_shared/storage_runtime.ts';
import { signPut, storageConfig } from '../_shared/storage_s3.ts';
import { uploadHandler } from './handler.ts';
Deno.serve(uploadHandler({
  ...storageAuth,
  uuid: () => crypto.randomUUID(),
  async sign(input) {
    const config = storageConfig(input.public);
    const publicBase = Deno.env.get('SUPABASE_URL');
    if (!config || (input.public && !publicBase)) return null;
    const { s3, bucket } = config;
    const putUrl = await signPut(
      s3,
      bucket,
      input.key,
      input.contentType,
      input.size,
      input.expiresIn,
    );
    return {
      putUrl,
      ...(input.public
        ? {
          publicUrl:
            `${publicBase}/storage/v1/object/public/${bucket}/${input.key}`,
        }
        : {}),
    };
  },
}));
