import { uploadHandler } from "./handler.ts";
import { downloadHandler } from "../storage-download-url/handler.ts";
import {
  lessonKeys,
  MAX_UPLOAD_SIZE,
  type StorageCaller,
  uploadInput,
} from "../_shared/storage.ts";
function assert(ok: unknown, message = "Assertion failed"): asserts ok {
  if (!ok) throw new Error(message);
}
function rejects(fn: () => unknown) {
  try {
    fn();
  } catch {
    return;
  }
  throw new Error("Accepted invalid input");
}
const id = "12345678-1234-1234-1234-123456789abc";
const key = `lessons/${id}.pdf`;
const frame = `lessons/${id}.webp`;
const origin = "https://app.example.test";
function request(
  body: unknown = {},
  method = "POST",
  from: string | null = origin,
) {
  return new Request("https://function.example.test", {
    method,
    headers: {
      ...(from ? { origin: from } : {}),
      authorization: "Bearer verified-test-token",
    },
    ...(method === "POST" ? { body: JSON.stringify(body) } : {}),
  });
}
const valid = { prefix: "lessons", contentType: "application/pdf", size: 42 };
const current: StorageCaller = {
  isGestor: () => Promise.resolve(true),
  lesson: () => Promise.resolve({ file_key: key, image_keys: [frame] }),
};
function fixture(caller: StorageCaller | null = current) {
  const calls: unknown[] = [];
  const auth = {
    origins: [origin],
    authenticate: () => Promise.resolve(caller),
  };
  return {
    calls,
    upload: uploadHandler({
      ...auth,
      uuid: () => id,
      sign: (input) => {
        calls.push(input);
        return Promise.resolve({
          putUrl: "https://storage.test/put",
          ...(input.public ? { publicUrl: "https://storage.test/public" } : {}),
        });
      },
    }),
    download: downloadHandler({
      ...auth,
      sign: (keys, expiry) => {
        calls.push({ keys, expiry });
        return Promise.resolve(
          Object.fromEntries(keys.map((k) => [k, "https://storage.test/get"])),
        );
      },
    }),
  };
}
Deno.test("upload MIME, prefix and size allowlist", () => {
  for (
    const contentType of [
      "application/pdf",
      "audio/mpeg",
      "image/gif",
      "image/png",
      "image/jpeg",
      "image/webp",
    ]
  ) {
    assert(uploadInput({ ...valid, contentType }).contentType === contentType);
  }
  assert(
    uploadInput({
      prefix: "covers",
      contentType: "image/webp",
      size: MAX_UPLOAD_SIZE,
    }),
  );
  for (
    const input of [
      null,
      [],
      {},
      { ...valid, prefix: "../lessons" },
      { ...valid, prefix: "avatars" },
      { ...valid, prefix: "covers" },
      { ...valid, contentType: "video/mp4" },
      { ...valid, contentType: "__proto__" },
      ...[0, -1, MAX_UPLOAD_SIZE + 1, 1.5, "42", null].map((size) => ({
        ...valid,
        size,
      })),
    ]
  ) rejects(() => uploadInput(input));
});
Deno.test("HTTP CORS, allowed methods, unauthorized JWT seam", async () => {
  for (const handler of [fixture(null).upload, fixture(null).download]) {
    const options = await handler(request({}, "OPTIONS"));
    assert(options.status === 204);
    assert(
      options.headers.get("access-control-allow-methods") === "POST, OPTIONS",
    );
    assert(options.headers.get("access-control-allow-origin") === origin);
    assert((await handler(request({}, "GET"))).status === 403);
    const denied = await handler(request({}, "POST", "https://evil.test"));
    assert(
      denied.status === 403 &&
        !denied.headers.has("access-control-allow-origin"),
    );
    assert(
      !(await handler(request({}, "OPTIONS", "https://evil.test"))).headers.has(
        "access-control-allow-origin",
      ),
    );
    assert((await handler(request(valid))).status === 401);
  }
});
Deno.test("active gestor uploads bind generated key, MIME, length and 15 minute expiry", async () => {
  const f = fixture();
  const response = await f.upload(request(valid));
  assert(response.status === 200);
  assert((await response.json()).key === key);
  assert(
    JSON.stringify(f.calls[0]) ===
      JSON.stringify({
        key,
        contentType: valid.contentType,
        size: 42,
        public: false,
        expiresIn: 900,
      }),
  );
  const cover = await f.upload(
    request({ prefix: "covers", contentType: "image/webp", size: 1 }),
  );
  const payload = await cover.json();
  assert(payload.key === `covers/${id}.webp` && payload.publicUrl);
  for (const role of ["empresa", "funcionario", "no active context"]) {
    const blocked = fixture({
      ...current,
      isGestor: () => Promise.resolve(false),
    });
    assert((await blocked.upload(request(valid))).status === 403, role);
    assert(blocked.calls.length === 0);
  }
  assert((await f.upload(request({ ...valid, size: 0 }))).status === 400);
});
Deno.test("each download request checks lesson RLS before signing all frames for one hour", async () => {
  const reads: string[] = [];
  const f = fixture({
    ...current,
    lesson: (lessonId) => {
      reads.push(lessonId);
      return current.lesson(lessonId);
    },
  });
  for (let i = 0; i < 2; i++) {
    const response = await f.download(
      request({ lessonId: id, key: "ignored/forged.pdf" }),
    );
    assert(response.status === 200);
    assert(Object.keys((await response.json()).urls).length === 2);
  }
  assert(reads.length === 2 && reads.every((read) => read === id));
  assert(
    JSON.stringify(f.calls[0]) ===
      JSON.stringify({ keys: [key, frame], expiry: 3600 }),
  );
  for (
    const denial of ["other company", "other user", "manager", "paused course"]
  ) {
    const blocked = fixture({
      ...current,
      lesson: () => Promise.resolve(null),
    });
    assert(
      (await blocked.download(request({ lessonId: id }))).status === 403,
      denial,
    );
    assert(blocked.calls.length === 0);
  }
  for (
    const payload of [{}, { lessonId: "../other" }, { lessonId: [id] }, null]
  ) {
    assert((await f.download(request(payload))).status === 400);
  }
});
Deno.test("keys must be private lesson objects, bounded and deduplicated", async () => {
  assert(lessonKeys({ file_key: key, image_keys: [key] }).length === 1);
  assert(
    lessonKeys({
      file_key: key,
      image_keys: [],
      alternate_content: { file_key: null, image_keys: [frame] },
    }).length === 2,
  );
  assert(
    lessonKeys({
      file_key: null,
      image_keys: Array(100).fill(frame),
      alternate_content: { file_key: null, image_keys: Array(100).fill(frame) },
    }).length === 1,
  );
  assert(
    lessonKeys({ file_key: null, image_keys: Array(100).fill(frame) })
      .length === 1,
  );
  for (
    const data of [
      { file_key: key, image_keys: Array(100).fill(frame) },
      { file_key: "covers/abc.webp", image_keys: [] },
      { file_key: "lessons/../secret.pdf", image_keys: [] },
      { file_key: "lessons/a.mp4", image_keys: [] },
      { file_key: key, image_keys: "bad" },
      { file_key: `lessons/${"a".repeat(260)}.pdf`, image_keys: [] },
      { file_key: 1, image_keys: [] },
      { file_key: null, image_keys: [], alternate_content: [] },
      {
        file_key: null,
        image_keys: [],
        alternate_content: { image_keys: Array(101).fill(frame) },
      },
      {
        file_key: null,
        image_keys: [],
        alternate_content: { file_key: "covers/abc.webp" },
      },
    ]
  ) {
    rejects(() => lessonKeys(data));
    const f = fixture({ ...current, lesson: () => Promise.resolve(data) });
    assert((await f.download(request({ lessonId: id }))).status === 400);
    assert(f.calls.length === 0);
  }
});
Deno.test("missing configuration, malformed JSON and failed dependencies fail closed", async () => {
  const auth = {
    origins: [origin],
    authenticate: () => Promise.resolve(current),
  };
  const upload = uploadHandler({
    ...auth,
    uuid: () => id,
    sign: () => Promise.resolve(null),
  });
  const download = downloadHandler({
    ...auth,
    sign: () => Promise.resolve(null),
  });
  assert((await upload(request(valid))).status === 503);
  assert((await download(request({ lessonId: id }))).status === 503);
  assert(
    (await upload(
      new Request("https://function.test", { method: "POST", body: "{" }),
    )).status === 400,
  );
  const failed = downloadHandler({
    ...auth,
    authenticate: () => Promise.reject(new Error("offline")),
    sign: () => Promise.resolve({}),
  });
  assert((await failed(request({ lessonId: id }))).status === 400);
});
