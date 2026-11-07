# Novels World - Cloudflare Edge Proxy

This Cloudflare Worker is a lightweight, 100% free serverless edge proxy that allows **Novels World Web** (`https://novels-world-app.web.app`) to browse, search, and read novels from any source without being blocked by browser CORS restrictions.

---

### How to Deploy (Takes 60 Seconds - 100% Free Forever)

#### Option 1: Via Cloudflare Dashboard (Recommended, No Terminal Required)
1. Go to **[dash.cloudflare.com](https://dash.cloudflare.com/)** and log in (or create a free account if you don't have one).
2. In the left sidebar, click **Workers & Pages**.
3. Click the blue **Create application** button, then click **Create Worker**.
4. Name it `novels-world-proxy` (or any name you prefer), and click **Deploy**.
5. Once created, click **Quick edit** (top right).
6. Delete whatever code is in the editor, and copy-paste the entire contents of [`worker.js`](worker.js).
7. Click **Save and Deploy**.
8. Copy your worker's live URL (e.g. `https://novels-world-proxy.<your-subdomain>.workers.dev`).

---

#### Option 2: Via Terminal (Wrangler CLI)
Run from this directory:
```bash
npx wrangler login
npx wrangler deploy
```

---

### Updating the App with Your Worker URL
Once deployed, copy your worker's URL and paste it in `lib/core/utils/http_client_factory.dart`:
```dart
String webProxyEndpoint = 'https://novels-world-proxy.<your-subdomain>.workers.dev';
```
Then run:
```bash
flutter build web --release
firebase deploy --only hosting
```
