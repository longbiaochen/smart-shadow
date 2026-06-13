import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";

import type { Config } from "../config.js";
import { normalizeGitHubWebhook } from "./normalize.js";
import { verifyGitHubSignature } from "./verify.js";

export interface GitHubWebhookListenerOptions {
  config: Config["github"];
  secret?: string;
  onMessage: (input: { eventName: string; deliveryId: string; message: ReturnType<typeof normalizeGitHubWebhook> }) => Promise<void>;
}

async function readBody(req: IncomingMessage): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  return Buffer.concat(chunks);
}

function respond(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(`${JSON.stringify(body)}\n`);
}

export class GitHubWebhookListener {
  private server?: Server;

  constructor(private readonly options: GitHubWebhookListenerOptions) {}

  address(): ReturnType<Server["address"]> | undefined {
    return this.server?.address();
  }

  async start(): Promise<void> {
    this.server = createServer(async (req, res) => {
      if (req.method === "GET" && req.url === "/channels/github/healthz") {
        respond(res, 200, { ok: true });
        return;
      }
      if (req.method !== "POST" || req.url !== this.options.config.webhook.path) {
        respond(res, 404, { ok: false, error: "not_found" });
        return;
      }

      const eventName = String(req.headers["x-github-event"] ?? "");
      const deliveryId = String(req.headers["x-github-delivery"] ?? "");
      if (!eventName || !deliveryId) {
        respond(res, 400, { ok: false, error: "missing_github_headers" });
        return;
      }
      if (!this.options.config.events.includes(eventName)) {
        respond(res, 202, { ok: true, ignored: "event_not_allowed" });
        return;
      }

      const rawBody = await readBody(req);
      const signature256 = typeof req.headers["x-hub-signature-256"] === "string" ? req.headers["x-hub-signature-256"] : undefined;
      if (!verifyGitHubSignature({ rawBody, signature256, secret: this.options.secret })) {
        respond(res, 401, { ok: false, error: "invalid_signature" });
        return;
      }

      const payload = JSON.parse(rawBody.toString("utf8")) as Record<string, unknown>;
      const repository = typeof payload.repository === "object" && payload.repository && "full_name" in payload.repository ? String((payload.repository as { full_name?: unknown }).full_name ?? "") : "";
      if (!this.options.config.repositories.includes(repository)) {
        respond(res, 202, { ok: true, ignored: "repository_not_allowed" });
        return;
      }
      const message = normalizeGitHubWebhook({ eventName, deliveryId, payload });
      await this.options.onMessage({ eventName, deliveryId, message });
      respond(res, 200, { ok: true });
    });

    await new Promise<void>((resolve) => this.server?.listen(this.options.config.webhook.port, this.options.config.webhook.host, resolve));
  }

  async stop(): Promise<void> {
    const server = this.server;
    if (!server) return;
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    this.server = undefined;
  }
}
