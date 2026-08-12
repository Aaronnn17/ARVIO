const http = require("http");
const url = require("url");
const fs = require("fs");
const path = require("path");

function loadSecrets() {
  process.env.IS_LOCAL_DEV = "true";
  process.env.APP_ANON_KEY = (process.env.APP_ANON_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3OiOiJzdXBhYmFzZSIsInJlZiI6InpyZHd2b3J0Y2Zub3lrbHR6dXFmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY3NDU4NzMsImV4cCI6MjA4MjMyMTg3M30.YfKZbSwxGs6_xMd6jkDtn1PKkfuyOHo9qVhUvFRddGU").trim().replace(/\r/g, "");
  try {
    const secretsPath = path.join(__dirname, "..", "secrets.properties");
    if (fs.existsSync(secretsPath)) {
      const content = fs.readFileSync(secretsPath, "utf8");
      content.split("\n").forEach((line) => {
        const trimmed = line.trim();
        if (trimmed && !trimmed.startsWith("#")) {
          const parts = trimmed.split("=");
          const key = parts[0]?.trim();
          const val = parts.slice(1).join("=").trim().replace(/\r/g, "");
          if (key && val && !val.startsWith("your-")) {
            process.env[key] = val;
          }
        }
      });
    }
  } catch (e) {
    // Ignore secrets loading error
  }
}

// Initial load
loadSecrets();

const { handleSimklProxy } = require("./netlify/functions/_backend.js");

const PORT = process.env.PORT || 8888;

const server = http.createServer(async (req, res) => {
  // Re-load secrets dynamically on incoming requests
  loadSecrets();

  // CORS headers
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, apikey, x-user-token");

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  const parsedUrl = url.parse(req.url, true);
  const pathname = parsedUrl.pathname || "";

  // Read request body
  let body = "";
  req.on("data", (chunk) => { body += chunk; });
  req.on("end", async () => {
    try {
      const event = {
        httpMethod: req.method,
        headers: req.headers,
        queryStringParameters: parsedUrl.query || {},
        body: body || null,
        isBase64Encoded: false
      };

      if (pathname.includes("simkl-proxy")) {
        const result = await handleSimklProxy(event);
        const status = result.statusCode || 200;
        console.log(`[${req.method}] ${pathname} -> ${status}`);
        if (status >= 400) {
          console.warn(`  ⚠️ Error (${status}):`, result.body || "(empty body)");
        }
        res.writeHead(status, result.headers || { "Content-Type": "application/json" });
        res.end(result.body || "");
      } else {
        console.log(`[${req.method}] ${pathname} -> 404`);
        res.writeHead(404, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: `Path ${pathname} not found on local server` }));
      }
    } catch (err) {
      console.error("Error handling local request:", err);
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: err.message || "Internal server error" }));
    }
  });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Local Netlify Auth Backend running at http://0.0.0.0:${PORT}`);
  console.log(`Simkl Proxy endpoint available at http://0.0.0.0:${PORT}/.netlify/functions/simkl-proxy`);
});
