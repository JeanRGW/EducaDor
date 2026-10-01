import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

// Exercise the real handler without invoking Supabase or requiring its secrets.
const source = stripTypeScriptTypes(
  readFileSync(new URL('../functions/invite-member/index.ts', import.meta.url), 'utf8')
    .replace(/^import .* from '\.\.\/_shared\/invites\.ts';\n/m, ''),
);

function ilike(value, pattern) {
  const literal = (character) => character.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  let expression = '^';
  for (let index = 0; index < pattern.length; index++) {
    const character = pattern[index];
    if (character === '\\') {
      expression += literal(pattern[++index]);
    } else if (character === '%') {
      expression += '.*';
    } else if (character === '_') {
      expression += '.';
    } else {
      expression += literal(character);
    }
  }
  return new RegExp(`${expression}$`, 'i').test(value);
}

function fixture({ profiles = [], grantedIds = [], authEmail, pending = [] } = {}) {
  const tables = {
    profiles: profiles.map((row) => ({ ...row })),
    platform_gestors: grantedIds.map((user_id) => ({ user_id })),
    company_memberships: [],
    membership_invites: pending.map((row) => ({ ...row })),
    companies: [],
  };
  const patterns = [];
  const accountLookups = [];
  const accountLinks = [];
  let sequence = 0;

  function from(table) {
    let operation = 'select';
    let payload;
    let maximum;
    const filters = [];
    const execute = () => {
      if (operation === 'insert') {
        const row = {
          id: `c0000000-0000-4000-8000-${String(++sequence).padStart(12, '0')}`,
          ...(table === 'companies' ? { active: true } : {}),
          ...payload,
        };
        tables[table].push(row);
        return { data: [row], error: null };
      }
      let rows = tables[table].filter((row) => filters.every((filter) => filter(row)));
      if (operation === 'delete') {
        tables[table] = tables[table].filter((row) => !rows.includes(row));
        return { data: null, error: null };
      }
      if (operation === 'update') rows.forEach((row) => Object.assign(row, payload));
      if (maximum !== undefined) rows = rows.slice(0, maximum);
      return { data: rows, error: null };
    };
    const query = {
      select: () => query,
      insert: (value) => { operation = 'insert'; payload = value; return query; },
      update: (value) => { operation = 'update'; payload = value; return query; },
      delete: () => { operation = 'delete'; return query; },
      eq: (column, value) => { filters.push((row) => row[column] === value); return query; },
      is: (column, value) => query.eq(column, value),
      gt: (column, value) => { filters.push((row) => row[column] > value); return query; },
      lt: (column, value) => { filters.push((row) => row[column] < value); return query; },
      ilike: (column, pattern) => {
        patterns.push(pattern);
        filters.push((row) => ilike(row[column], pattern));
        return query;
      },
      limit: (value) => { maximum = value; return query; },
      maybeSingle: async () => {
        const result = execute();
        return result.data.length > 1
          ? { data: null, error: { message: 'Multiple rows' } }
          : { data: result.data[0] ?? null, error: null };
      },
      single: async () => ({ data: execute().data[0], error: null }),
      then: (resolve, reject) => Promise.resolve(execute()).then(resolve, reject),
    };
    return query;
  }

  let handler;
  runInNewContext(source, {
    Deno: {
      serve: (callback) => { handler = callback; },
      env: { get: (name) => name === 'APP_ORIGIN' ? 'https://app.example.test' : undefined },
    },
    preflight: () => null,
    caller: async () => ({
      id: 'publisher',
      client: { rpc: async () => ({ data: [{ role: 'gestor', company_id: null }], error: null }) },
    }),
    respond: (_req, body, status = 200) => ({ body, status }),
    newToken: () => 'a'.repeat(64),
    tokenHash: async () => 'b'.repeat(64),
    admin: {
      from,
      auth: { admin: {
        getUserById: async (id) => {
          accountLookups.push(id);
          return { data: { user: {
            id,
            email: authEmail ?? profiles.find((row) => row.id === id)?.email,
            email_confirmed_at: '2026-09-30T00:00:00Z',
          } }, error: null };
        },
        generateLink: async (options) => {
          accountLinks.push(options);
          return { data: {
            user: { id: 'new-user', email: options.email },
            properties: { action_link: 'https://auth.example.test/invite' },
          }, error: null };
        },
      } },
    },
  });
  return {
    tables, patterns, accountLookups, accountLinks,
    invite: (input) => handler({ json: async () => ({ role: 'gestor', name: 'Invitee', ...input }) }),
  };
}

for (const [email, pattern, decoy] of [
  ['Ana_1@Example.test', 'ana\\_1@example.test', 'anax1@example.test'],
  ['A%B@Example.test', 'a\\%b@example.test', 'axxxb@example.test'],
  ['Ana\\One@Example.test', 'ana\\\\one@example.test', 'anaone@example.test'],
]) {
  test(`email lookup treats pattern characters literally: ${email}`, async () => {
    const state = fixture({ profiles: [
      { id: 'literal', email },
      { id: 'decoy', email: decoy },
    ] });
    const response = await state.invite({ email });
    assert.equal(response.status, 200);
    assert.deepEqual(state.patterns, [pattern]);
    assert.deepEqual(state.accountLookups, ['literal']);
    assert.equal(state.accountLinks.length, 0);
    assert.equal(state.tables.membership_invites[0].email, email.toLowerCase());
  });
}

for (const decoys of [['ana@example.test'], ['ana@example.test', 'alex@example.test']]) {
  test(`wildcard address does not match ${decoys.length} unrelated profiles`, async () => {
    const state = fixture({
      profiles: decoys.map((email, index) => ({ id: `decoy-${index}`, email })),
      grantedIds: ['decoy-0'],
    });
    const response = await state.invite({ email: 'a%@example.test' });
    assert.equal(response.status, 200);
    assert.equal(response.body.link, 'https://auth.example.test/invite');
    assert.equal(state.accountLookups.length, 0);
    assert.equal(state.accountLinks[0].email, 'a%@example.test');
    assert.equal(state.tables.profiles.at(-1).id, 'new-user');
  });
}

test('a single wildcard match cannot return a dead membership link', async () => {
  const state = fixture({ profiles: [{ id: 'decoy', email: 'ana@example.test' }] });
  const response = await state.invite({ email: 'a%@example.test' });
  assert.equal(response.status, 200);
  assert.equal(response.body.link, 'https://auth.example.test/invite');
  assert.equal(state.accountLookups.length, 0);
  assert.equal(state.accountLinks[0].email, 'a%@example.test');
  assert.equal(state.tables.profiles.at(-1).email, 'a%@example.test');
});

test('new invitation with a mismatched Auth email is rejected and cleaned up', async () => {
  const state = fixture({
    profiles: [{ id: 'existing', email: 'invitee@example.test' }],
    authEmail: 'someone-else@example.test',
  });
  const response = await state.invite({ email: 'invitee@example.test' });
  assert.equal(response.status, 400);
  assert.equal(response.body.error, 'Account unavailable');
  assert.equal(state.tables.membership_invites.length, 0);
  assert.equal(state.accountLinks.length, 0);
});

test('Auth email mismatch also removes a company created for the invitation', async () => {
  const state = fixture({
    profiles: [{ id: 'existing', email: 'invitee@example.test' }],
    authEmail: 'someone-else@example.test',
  });
  const response = await state.invite({
    role: 'empresa', email: 'invitee@example.test', company: { name: 'New Company' },
  });
  assert.equal(response.status, 400);
  assert.equal(state.tables.membership_invites.length, 0);
  assert.equal(state.tables.companies.length, 0);
});

test('regeneration looks up an underscore email literally and rotates its token', async () => {
  const state = fixture({
    profiles: [
      { id: 'literal', email: 'Ana_1@Example.test' },
      { id: 'decoy', email: 'anax1@example.test' },
    ],
    pending: [{ id: 'pending', email: 'ana_1@example.test', role: 'gestor',
      company_id: null, expires_at: '2099-01-01T00:00:00Z', token_hash: 'old-token' }],
  });
  const response = await state.invite({ action: 'regenerate', email: 'Ana_1@Example.test' });
  assert.equal(response.status, 200);
  assert.deepEqual(state.accountLookups, ['literal']);
  assert.equal(state.tables.membership_invites[0].token_hash, 'b'.repeat(64));
});

test('regeneration still rejects a mismatched Auth email without rotating the token', async () => {
  const state = fixture({
    profiles: [{ id: 'existing', email: 'invitee@example.test' }],
    authEmail: 'someone-else@example.test',
    pending: [{ id: 'pending', email: 'invitee@example.test', role: 'gestor',
      company_id: null, expires_at: '2099-01-01T00:00:00Z', token_hash: 'old-token' }],
  });
  const response = await state.invite({ action: 'regenerate', email: 'invitee@example.test' });
  assert.equal(response.status, 409);
  assert.equal(state.tables.membership_invites[0].token_hash, 'old-token');
});
