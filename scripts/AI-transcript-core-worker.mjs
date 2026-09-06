#!/usr/bin/env node

import { createInterface } from 'node:readline';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const CORE_COMMIT = '4ee65bab8f6a4c2f9caf55f2ff342d903108f8de';

function coreRootPath() {
  const configured = process.env.AI_CONVERSATION_CORE;
  if (configured && !configured.endsWith('.js')) return path.resolve(configured);
  return path.resolve(import.meta.dirname, '..', 'dependencies', 'AIConversationCore');
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

function eventProjection(event, projectionByIndex) {
  const inherited = event?.projection ?? {};
  const supplied = projectionByIndex.get(event.source_index) ?? {};
  const base = {
    ...inherited,
    ...supplied,
    heading_metadata: {
      ...(inherited.heading_metadata ?? {}),
      ...(supplied.heading_metadata ?? {})
    },
    colors: {
      ...(inherited.colors ?? {}),
      ...(supplied.colors ?? {})
    }
  };
  if (!Object.keys(base.heading_metadata).length) delete base.heading_metadata;
  if (!Object.keys(base.colors).length) delete base.colors;

  const relatedSources = {};
  for (const [name, source] of Object.entries(event.relationships ?? {})) {
    if (!source || typeof source !== 'object' || !Number.isInteger(source.record_index)) continue;
    const related = projectionByIndex.get(source.record_index);
    if (related) relatedSources[name] = related;
  }
  return Object.keys(relatedSources).length
    ? { ...base, related_sources: relatedSources }
    : base;
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

  const options = {
    includeRolledBackTurns: request?.options?.includeRolledBackTurns === true
  };
  const loaded = core.loadConversationSources({
    provider: request.provider,
    primarySource: { records: request.records },
    supplementarySources: request.supplementary_sources ?? {},
    options
  });
  const projectionByIndex = new Map(
    Object.entries(request.projections ?? {}).map(([index, projection]) => [Number(index), projection])
  );
  let events = loaded.events.map(event => {
    const projection = eventProjection(event, projectionByIndex);
    return Object.keys(projection).length ? { ...event, projection } : event;
  });
  if (Array.isArray(request.source_indexes)) {
    const allowed = new Set(request.source_indexes);
    events = events.filter(event =>
      event.content_type === 'model_change' || allowed.has(event.source_index));
  }

  return {
    ok: true,
    core_commit: CORE_COMMIT,
    markdown: core.renderCanonicalMarkdown(events),
    ...(loaded.session_metadata ? { session_metadata: loaded.session_metadata } : {})
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
