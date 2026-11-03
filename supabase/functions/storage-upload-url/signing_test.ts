import { S3Client, signGet, signPut } from '../_shared/storage_s3.ts';
function assert(ok: unknown): asserts ok {
  if (!ok) throw new Error('Assertion failed');
}
const key = 'lessons/12345678-1234-1234-1234-123456789abc.pdf';
const frame = 'lessons/12345678-1234-1234-1234-123456789abc.webp';
Deno.test('real SDK offline signing binds content headers and TTL without network', async () => {
  const s3 = new S3Client({
    endpoint: 'https://storage.example.test',
    region: 'test-region',
    forcePathStyle: true,
    credentials: {
      accessKeyId: 'test-only-access',
      secretAccessKey: 'test-only-secret',
    },
    requestChecksumCalculation: 'WHEN_REQUIRED',
  });
  try {
    const put = new URL(
      await signPut(s3, 'private', key, 'application/pdf', 42, 900),
    );
    const signed = put.searchParams.get('X-Amz-SignedHeaders')!.split(';');
    assert(
      signed.includes('content-type') && signed.includes('content-length') &&
        signed.includes('host'),
    );
    assert(put.searchParams.get('X-Amz-Expires') === '900');
    const changedSize = new URL(
      await signPut(s3, 'private', key, 'application/pdf', 43, 900),
    );
    const changedType = new URL(
      await signPut(s3, 'private', key, 'audio/mpeg', 42, 900),
    );
    assert(
      put.searchParams.get('X-Amz-Signature') !==
        changedSize.searchParams.get('X-Amz-Signature'),
    );
    assert(
      put.searchParams.get('X-Amz-Signature') !==
        changedType.searchParams.get('X-Amz-Signature'),
    );
    const get = new URL(await signGet(s3, 'private', frame, 3600));
    assert(get.searchParams.get('X-Amz-Expires') === '3600');
    assert(get.pathname === `/private/${frame}`);
  } finally {
    s3.destroy();
  }
});
