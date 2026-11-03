import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from 'npm:@aws-sdk/client-s3@3.1161.0';
import { getSignedUrl } from 'npm:@aws-sdk/s3-request-presigner@3.1161.0';
export { S3Client };
export function signPut(
  s3: S3Client,
  bucket: string,
  key: string,
  contentType: string,
  size: number,
  expiresIn: number,
) {
  return getSignedUrl(
    s3,
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      ContentType: contentType,
      ContentLength: size,
    }),
    {
      expiresIn,
      // Content-Type is otherwise excluded by the S3 presigner. Browser sets length from the body.
      signableHeaders: new Set(['content-type', 'content-length']),
    },
  );
}
export function signGet(
  s3: S3Client,
  bucket: string,
  key: string,
  expiresIn: number,
) {
  return getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: key }), {
    expiresIn,
  });
}
export function storageConfig(isPublic: boolean) {
  const endpoint = Deno.env.get('STORAGE_S3_ENDPOINT');
  const region = Deno.env.get('STORAGE_S3_REGION');
  const accessKeyId = Deno.env.get('STORAGE_S3_ACCESS_KEY_ID');
  const secretAccessKey = Deno.env.get('STORAGE_S3_SECRET_ACCESS_KEY');
  const bucket = Deno.env.get(
    isPublic ? 'STORAGE_BUCKET_PUBLIC' : 'STORAGE_BUCKET_PRIVATE',
  );
  if (!endpoint || !region || !accessKeyId || !secretAccessKey || !bucket) {
    return null;
  }
  return {
    bucket,
    s3: new S3Client({
      endpoint,
      region,
      forcePathStyle: true,
      credentials: { accessKeyId, secretAccessKey },
      requestChecksumCalculation: 'WHEN_REQUIRED',
    }),
  };
}
