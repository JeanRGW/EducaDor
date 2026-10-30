import { S3Client, GetObjectCommand } from 'npm:@aws-sdk/client-s3@3';
import { getSignedUrl } from 'npm:@aws-sdk/s3-request-presigner@3';
import { caller, preflight, respond } from '../_shared/invites.ts';

Deno.serve(async (req) => {
  const blocked = preflight(req);
  if (blocked) return blocked;
  const current = await caller(req);
  if (!current) return respond(req, { error: 'Authentication required' }, 401);
  try {
    const { lessonId } = await req.json();
    // The caller's JWT and lesson RLS enforce active role and all course gates.
    const { data, error } = await current.client.from('lessons')
      .select('file_key,image_keys').eq('id', lessonId).maybeSingle();
    if (error || !data) {
      return respond(req, { error: 'Forbidden' }, 403);
    }
    const endpoint = Deno.env.get('STORAGE_S3_ENDPOINT');
    const region = Deno.env.get('STORAGE_S3_REGION');
    const accessKeyId = Deno.env.get('STORAGE_S3_ACCESS_KEY_ID');
    const secretAccessKey = Deno.env.get('STORAGE_S3_SECRET_ACCESS_KEY');
    const bucket = Deno.env.get('STORAGE_BUCKET_PRIVATE');
    if (!endpoint || !region || !accessKeyId || !secretAccessKey || !bucket) {
      return respond(req, { error: 'Storage not configured' }, 503);
    }
    const s3 = new S3Client({ endpoint, region, forcePathStyle: true,
      credentials: { accessKeyId, secretAccessKey } });
    const keys: string[] = [...(data.file_key ? [data.file_key] : []), ...(data.image_keys ?? [])];
    if (keys.length > 100) return respond(req, { error: 'Too many files' }, 400);
    const urls = Object.fromEntries(await Promise.all(keys.map(async (key) => [key,
      await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: key }), { expiresIn: 3600 })])));
    return respond(req, { urls });
  } catch {
    return respond(req, { error: 'Invalid request' }, 400);
  }
});
