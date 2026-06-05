export interface ShadowMessage {
  id: string;
  source: "feishu";
  eventKey: string;
  receivedAt: string;
  sender: {
    id: string;
    name?: string;
  };
  chat: {
    id: string;
    type?: "p2p" | "group" | "unknown";
    name?: string;
  };
  thread: {
    id?: string;
    rootId?: string;
  };
  message: {
    id: string;
    type: "text" | "post" | "image" | "file" | "unknown";
    text: string;
    raw: unknown;
  };
  raw: unknown;
}

export interface KnownProject {
  key: string;
  name: string;
  cwd: string;
  aliases: string[];
}

export interface CandidateThread {
  threadId: string;
  title?: string;
  cwd?: string;
  updatedAt?: string;
  summary?: string;
}

export type DispatchAction = "reply_only" | "resume_thread" | "start_thread" | "ask_user" | "reject";

export interface DispatchDecision {
  action: DispatchAction;
  confidence: number;
  reason: string;
  projectKey?: string;
  cwd?: string;
  targetThreadId?: string;
  targetThreadTitle?: string;
  threadTitle?: string;
  initialPrompt?: string;
  replyText?: string;
  question?: string;
  riskLevel: "low" | "medium" | "high";
  requiresApproval: boolean;
}

export interface MainThread {
  threadId: string;
  cwd: string;
  title: string;
}

export interface ThreadBinding {
  codexThreadId: string;
  projectKey: string;
  cwd: string;
  updatedAt: string;
}

export interface ProcessedMessage {
  processedAt: string;
  status: string;
}

export interface RegistryData {
  version: 1;
  mainThread: MainThread;
  projects: KnownProject[];
  bindings: Record<string, ThreadBinding>;
  processedMessages: Record<string, ProcessedMessage>;
}
