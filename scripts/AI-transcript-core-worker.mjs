#!/usr/bin/env node

import { createInterface } from 'node:readline';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const CORE_COMMIT = 'cdad429007754f7c1ce1eb5ec3b33924ffb0aee1';

function coreEntryPath() {
  const configured = process.env.AI_CONVERSATION_CORE;
  if (configured) {
    return configured.endsWith('.js')
      ? configured
      : path.join(configured, 'src', 'index.js');
  }
  return path.resolve(import.meta.dirname, '..', '..', 'AIConversationCore', 'src', 'index.js');
}

const core = await import(pathToFileURL(coreEntryPath()).href);

function adapt(provider, records) {
  if (provider === 'chatgpt') return core.adaptChatGPTRecords(records);
  if (provider === 'claude') return core.adaptClaudeRecords(records);
  if (provider === 'codex') return core.adaptCodexRecords(records);
  throw new Error(`Unsupported provider: ${provider}`);
}

function render(request) {
  if (request?.operation === 'ping') {
    return { ok: true, core_commit: CORE_COMMIT };
  }
  if (request?.operation !== 'render') {
    throw new Error(`Unsupported operation: ${request?.operation}`);
  }
  if (!Array.isArray(request.records)) {
    throw new TypeError('render request records must be an array');
  }

  let events = adapt(request.provider, request.records);
  if (Array.isArray(request.source_indexes)) {
    const allowed = new Set(request.source_indexes);
    events = events.filter(event => allowed.has(event.source_index));
  }
  return {
    ok: true,
    core_commit: CORE_COMMIT,
    markdown: core.renderCanonicalMarkdown(events)
  };
}

const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of input) {
  if (!line.trim()) continue;
  try {
    process.stdout.write(`${JSON.stringify(render(JSON.parse(line)))}\n`);
  } catch (error) {
    process.stdout.write(`${JSON.stringify({
      ok: false,
      error: error instanceof Error ? error.message : String(error)
    })}\n`);
  }
}
