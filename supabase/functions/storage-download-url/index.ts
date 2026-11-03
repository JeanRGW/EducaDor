import { storageAuth } from '../_shared/storage_runtime.ts';
import { signGet, storageConfig } from '../_shared/storage_s3.ts';
import { downloadHandler } from './handler.ts';
Deno.serve(downloadHandler({
  ...storageAuth,
  async sign(keys, expiresIn) {
    const config = storageConfig(false);
    if (!config) return null;
    const { s3, bucket } = config;
    return Object.fromEntries(
      await Promise.all(
        keys.map(async (
          key,
        ) => [key, await signGet(s3, bucket, key, expiresIn)]),
      ),
    );
  },
}));
