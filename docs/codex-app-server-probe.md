# Codex App Server Probe

Date: 2026-06-05

## Local versions

```text
codex --version
codex-cli 0.136.0-alpha.2
```

The managed local app-server reports:

```json
{
  "status": "running",
  "backend": "pid",
  "managedCodexPath": "/Users/longbiao/.codex/packages/standalone/current/codex",
  "managedCodexVersion": "0.136.0",
  "socketPath": "/Users/longbiao/.codex/app-server-control/app-server-control.sock",
  "cliVersion": "0.136.0-alpha.2",
  "appServerVersion": "0.136.0"
}
```

## CLI command surface

`codex app-server --help` exposes an experimental local app server:

```text
codex app-server [OPTIONS] [COMMAND]
  daemon
  proxy
  generate-ts
  generate-json-schema

--listen <URL>
  stdio://, unix://, unix://PATH, ws://IP:PORT, off
```

`codex remote-control --help` exposes daemon lifecycle commands:

```text
codex remote-control start
codex remote-control stop
```

`codex exec --help` and `codex exec resume --help` confirm the fallback syntax:

```bash
codex exec --cd <project_path> --sandbox workspace-write "<task>"
codex exec --cd <project_path> --sandbox workspace-write resume <session_id> "<task>"
```

Note: `--cd` belongs before the `resume` subcommand for this CLI version.

## App Server protocol findings

Schema generation works:

```bash
codex app-server generate-json-schema --experimental --out /tmp/codex-app-schema-smart-shadow
codex app-server generate-ts --experimental --out /tmp/codex-app-ts-smart-shadow
```

The generated experimental protocol includes:

- `thread/start`
- `thread/resume`
- `thread/list`
- `turn/start`
- `turn/completed`
- `item/agentMessage/delta`
- `item/completed`

HTTP/WebSocket boundary was verified with:

```bash
codex app-server --listen ws://127.0.0.1:48765
```

Observed endpoints:

```text
GET /readyz  -> HTTP/1.1 200 OK
GET /healthz -> HTTP/1.1 200 OK
WebSocket /  -> HTTP/1.1 101 Switching Protocols
```

A raw WebSocket JSON-RPC `initialize` request returned a JSON-RPC result. This confirms that an external local client can call the App Server over loopback WebSocket.

## Capability matrix

| Capability | Current result |
| --- | --- |
| Start local app-server | Supported via `codex app-server --listen ws://127.0.0.1:<port>` and daemon commands |
| External HTTP/WebSocket prompt path | WebSocket JSON-RPC is usable on loopback; no stable REST prompt API found |
| Specify project path | Supported by `thread/start.cwd`, `thread/resume.cwd`, and `turn/start.cwd` |
| Create new session | Supported by `thread/start` |
| Resume existing session | Supported by `thread/resume` with `threadId`; fallback `codex exec resume` also works |
| Send prompt | Supported by `turn/start` after `thread/start` or `thread/resume` |
| Capture model output | Supported through `item/agentMessage/delta`; `item/completed` is a fallback source |

## shadowd experiment result

Implemented in `/Users/longbiao/Projects/smart-shadow/shadowd`.

Verified mock App Server run:

```bash
python3 shadowd/shadowd.py --mock "devops 只回复一句 shadowd app-server 输出采集正常，不修改文件"
```

Result:

```text
shadowd -> Codex app-server OK
shadowd app-server 输出采集正常
```

Verified fallback exec run:

```text
backend=exec
ok=true
returncode=0
log=/Users/longbiao/Projects/smart-shadow/shadowd/logs/codex-exec-1780634940.json
```

## Feishu/Lark CLI findings

Installed CLI name:

```text
/Users/longbiao/.npm-global/bin/lark-cli
```

`feishu` and `lark` command names are not present in the current shell PATH.

`lark-cli doctor` reports:

```text
ok=true
cli_version=1.0.48
bot_identity=ready
user_identity=ready
endpoint_open=reachable
endpoint_mcp=reachable
```

IM capabilities:

- Read chat messages: `lark-cli im +chat-messages-list`
- Send messages: `lark-cli im +messages-send`
- Reply to messages: `lark-cli im +messages-reply`
- Consume events: `lark-cli event consume im.message.receive_v1`

The minimal `shadowd` implementation uses polling when `feishu.chat_id` is configured. Mock mode is available without chat configuration.

## Boundaries

- App Server API is marked experimental by the CLI and generated protocol.
- No stable public REST prompt API was found.
- The implemented App Server path uses loopback WebSocket JSON-RPC only.
- `shadowd` starts a short-lived App Server process per Codex task for the experiment. A product path should manage a durable service and reconnect logic.
- High-risk messages are routed to `plan_then_confirm` before Codex execution.
