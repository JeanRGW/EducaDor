import { caller } from './invites.ts';
import type { HttpDependencies } from './storage.ts';
export const storageAuth: HttpDependencies = {
  origins:
    (Deno.env.get('ALLOWED_APP_ORIGINS') ?? Deno.env.get('APP_ORIGIN') ?? '')
      .split(',').map((value) => value.trim()).filter(Boolean),
  async authenticate(req) {
    const current = await caller(req);
    if (!current) return null;
    return {
      async isGestor() {
        const { data, error } = await current.client.rpc('selected_context');
        return !error && data?.[0]?.role === 'gestor';
      },
      async lesson(id) {
        const { data, error } = await current.client.from('lessons')
          .select('file_key,image_keys,alternate_content').eq('id', id).maybeSingle();
        return error ? null : data;
      },
    };
  },
};
