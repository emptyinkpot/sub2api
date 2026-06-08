#!/usr/bin/env node
/**
 * Bootstrap ContentMRS novel lane on sub2api:
 * - ensure GLM/Qwen group + upstream account (if DASHSCOPE_API_KEY or ZHIPU_API_KEY present)
 * - create user API key bound to novel group
 * - write ~/.codex-secrets/contentmrs/sub2api-novel.env (never commit)
 *
 * Requires SUB2API_ADMIN_EMAIL + SUB2API_ADMIN_PASSWORD in env, or an explicit
 * SUB2API_DEPLOY_ENV_FILE. The production deployment env is owned by Coolify;
 * this helper must not assume a host-local source checkout.
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';

const baseUrl = String(process.env.SUB2API_ADMIN_BASE_URL || 'http://127.0.0.1:8080').replace(/\/+$/, '');
const publicV1 = `${baseUrl}/api/v1`;
const novelGroupName = String(process.env.SUB2API_NOVEL_GROUP_NAME || 'contentmrs-novel-qwen');
const novelKeyName = String(process.env.SUB2API_NOVEL_KEY_NAME || 'contentmrs-novel-generation');
const defaultModel = String(process.env.CONTENTBASE_DEFAULT_MODEL || 'qwen-plus');

function readEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const out = {};
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx <= 0) continue;
    out[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim();
  }
  return out;
}

function pickProviderKey() {
  const fromEnv = String(process.env.DASHSCOPE_API_KEY || process.env.ZHIPU_API_KEY || process.env.GLM_API_KEY || '').trim();
  if (fromEnv) return { apiKey: fromEnv, baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1' };
  const secrets = [
    path.join(os.homedir(), '.codex-secrets', 'dashscope', 'api.env'),
    path.join(os.homedir(), '.codex-secrets', 'glm', 'api.env'),
    path.join(os.homedir(), '.codex-secrets', 'zhipu', 'api.env'),
  ];
  for (const file of secrets) {
    const map = readEnvFile(file);
    const apiKey = String(map.DASHSCOPE_API_KEY || map.ZHIPU_API_KEY || map.GLM_API_KEY || '').trim();
    if (apiKey) {
      const base = String(map.DASHSCOPE_BASE_URL || map.GLM_BASE_URL || 'https://dashscope.aliyuncs.com/compatible-mode/v1').trim();
      return { apiKey, baseUrl: base.replace(/\/+$/, '') };
    }
  }
  return null;
}

async function api(method, route, token, body) {
  const response = await fetch(`${publicV1}${route}`, {
    method,
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let payload = {};
  if (text.trim()) {
    try { payload = JSON.parse(text); } catch { payload = { raw: text }; }
  }
  if (!response.ok) {
    const err = new Error(`sub2api ${method} ${route} failed: HTTP ${response.status} ${payload?.message || payload?.error || text.slice(0, 240)}`);
    err.status = response.status;
    err.payload = payload;
    throw err;
  }
  return payload?.data ?? payload;
}

async function loginAdmin() {
  const deployEnv = process.env.SUB2API_DEPLOY_ENV_FILE
    ? readEnvFile(process.env.SUB2API_DEPLOY_ENV_FILE)
    : {};
  const email = String(process.env.SUB2API_ADMIN_EMAIL || deployEnv.ADMIN_EMAIL || '').trim();
  const password = String(process.env.SUB2API_ADMIN_PASSWORD || deployEnv.ADMIN_PASSWORD || '').trim();
  if (!email || !password) {
    throw new Error('SUB2API admin credentials missing. Set SUB2API_ADMIN_EMAIL + SUB2API_ADMIN_PASSWORD or provide SUB2API_DEPLOY_ENV_FILE.');
  }
  const result = await api('POST', '/auth/login', '', { email, password });
  const token = String(result?.access_token || result?.token || '').trim();
  if (!token) throw new Error('admin login returned no access_token');
  return token;
}

function normalizeGroups(raw) {
  if (Array.isArray(raw)) return raw;
  if (raw && typeof raw === 'object') {
    return raw.items || raw.list || raw.groups || [];
  }
  return [];
}

function normalizeAccounts(raw) {
  if (Array.isArray(raw)) return raw;
  if (raw && typeof raw === 'object') {
    return raw.items || raw.list || raw.accounts || [];
  }
  return [];
}

async function ensureNovelGroup(token, providerKey) {
  const groups = normalizeGroups(await api('GET', '/admin/groups/all', token));
  let group = groups.find((item) => String(item?.name || '') === novelGroupName)
    || groups.find((item) => String(item?.platform || '') === 'openai' && /novel|contentmrs|qwen/i.test(String(item?.name || '')));
  if (!group) {
    group = await api('POST', '/admin/groups', token, {
      name: novelGroupName,
      description: 'ContentMRS Tier-1 novel/article generation (Qwen via DashScope compatible API)',
      platform: 'openai',
      rate_multiplier: 1,
      is_exclusive: true,
      subscription_type: 'standard',
    });
  }
  const groupId = Number(group?.id || group?.ID || 0);
  if (!groupId) throw new Error('novel group id missing after create/find');

  const accountsPage = await api('GET', '/admin/accounts?page=1&page_size=100', token);
  const accounts = normalizeAccounts(accountsPage);
  let account = accounts.find((item) => /contentmrs-novel|novel-qwen/i.test(String(item?.name || '')) && String(item?.platform || '') === 'openai');
  if (!account && providerKey) {
    account = await api('POST', '/admin/accounts', token, {
      name: 'contentmrs-novel-qwen-upstream',
      platform: 'openai',
      type: 'apikey',
      credentials: {
        api_key: providerKey.apiKey,
        base_url: providerKey.baseUrl,
        model_mapping: {
          [defaultModel]: defaultModel,
          'qwen-max': 'qwen-max',
          'qwen-turbo': 'qwen-turbo',
          'qwen-plus': 'qwen-plus',
        },
      },
      extra: { openai_passthrough: true },
      group_ids: [groupId],
      concurrency: 3,
      priority: 100,
    });
    try {
      await api('POST', `/admin/accounts/${account.id}/test`, token, {});
    } catch (error) {
      console.warn('account test warning:', error instanceof Error ? error.message : String(error));
    }
  } else if (account && providerKey) {
    await api('PUT', `/admin/accounts/${account.id}`, token, {
      name: account.name || 'contentmrs-novel-qwen-upstream',
      platform: 'openai',
      type: 'apikey',
      credentials: {
        api_key: providerKey.apiKey,
        base_url: providerKey.baseUrl,
        model_mapping: {
          [defaultModel]: defaultModel,
          'qwen-max': 'qwen-max',
          'qwen-turbo': 'qwen-turbo',
          'qwen-plus': 'qwen-plus',
        },
      },
      extra: { openai_passthrough: true },
      group_ids: [groupId],
      concurrency: Number(account.concurrency || 3),
      priority: Number(account.priority || 100),
    });
  }

  return { groupId, group, accountId: account?.id || null };
}

async function createNovelClientKey(token, groupId) {
  const users = await api('GET', '/admin/users?page=1&page_size=20', token);
  const userItems = normalizeAccounts(users);
  const adminUser = userItems.find((u) => u.role === 'admin' || u.is_admin) || userItems[0];
  if (!adminUser?.id) throw new Error('no admin user found to own novel API key');

  const existingKeys = await api('GET', `/admin/groups/${groupId}/api-keys?page=1&page_size=50`, token);
  const keyItems = normalizeAccounts(existingKeys);
  const existing = keyItems.find((k) => String(k?.name || '') === novelKeyName);
  if (existing?.key) {
    return { key: existing.key, keyId: existing.id, reused: true };
  }

  const created = await api('POST', '/keys', token, {
    name: novelKeyName,
    group_id: groupId,
    quota: 0,
  });
  const key = String(created?.key || created?.api_key || '').trim();
  if (!key) throw new Error('create key returned empty key — copy from sub2api UI if shown once');
  return { key, keyId: created?.id, reused: false };
}

async function main() {
  const providerKey = pickProviderKey();
  const token = await loginAdmin();
  const { groupId, accountId } = await ensureNovelGroup(token, providerKey);
  const { key, keyId, reused } = await createNovelClientKey(token, groupId);

  const outDir = path.join(os.homedir(), '.codex-secrets', 'contentmrs');
  fs.mkdirSync(outDir, { recursive: true });
  const envPath = path.join(outDir, 'sub2api-novel.env');
  const lines = [
    '# ContentMRS novel generation — sub2api client key (do not use Codex auth.json)',
    `SUB2API_NOVEL_API_KEY=${key}`,
    `SUB2API_NOVEL_BASE_URL=https://sub2api.tengokukk.com/v1`,
    `CONTENTBASE_DEFAULT_MODEL=${defaultModel}`,
    `SUB2API_NOVEL_GROUP_ID=${groupId}`,
    `SUB2API_NOVEL_KEY_ID=${keyId}`,
    `SUB2API_NOVEL_GROUP_NAME=${novelGroupName}`,
  ];
  fs.writeFileSync(envPath, `${lines.join('\n')}\n`, 'utf8');

  const probeBody = JSON.stringify({
    model: defaultModel,
    messages: [{ role: 'user', content: 'ping' }],
    max_tokens: 8,
  });
  const probeTargets = [
    `${baseUrl}/v1/chat/completions`,
    'https://sub2api.tengokukk.com/v1/chat/completions',
  ];
  let probeStatus = null;
  let probeModel = null;
  let probeWarn = null;
  for (const url of probeTargets) {
    try {
      const probe = await fetch(url, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${key}`,
          'content-type': 'application/json',
        },
        body: probeBody,
      });
      const probeText = await probe.text();
      let probeJson = {};
      try { probeJson = JSON.parse(probeText); } catch {}
      probeStatus = probe.status;
      probeModel = probeJson?.model || null;
      if (probe.ok) {
        probeWarn = null;
        break;
      }
      probeWarn = `HTTP ${probe.status} ${probeText.slice(0, 200)}`;
    } catch (error) {
      probeWarn = error instanceof Error ? error.message : String(error);
    }
  }
  if (probeWarn) {
    console.warn(`novel key probe warning (${probeTargets.join(' -> ')}): ${probeWarn}`);
  }

  console.log(JSON.stringify({
    ok: true,
    envPath,
    groupId,
    accountId,
    keyId,
    reusedKey: reused,
    model: defaultModel,
    probeStatus,
    probeModel,
    probeWarn,
    hasProviderKey: Boolean(providerKey),
  }, null, 2));
}

main().catch((error) => {
  console.error(JSON.stringify({
    ok: false,
    error: error instanceof Error ? error.message : String(error),
    payload: error?.payload || null,
  }, null, 2));
  process.exit(1);
});
