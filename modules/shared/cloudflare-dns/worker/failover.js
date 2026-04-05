/**
 * Cloudflare Worker — Automated DNS Failover
 *
 * Two invocation modes:
 *
 * 1. CRON (scheduled) — runs every minute as a background health check.
 *    Checks AKS health, updates DNS if unhealthy.
 *
 * 2. HTTP (fetch) — triggered instantly via POST /trigger
 *    Used by the backend's /api/simulate-down to force immediate failover.
 *    Requires Authorization: Bearer <WORKER_SECRET> header.
 *
 * State is persisted in KV between executions:
 *   - current_target: "aks" | "gke"
 *   - failure_count:  number of consecutive AKS failures
 *   - last_failover_at: ISO timestamp of last failover event
 *
 * RTO:
 *   - Cron: ~4 minutes (1 min detection × 3 threshold + DNS propagation)
 *   - HTTP trigger: < 5 seconds (immediate health check + DNS update)
 */

const CLOUDFLARE_API = "https://api.cloudflare.com/client/v4";

export default {
  /**
   * Cron handler — triggered every minute by Cloudflare scheduler.
   */
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runFailoverCheck(env));
  },

  /**
   * HTTP handler — allows instant failover trigger from the backend.
   *
   * POST /trigger
   *   Authorization: Bearer <WORKER_SECRET>
   *   Body: { "force_check": true }
   *
   * GET /state
   *   Authorization: Bearer <WORKER_SECRET>
   *   Returns current failover state as JSON.
   */
  async fetch(request, env) {
    const url = new URL(request.url);

    // Auth check
    const authHeader = request.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "").trim();
    if (!env.WORKER_SECRET || token !== env.WORKER_SECRET) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // CORS for frontend direct calls
    const corsHeaders = {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    };

    if (url.pathname === "/state" && request.method === "GET") {
      const state = await loadState(env);
      return new Response(JSON.stringify(state), { headers: corsHeaders });
    }

    if (url.pathname === "/trigger" && request.method === "POST") {
      // Instant trigger skips the failure threshold — forces immediate failover check
      await runFailoverCheck(env, { instant: true });
      const state = await loadState(env);
      return new Response(
        JSON.stringify({ ok: true, state }),
        { headers: corsHeaders }
      );
    }

    if (url.pathname === "/recover" && request.method === "POST") {
      // Force failback to AKS
      await updateDnsRecord(env, env.AKS_IP);
      await saveState(env, { current_target: "aks", failure_count: 0, last_failover_at: null });
      return new Response(
        JSON.stringify({ ok: true, message: "forced failback to AKS" }),
        { headers: corsHeaders }
      );
    }

    return new Response(JSON.stringify({ error: "not found" }), {
      status: 404,
      headers: corsHeaders,
    });
  },
};

async function runFailoverCheck(env, opts = {}) {
  const state = await loadState(env);
  console.log(`[failover] current_target=${state.current_target} failure_count=${state.failure_count}`);

  // Health checks use the non-proxied DNS records (aks-health / gke-health)
  // over HTTPS with Host: app.lucasnicoloso.com so nginx routes correctly.
  // Direct HTTP to the IP returns 308 redirect which doesn't work from Workers.
  const domain = env.DOMAIN_NAME || "lucasnicoloso.com";
  const aksHealthy = await checkHealth(`https://aks-health.${domain}${env.HEALTH_PATH}`, `app.${domain}`);
  console.log(`[failover] AKS health check: ${aksHealthy ? "PASS" : "FAIL"}`);

  if (aksHealthy) {
    if (state.current_target === "gke") {
      // AKS recovered — fail back
      console.log("[failover] AKS recovered. Failing back to AKS.");
      await updateDnsRecord(env, env.AKS_IP);
      await saveState(env, {
        current_target: "aks",
        failure_count: 0,
        last_failover_at: state.last_failover_at,
      });
    } else {
      await saveState(env, { ...state, failure_count: 0 });
    }
    return;
  }

  // AKS is unhealthy
  const newCount = state.failure_count + 1;
  const threshold = parseInt(env.FAILURE_THRESHOLD, 10);
  console.log(`[failover] AKS failure ${newCount}/${threshold}`);

  if ((opts.instant || newCount >= threshold) && state.current_target === "aks") {
    if (!opts.instant) {
      const gkeHealthy = await checkHealth(`https://gke-health.${domain}${env.HEALTH_PATH}`, `app.${domain}`);
      if (!gkeHealthy) {
        console.warn("[failover] GKE also unhealthy — not failing over.");
        await saveState(env, { ...state, failure_count: newCount });
        return;
      }
    } else {
      console.log("[failover] Instant trigger — skipping GKE health check");
    }

    console.log("[failover] FAILOVER TRIGGERED: AKS → GKE");
    await updateDnsRecord(env, env.GKE_IP);
    await saveState(env, {
      current_target: "gke",
      failure_count: newCount,
      last_failover_at: new Date().toISOString(),
    });
  } else {
    await saveState(env, { ...state, failure_count: newCount });
  }
}

async function checkHealth(url, hostHeader) {
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: { "Host": hostHeader },
      signal: AbortSignal.timeout(5000),
    });
    return response.status === 200;
  } catch (err) {
    console.error(`[failover] health check error for ${url}: ${err.message}`);
    return false;
  }
}

async function updateDnsRecord(env, targetIp) {
  const domain = env.DOMAIN_NAME || "lucasnicoloso.com";
  const recordNames = (env.RECORD_NAMES || env.RECORD_NAME || "api").split(",");

  for (const name of recordNames) {
    const fqdn = `${name.trim()}.${domain}`;
    const listRes = await fetch(
      `${CLOUDFLARE_API}/zones/${env.ZONE_ID}/dns_records?type=A&name=${fqdn}`,
      {
        headers: {
          Authorization: `Bearer ${env.CF_API_TOKEN}`,
          "Content-Type": "application/json",
        },
      }
    );

    const listData = await listRes.json();
    if (!listData.success || listData.result.length === 0) {
      console.error(`[failover] DNS record not found for ${fqdn}`);
      continue;
    }

    const recordId = listData.result[0].id;

    const updateRes = await fetch(
      `${CLOUDFLARE_API}/zones/${env.ZONE_ID}/dns_records/${recordId}`,
      {
        method: "PUT",
        headers: {
          Authorization: `Bearer ${env.CF_API_TOKEN}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          type: "A",
          name: name.trim(),
          content: targetIp,
          proxied: true,
          ttl: 1,
        }),
      }
    );

    const updateData = await updateRes.json();
    if (updateData.success) {
      console.log(`[failover] DNS ${fqdn} updated → ${targetIp}`);
    } else {
      console.error(`[failover] DNS update failed for ${fqdn}: ${JSON.stringify(updateData.errors)}`);
    }
  }
}

async function loadState(env) {
  const raw = await env.FAILOVER_STATE.get("state");
  if (!raw) {
    return { current_target: "aks", failure_count: 0, last_failover_at: null };
  }
  return JSON.parse(raw);
}

async function saveState(env, state) {
  await env.FAILOVER_STATE.put("state", JSON.stringify(state));
}
