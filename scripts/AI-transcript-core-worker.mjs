#!/usr/bin/env node

import { createInterface } from 'node:readline';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const CORE_COMMIT = 'ee1bd128c98dc381688667033c77e007d64148e4';

function coreRootPath() {
  const configured = process.env.AI_CONVERSATION_CORE;
  if (configured && !configured.endsWith('.js')) return path.resolve(configured);
  return path.resolve(import.meta.dirname, '..', '..', 'AIConversationCore');
}

function coreEntryPath() {
  const configured = process.env.AI_CONVERSATION_CORE;
  if (configured?.endsWith('.js')) return configured;
  return path.join(coreRootPath(), 'src', 'index.js');
}

function verifyCorePin() {
  const configured = process.env.AI_CONVERSATION_CORE;
  if (configured?.endsWith('.js')) {
    throw new Error('AI_CONVERSATION_CORE must name the pinned AIConversationCore repository, not a JavaScript file');
  }
  let actual;
  try {
    actual = execFileSync('git', ['-C', coreRootPath(), 'rev-parse', 'HEAD'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    }).trim();
  } catch (error) {
    throw new Error(`Cannot verify AIConversationCore checkout at ${coreRootPath()}: ${error.message}`);
  }
  if (actual !== CORE_COMMIT) {
    throw new Error(`AIConversationCore commit mismatch: expected ${CORE_COMMIT}, found ${actual}`);
  }
}

verifyCorePin();
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

  const projectionByIndex = new Map(
    Object.entries(request.projections ?? {}).map(([index, projection]) => [Number(index), projection])
  );
  let events = adapt(request.provider, request.records).map(event => {
    const projection = projectionByIndex.get(event.source_index);
    return projection ? { ...event, projection } : event;
  });
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
