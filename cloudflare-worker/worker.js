/**
 * Novels World Cloudflare Edge Proxy
 * 
 * Transparently proxies novel website requests for the web browser client,
 * providing proper CORS headers and avoiding browser cross-origin blocks.
 */

export default {
  async fetch(request, env, ctx) {
    // 1. Handle CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS, HEAD",
          "Access-Control-Allow-Headers": "*",
          "Access-Control-Max-Age": "86400",
        },
      });
    }

    // 2. Extract target URL
    const url = new URL(request.url);
    const targetUrl = url.searchParams.get("url");

    if (!targetUrl) {
      return new Response(
        JSON.stringify({ 
          error: "Missing 'url' query parameter",
          usage: "Pass ?url=https://target-novel-site.com"
        }),
        {
          status: 400,
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }

    try {
      const parsedTarget = new URL(targetUrl);

      // 3. Prepare forward headers
      const forwardHeaders = new Headers(request.headers);
      forwardHeaders.set("Host", parsedTarget.host);
      forwardHeaders.set("Referer", parsedTarget.origin + "/");
      forwardHeaders.set(
        "User-Agent",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      );
      forwardHeaders.delete("Origin");

      const init = {
        method: request.method,
        headers: forwardHeaders,
        redirect: "follow",
      };

      if (request.method !== "GET" && request.method !== "HEAD") {
        init.body = request.body;
      }

      // 4. Fetch the target URL from Cloudflare Edge
      const response = await fetch(targetUrl, init);

      // 5. Clone and attach CORS headers
      const responseHeaders = new Headers(response.headers);
      responseHeaders.set("Access-Control-Allow-Origin", "*");
      responseHeaders.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, HEAD");
      responseHeaders.set("Access-Control-Allow-Headers", "*");
      responseHeaders.delete("X-Frame-Options");
      responseHeaders.delete("Content-Security-Policy");

      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: responseHeaders,
      });
    } catch (err) {
      return new Response(
        JSON.stringify({ error: "Proxy fetch failed", message: err.message }),
        {
          status: 502,
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }
  },
};
