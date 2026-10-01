import { S3Client, PutObjectCommand } from 'npm:@aws-sdk/client-s3@3';
import { getSignedUrl } from 'npm:@aws-sdk/s3-request-presigner@3';
import { caller, preflight, respond } from '../_shared/invites.ts';

// Covers are resized to WebP on the device; the app holds no storage keys.
// Flow: POST here (Supabase JWT) → PUT bytes to putUrl → save key via publish_video_trail.
const maxSize = 50 * 1024 * 1024; // Supabase Free per-file ceiling.
const expiresIn = 15 * 60;

Deno.serve(async (req) => {
  const blocked = preflight(req);
  if (blocked) return blocked;
  const current = await caller(req);
  if (!current) return respond(req, { error: 'Authentication required' }, 401);

  try {
    const { data: selected, error: contextError } =
      await current.client.rpc('selected_context');
    if (contextError || selected?.[0]?.role !== 'gestor') {
      return respond(req, { error: 'Forbidden' }, 403);
    }

    const input = await req.json();
    const prefix = input.prefix as string;
    const contentType = input.contentType as string;
    const size = input.size as number;
    if (prefix !== 'covers' || contentType !== 'image/webp' ||
      typeof size !== 'number' || !(size >= 1 && size <= maxSize)) {
      return respond(req, { error: 'Invalid upload' }, 400);
    }

    const endpoint = Deno.env.get('STORAGE_S3_ENDPOINT');
    const region = Deno.env.get('STORAGE_S3_REGION');
    const accessKeyId = Deno.env.get('STORAGE_S3_ACCESS_KEY_ID');
    const secretAccessKey = Deno.env.get('STORAGE_S3_SECRET_ACCESS_KEY');
    const bucket = Deno.env.get('STORAGE_BUCKET_PUBLIC');
    if (!endpoint || !region || !accessKeyId || !secretAccessKey || !bucket) {
      return respond(req, { error: 'Storage upload not configured' }, 503);
    }

    const key = `covers/${crypto.randomUUID()}.webp`;
    const s3 = new S3Client({
      endpoint, region, forcePathStyle: true,
      credentials: { accessKeyId, secretAccessKey },
    });
    // Sign host only: content headers vary by HTTP client and would break
    // the signature when they differ by case or presence.
    const putUrl = await getSignedUrl(s3, new PutObjectCommand({
      Bucket: bucket, Key: key, ContentType: contentType,
    }), { expiresIn });
    return respond(req, { key, putUrl,
      publicUrl: `${Deno.env.get('SUPABASE_URL')}/storage/v1/object/public/${bucket}/${key}` });
  } catch {
    return respond(req, { error: 'Invalid request' }, 400);
  }
});
