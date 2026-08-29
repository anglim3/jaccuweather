const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

function loadLimiter() {
  const source = fs.readFileSync(path.join(root, 'lockdown-worker.js'), 'utf8');
  const match = source.match(/const pollenRateLimitFn = `([\s\S]*?)`;/);
  assert.ok(match, 'expected pollenRateLimitFn template in lockdown-worker.js');
  const calls = [];
  const sandbox = {
    jsonResponse(data, status = 200, extraHeaders = {}) {
      const response = { data, status, headers: extraHeaders };
      calls.push(response);
      return response;
    },
  };
  vm.runInNewContext(`${match[1]}; this.pollenRateLimitDenied = pollenRateLimitDenied;`, sandbox);
  return { pollenRateLimitDenied: sandbox.pollenRateLimitDenied, calls };
}

function requestWithIp(ip) {
  return {
    headers: {
      get(name) {
        if (name === 'CF-Connecting-IP') return ip;
        return null;
      },
    },
  };
}

test('missing rate-limit binding fails closed with 503 and does not call upstream', async () => {
  const { pollenRateLimitDenied, calls } = loadLimiter();
  const denied = await pollenRateLimitDenied(requestWithIp('1.2.3.4'), {});
  assert.equal(denied.status, 503);
  assert.equal(denied.data.reason, 'Service Unavailable');
  assert.equal(calls.length, 1);
});

test('non-callable limit fails closed with 503', async () => {
  const { pollenRateLimitDenied } = loadLimiter();
  const denied = await pollenRateLimitDenied(requestWithIp('1.2.3.4'), { POLLEN_RATE_LIMIT: {} });
  assert.equal(denied.status, 503);
});

test('missing CF-Connecting-IP fails closed with 403 and does not use a shared key', async () => {
  const { pollenRateLimitDenied } = loadLimiter();
  let limited = false;
  const denied = await pollenRateLimitDenied(requestWithIp(null), {
    POLLEN_RATE_LIMIT: {
      async limit() {
        limited = true;
        return { success: true };
      },
    },
  });
  assert.equal(denied.status, 403);
  assert.equal(denied.data.reason, 'Forbidden');
  assert.equal(limited, false);
});

test('limiter.limit throw fails closed with 503', async () => {
  const { pollenRateLimitDenied } = loadLimiter();
  const denied = await pollenRateLimitDenied(requestWithIp('1.2.3.4'), {
    POLLEN_RATE_LIMIT: {
      async limit() {
        throw new Error('kv unavailable');
      },
    },
  });
  assert.equal(denied.status, 503);
  assert.equal(denied.data.reason, 'Service Unavailable');
});

test('success !== true returns 429 with Retry-After: 60', async () => {
  const { pollenRateLimitDenied } = loadLimiter();
  const denied = await pollenRateLimitDenied(requestWithIp('1.2.3.4'), {
    POLLEN_RATE_LIMIT: {
      async limit({ key }) {
        assert.equal(key, '1.2.3.4');
        return { success: false };
      },
    },
  });
  assert.equal(denied.status, 429);
  assert.equal(denied.data.reason, 'Too Many Requests');
  assert.equal(denied.headers['Retry-After'], '60');
});

test('null limiter result is treated as a deny, not a pass', async () => {
  const { pollenRateLimitDenied } = loadLimiter();
  const denied = await pollenRateLimitDenied(requestWithIp('1.2.3.4'), {
    POLLEN_RATE_LIMIT: {
      async limit() {
        return null;
      },
    },
  });
  assert.equal(denied.status, 429);
  assert.equal(denied.headers['Retry-After'], '60');
});

test('successful limit returns null so the pollen handler can run', async () => {
  const { pollenRateLimitDenied, calls } = loadLimiter();
  const denied = await pollenRateLimitDenied(requestWithIp('203.0.113.9'), {
    POLLEN_RATE_LIMIT: {
      async limit({ key }) {
        assert.equal(key, '203.0.113.9');
        return { success: true };
      },
    },
  });
  assert.equal(denied, null);
  assert.equal(calls.length, 0);
});

test('period in wrangler.toml is 60 seconds and matches Retry-After', () => {
  const toml = fs.readFileSync(path.join(root, 'wrangler.toml'), 'utf8');
  assert.match(toml, /limit = 20/);
  assert.match(toml, /period = 60/);
  const source = fs.readFileSync(path.join(root, 'lockdown-worker.js'), 'utf8');
  assert.match(source, /Retry-After': '60'/);
});
