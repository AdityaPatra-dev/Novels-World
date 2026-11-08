/**
 * Novels World Cloudflare Edge Proxy with High-Performance Edge Caching
 * 
 * - Caches responses using Cloudflare's native Edge Cache (caches.default)
 * - Sets browser Cache-Control headers to minimize duplicate network requests
 * - Drastically reduces worker invocation counts and latency
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

    const cache = caches.default;
    const cacheKey = new Request(request.url, { method: "GET" });

    // 3. Check Cloudflare Edge Cache for GET requests (serves in <10ms, 0 origin hits)
    if (request.method === "GET") {
      try {
        const cachedResponse = await cache.match(cacheKey);
        if (cachedResponse) {
          const res = new Response(cachedResponse.body, cachedResponse);
          res.headers.set("X-Proxy-Cache", "HIT");
          res.headers.set("Access-Control-Allow-Origin", "*");
          return res;
        }
      } catch (_) {}
    }

    try {
      const parsedTarget = new URL(targetUrl);

      // 4. Prepare forward headers
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
        cf: {
          cacheEverything: true,
          cacheTtlByStatus: {
            "200-299": 3600, // 1 hour for successful responses
            "404": 60,
            "500-599": 10,
          },
        },
      };

      if (request.method !== "GET" && request.method !== "HEAD") {
        init.body = request.body;
      }

      // 5. Fetch from origin server
      const response = await fetch(targetUrl, init);

      // Determine optimal TTL based on content type
      const contentType = response.headers.get("content-type") || "";
      const isImage = targetUrl.match(/\.(jpe?g|png|webp|avif|gif)(\?.*)?$/i) || contentType.startsWith("image/");
      const isChapter = targetUrl.toLowerCase().includes("chapter");

      let maxAge = 1800; // 30 minutes default
      if (isImage) {
        maxAge = 86400 * 7; // 7 days for book covers
      } else if (isChapter) {
        maxAge = 86400; // 24 hours for chapter text
      }

      // 6. Build response with CORS and browser caching headers
      const responseHeaders = new Headers(response.headers);
      responseHeaders.set("Access-Control-Allow-Origin", "*");
      responseHeaders.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, HEAD");
      responseHeaders.set("Access-Control-Allow-Headers", "*");
      responseHeaders.set("Cache-Control", `public, max-age=${maxAge}, s-maxage=${maxAge}, stale-while-revalidate=3600`);
      responseHeaders.set("X-Proxy-Cache", "MISS");
      responseHeaders.delete("X-Frame-Options");
      responseHeaders.delete("Content-Security-Policy");

      const proxyResponse = new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: responseHeaders,
      });

      // 7. Store in Cloudflare Edge Cache for GET requests
      if (request.method === "GET" && response.status === 200) {
        ctx.waitUntil(cache.put(cacheKey, proxyResponse.clone()));
      }

      return proxyResponse;
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
