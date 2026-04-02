/**
 * Cloudflare Worker — Automated DNS Failover
 *
 * Runs every minute via cron trigger.
 * Checks OKE primary cluster health. On consecutive failures, updates
 * the DNS A record to point to GKE failover cluster.
 * Automatically fails back when OKE recovers.
 *
 * State is persisted in KV between executions:
 * - current_target: "oke" | "gke"
 * - failure_count: number of consecutive OKE failures
 * - last_failover_at: ISO timestamp of last failover event
 *
 * Trade-off (ADR-007):
 * Cron minimum interval is 1 minute → RTO ~4 minutes.
 * Cloudflare Load Balancing ($5/month) provides sub-second detection.
 * This approach is chosen to keep the project at R$0/month.
 */

const CLOUDFLARE_API = "https://api.cloudflare.com/client/v4";

export default {
  /**
   * Cron handler — triggered every minute by Cloudflare scheduler
   */
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runFailoverCheck(env));
  },
};

async function runFailoverCheck(env) {
  const state = await loadState(env);
  console.log(`[failover] current_target=${state.current_target} failure_count=${state.failure_count}`);

  const okeHealthy = await checkHealth(env.OKE_IP, env.HEALTH_PATH);
  console.log(`[failover] OKE health check: ${okeHealthy ? "PASS" : "FAIL"}`);

  if (okeHealthy) {
    if (state.current_target === "gke") {
      // OKE recovered — fail back
      console.log("[failover] OKE recovered. Failing back to OKE.");
      await updateDnsRecord(env, env.OKE_IP);
      await saveState(env, { current_target: "oke", failure_count: 0, last_failover_at: state.last_failover_at });
    } else {
      // Normal operation — reset failure counter
      await saveState(env, { ...state, failure_count: 0 });
    }
    return;
  }

  // OKE is unhealthy
  const newCount = state.failure_count + 1;
  const threshold = parseInt(env.FAILURE_THRESHOLD, 10);
  console.log(`[failover] OKE failure ${newCount}/${threshold}`);

  if (newCount >= threshold && state.current_target === "oke") {
    // Threshold reached — trigger failover to GKE
    const gkeHealthy = await checkHealth(env.GKE_IP, env.HEALTH_PATH);
    if (!gkeHealthy) {
      console.warn("[failover] GKE also unhealthy — not failing over. Both clusters down.");
      await saveState(env, { ...state, failure_count: newCount });
      return;
    }

    console.log("[failover] FAILOVER TRIGGERED: OKE → GKE");
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

/**
 * Performs an HTTPS health check against the given IP.
 * Returns true if the endpoint responds with HTTP 200.
 */
async function checkHealth(ip, path) {
  try {
    const url = `https://${ip}${path}`;
    const response = await fetch(url, {
      method: "GET",
      signal: AbortSignal.timeout(5000), // 5 second timeout
    });
    return response.status === 200;
  } catch (err) {
    console.error(`[failover] health check error for ${ip}: ${err.message}`);
    return false;
  }
}

/**
 * Updates the DNS A record via Cloudflare API.
 */
async function updateDnsRecord(env, targetIp) {
  // First, find the record ID
  const listRes = await fetch(
    `${CLOUDFLARE_API}/zones/${env.ZONE_ID}/dns_records?type=A&name=${env.RECORD_NAME}`,
    {
      headers: {
        Authorization: `Bearer ${env.CF_API_TOKEN}`,
        "Content-Type": "application/json",
      },
    }
  );

  const listData = await listRes.json();
  if (!listData.success || listData.result.length === 0) {
    console.error("[failover] DNS record not found");
    return;
  }

  const recordId = listData.result[0].id;

  // Update the record
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
        name: env.RECORD_NAME,
        content: targetIp,
        proxied: true,
        ttl: 1,
      }),
    }
  );

  const updateData = await updateRes.json();
  if (updateData.success) {
    console.log(`[failover] DNS updated → ${targetIp}`);
  } else {
    console.error(`[failover] DNS update failed: ${JSON.stringify(updateData.errors)}`);
  }
}

/**
 * Loads failover state from KV store.
 */
async function loadState(env) {
  const raw = await env.FAILOVER_STATE.get("state");
  if (!raw) {
    return { current_target: "oke", failure_count: 0, last_failover_at: null };
  }
  return JSON.parse(raw);
}

/**
 * Persists failover state to KV store.
 */
async function saveState(env, state) {
  await env.FAILOVER_STATE.put("state", JSON.stringify(state));
}
