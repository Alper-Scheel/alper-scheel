const PRODUCT_ID = "alva-text";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return json({}, 204);
    }

    try {
      if (request.method === "GET" && (url.pathname === "/" || url.pathname === "/health")) {
        return json({
          ok: true,
          service: "adluna-platform-api",
          runtime: "cloudflare-worker",
          version: "0.2.0",
          env: "production"
        });
      }

      if (request.method === "POST" && url.pathname === "/v1/activation/request") {
        return await requestActivation(request, env);
      }

      if (request.method === "POST" && url.pathname === "/v1/activation/verify") {
        return await verifyActivation(request, env);
      }

      if (request.method === "POST" && url.pathname === "/v1/license/check") {
        return await licenseCheck(request, env);
      }

      if (request.method === "GET" && url.pathname === "/v1/admin/stats") {
        return await adminStats(request, env);
      }

      if (request.method === "POST" && url.pathname === "/v1/device/list") {
        return json({ devices: [] });
      }

      if (request.method === "POST" && url.pathname === "/v1/device/revoke") {
        return json({ ok: true, message: "Device revoke accepted." });
      }

      return json({ detail: "Not found" }, 404);
    } catch (error) {
      return json({ detail: error?.message || "Internal server error" }, 500);
    }
  }
};

async function requestActivation(request, env) {
  const body = await readJSON(request);
  const email = normalizeEmail(body.email);
  const product = String(body.product || "");
  const deviceUUID = String(body.device_uuid || "");

  if (!email || product !== PRODUCT_ID || !deviceUUID) {
    return json({ detail: "Invalid activation request" }, 400);
  }

  const code = await activationCode(env, email, product, deviceUUID, currentWindow(env));
  const sent = await sendActivationEmail(env, email, code);

  if (!sent.ok) {
    return json({ detail: "Email provider unavailable. Please try again shortly." }, 502);
  }

  return json({
    ok: true,
    message: `Code sent to ${email}. Valid for ${ttlMinutes(env)} minutes.`
  });
}

async function verifyActivation(request, env) {
  const body = await readJSON(request);
  const email = normalizeEmail(body.email);
  const product = String(body.product || "");
  const deviceUUID = String(body.device_uuid || "");
  const code = String(body.code || "").replace(/\D/g, "");

  if (!email || product !== PRODUCT_ID || !deviceUUID || code.length < 6) {
    return json({ detail: "Invalid activation payload" }, 400);
  }

  const nowWindow = currentWindow(env);
  const validCodes = [
    await activationCode(env, email, product, deviceUUID, nowWindow),
    await activationCode(env, email, product, deviceUUID, nowWindow - 1)
  ];

  if (!validCodes.includes(code)) {
    return json({ detail: "Invalid, expired, or already-used code" }, 401);
  }

  const token = await signToken(env, {
    email,
    product,
    device_uuid: deviceUUID,
    status: "beta",
    tier: "full",
    issued_at: Math.floor(Date.now() / 1000)
  });

  return json({
    ok: true,
    token,
    status: "beta",
    tier: "full",
    message: "Device activated successfully."
  });
}

async function licenseCheck(request, env) {
  const body = await readJSON(request);
  const auth = request.headers.get("Authorization") || "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  const payload = await verifyToken(env, token);

  if (!payload) {
    return json({ detail: "Invalid token" }, 401);
  }

  if (payload.product !== body.product || payload.device_uuid !== body.device_uuid) {
    return json({ detail: "Token does not match provided device/product" }, 401);
  }

  return json({
    status: "beta",
    tier: "full",
    message: "Vollzugang aktiv. Danke für deine Unterstützung.",
    check_again_in: Number(env.LICENSE_CHECK_TTL_SECONDS || "86400"),
    trial_expires_at: null
  });
}

async function adminStats(request, env) {
  const expected = env.ADLUNA_ADMIN_TOKEN || "";
  const auth = request.headers.get("Authorization") || "";
  if (expected && auth !== `Bearer ${expected}`) {
    return json({ detail: "Unauthorized" }, 401);
  }
  return json({
    total_users: null,
    verified_users: null,
    active_devices: null,
    checks_last_24h: null,
    products: [PRODUCT_ID],
    runtime: "cloudflare-worker"
  });
}

async function sendActivationEmail(env, email, code) {
  const apiKey = env.RESEND_API_KEY;
  if (!apiKey) {
    return { ok: false, status: 500 };
  }

  const fromName = env.RESEND_FROM_NAME || "AdLuna Platform";
  const fromEmail = env.RESEND_FROM_EMAIL || "no-reply@mail.adluna.de";
  const subject = "Dein ALVA-TEXT Aktivierungscode";
  const text = [
    "Hallo,",
    "",
    `dein Aktivierungscode für ALVA-TEXT lautet: ${code}`,
    "",
    `Der Code ist ${ttlMinutes(env)} Minuten gültig.`,
    "",
    "AdLuna"
  ].join("\n");

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      from: `${fromName} <${fromEmail}>`,
      to: [email],
      subject,
      text
    })
  });

  return { ok: response.ok, status: response.status };
}

async function activationCode(env, email, product, deviceUUID, windowValue) {
  const raw = `${email}|${product}|${deviceUUID}|${windowValue}`;
  const signature = await hmac(env, raw);
  const bytes = new Uint8Array(signature);
  const number = ((bytes[0] << 24) >>> 0) + (bytes[1] << 16) + (bytes[2] << 8) + bytes[3];
  return String(number % 1000000).padStart(6, "0");
}

function currentWindow(env) {
  return Math.floor(Date.now() / 1000 / (ttlMinutes(env) * 60));
}

function ttlMinutes(env) {
  return Number(env.ACTIVATION_CODE_TTL_MINUTES || "15");
}

async function signToken(env, payload) {
  const encodedPayload = base64url(new TextEncoder().encode(JSON.stringify(payload)));
  const signature = base64url(new Uint8Array(await hmac(env, encodedPayload)));
  return `${encodedPayload}.${signature}`;
}

async function verifyToken(env, token) {
  const parts = token.split(".");
  if (parts.length !== 2) {
    return null;
  }
  const expected = base64url(new Uint8Array(await hmac(env, parts[0])));
  if (!constantTimeEqual(expected, parts[1])) {
    return null;
  }
  try {
    const jsonText = new TextDecoder().decode(base64urlDecode(parts[0]));
    return JSON.parse(jsonText);
  } catch {
    return null;
  }
}

async function hmac(env, value) {
  const secret = env.ACTIVATION_SECRET || env.ADLUNA_ADMIN_TOKEN || "adluna-dev-secret";
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  return crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
}

function constantTimeEqual(a, b) {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let index = 0; index < a.length; index += 1) {
    diff |= a.charCodeAt(index) ^ b.charCodeAt(index);
  }
  return diff === 0;
}

function base64url(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64urlDecode(value) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

async function readJSON(request) {
  try {
    return await request.json();
  } catch {
    return {};
  }
}

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function json(body, status = 200) {
  return new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "authorization, content-type",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS"
    }
  });
}
