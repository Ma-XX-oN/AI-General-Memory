from pathlib import Path

path = Path('scripts/AI-transcript.py')
text = path.read_text(encoding='utf-8')
marker = 'class ChatGPTSessionStore(SessionStore):\n'
assert marker in text

helper = r'''def _cg_order_records_by_uap(records):
  """Return ChatGPT records grouped by API UAP identity in User-anchor order."""
  anchors = []
  for index, rec in enumerate(records):
    if rec.get("author", {}).get("role") != "user":
      continue
    metadata = rec.get("metadata", {}) if isinstance(rec.get("metadata"), dict) else {}
    anchors.append({
      "ordinal": len(anchors),
      "index": index,
      "id": rec.get("id"),
      "exchange": metadata.get("turn_exchange_id"),
      "working": metadata.get("working_turn_id"),
    })

  if not anchors:
    return records
  if not any(anchor["exchange"] or anchor["working"] for anchor in anchors):
    return records

  exchange_map = {}
  working_map = {}
  anchor_by_index = {anchor["index"]: anchor["ordinal"] for anchor in anchors}
  for anchor in anchors:
    if anchor["exchange"]:
      exchange_map.setdefault(anchor["exchange"], []).append(anchor["ordinal"])
    if anchor["working"]:
      working_map.setdefault(anchor["working"], []).append(anchor["ordinal"])

  primary = []
  for index, rec in enumerate(records):
    if index in anchor_by_index:
      primary.append(["exact", anchor_by_index[index]])
      continue
    metadata = rec.get("metadata", {}) if isinstance(rec.get("metadata"), dict) else {}
    exchange = exchange_map.get(metadata.get("turn_exchange_id"), [])
    working = working_map.get(metadata.get("working_turn_id"), [])
    candidates = sorted(set(exchange + working))
    disagreement = len(exchange) == 1 and len(working) == 1 and exchange[0] != working[0]
    if disagreement or len(candidates) > 1:
      primary.append(["conflict", None])
    elif len(candidates) == 1:
      primary.append(["exact", candidates[0]])
    else:
      primary.append(["unresolved", None])

  def identifier_scalars(rec):
    found = []
    seen = set()
    freeform = {"text", "parts", "thinking", "summary", "message", "prompt", "output", "input", "content"}
    def walk(value, depth=0):
      if depth > 8 or value is None:
        return
      if isinstance(value, list):
        for child in value[:12]:
          walk(child, depth + 1)
        return
      if not isinstance(value, dict) or id(value) in seen:
        return
      seen.add(id(value))
      for key, child in value.items():
        if isinstance(child, (dict, list)):
          if key not in freeform:
            walk(child, depth + 1)
          continue
        if key in freeform or isinstance(child, bool):
          continue
        if not isinstance(child, (str, int, float)):
          continue
        if isinstance(child, str) and len(child) > 256:
          continue
        if re.search(r"(?:^id$|_id$|_ids$|call|parent|source|reference|tool|exchange|working|request|response)", key, re.I):
          found.append(child)
    walk(rec)
    return found

  exact_message_to_uap = {}
  exact_identifiers = {}
  for index, (kind, uap) in enumerate(primary):
    if kind != "exact":
      continue
    rec = records[index]
    if rec.get("id"):
      exact_message_to_uap[str(rec["id"])] = uap
    for value in identifier_scalars(rec):
      exact_identifiers.setdefault((type(value).__name__, str(value)), set()).add(uap)

  for index, (kind, _uap) in enumerate(primary):
    if kind != "unresolved":
      continue
    rec = records[index]
    refs = set()
    for value in identifier_scalars(rec):
      uap = exact_message_to_uap.get(str(value))
      if uap is not None:
        refs.add(uap)
    rec_id = rec.get("id")
    if rec_id is not None:
      refs.update(exact_identifiers.get((type(rec_id).__name__, str(rec_id)), set()))

    before = next((primary[i][1] for i in range(index - 1, -1, -1) if primary[i][0] == "exact"), None)
    after = next((primary[i][1] for i in range(index + 1, len(primary)) if primary[i][0] == "exact"), None)
    bounded = before if before is not None and before == after else None
    role = rec.get("author", {}).get("role")
    hidden = bool((rec.get("metadata") or {}).get("is_visually_hidden_from_conversation"))

    if len(refs) > 1 or (len(refs) == 1 and bounded is not None and next(iter(refs)) != bounded):
      primary[index] = ["conflict", None]
    elif len(refs) == 1:
      primary[index] = ["linked", next(iter(refs))]
    elif bounded is not None and role != "system":
      primary[index] = ["bounded", bounded]
    elif role == "system" and hidden:
      primary[index] = ["global", None]
    else:
      primary[index] = ["unresolved", None]

  conflicts = [i for i, item in enumerate(primary) if item[0] == "conflict"]
  unresolved = [i for i, item in enumerate(primary) if item[0] == "unresolved"]
  if conflicts or unresolved:
    raise ValueError(
      f"ChatGPT UAP grouping failed: {len(conflicts)} conflict(s), {len(unresolved)} unresolved record(s)"
    )

  groups = [[] for _ in anchors]
  for index, (_kind, uap) in enumerate(primary):
    if uap is not None:
      groups[uap].append(records[index])
  for ordinal, group in enumerate(groups):
    users = [rec for rec in group if rec.get("author", {}).get("role") == "user"]
    if len(users) != 1:
      raise ValueError(f"ChatGPT UAP {ordinal + 1} has {len(users)} User records")
  return [rec for group in groups for rec in group]


'''
text = text.replace(marker, helper + marker, 1)
needle = '''    headings = _headings()\n    policy = _display_policy()\n'''
replacement = '''    for idx, rec in enumerate(lines):\n      rec.setdefault("_rec_no", idx + 1)\n    lines = _cg_order_records_by_uap(lines)\n\n    headings = _headings()\n    policy = _display_policy()\n'''
assert needle in text
text = text.replace(needle, replacement, 1)
path.write_text(text, encoding='utf-8')
