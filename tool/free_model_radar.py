#!/usr/bin/env python3
"""Free-model radar: what appeared in (or vanished from) the free catalog.

    python3 tool/free_model_radar.py             # what changed since the snapshot
    python3 tool/free_model_radar.py --update    # accept today's catalog as the baseline
    python3 tool/free_model_radar.py --all       # print every free model, not just the news
    python3 tool/free_model_radar.py --telegram  # also push the news to Telegram

Why a script and not a screen: the package already tells you about new free
models *when you open the Free models screen*. This answers the other question —
"did anything appear while I was not looking?" — without opening the app, and it
needs no API key: `GET /api/v1/models` on OpenRouter is public.

Two things it deliberately does not do:

  * it does not scaffold a GitHub Actions workflow. Adding a scheduled job (and
    the secrets that go with it) is the repo owner's call, not an agent's. The
    script is cron-shaped: run it daily, keep the snapshot committed, and it
    prints nothing when nothing changed. Wire it up whenever you want it.
  * it does not scrape the trackers or the gateway sign-up pages. Those change
    weekly and lie politely; `lib/models/free_source.dart` is the curated index
    of where to look, and this radar only reports the one source that publishes
    a stable machine-readable catalog.

Exit codes: 0 = ran fine (with or without news), 1 = the fetch failed.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT = ROOT / "tool" / "free_models_snapshot.json"
CATALOG_URL = "https://openrouter.ai/api/v1/models"
TIMEOUT_SECONDS = 20


def fetch_catalog() -> list[dict]:
    """Return the free models in OpenRouter's public catalog.

    Free means either a `:free` id suffix or a zero prompt+completion price —
    both shapes exist in the catalog and a model only needs one of them.
    """
    request = urllib.request.Request(
        CATALOG_URL, headers={"Accept": "application/json", "User-Agent": "free-model-radar"}
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        body = json.loads(response.read().decode("utf-8"))

    free: list[dict] = []
    for entry in body.get("data", []):
        model_id = (entry.get("id") or "").strip()
        if not model_id:
            continue
        pricing = entry.get("pricing") or {}
        prompt = str(pricing.get("prompt", "")).strip()
        completion = str(pricing.get("completion", "")).strip()
        zero_priced = prompt in {"0", "0.0"} and completion in {"0", "0.0"}
        if not (zero_priced or model_id.endswith(":free")):
            continue
        free.append(
            {
                "id": model_id,
                "name": entry.get("name") or model_id,
                "contextLength": entry.get("context_length"),
            }
        )
    free.sort(key=lambda model: model["id"])
    return free


def load_snapshot() -> dict:
    if not SNAPSHOT.exists():
        return {"checkedAt": None, "models": []}
    try:
        return json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:  # a corrupt snapshot is not a crash
        print(f"radar: ignoring unreadable snapshot ({error})", file=sys.stderr)
        return {"checkedAt": None, "models": []}


def save_snapshot(models: list[dict]) -> None:
    SNAPSHOT.write_text(
        json.dumps(
            {
                "checkedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "source": CATALOG_URL,
                "models": models,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def send_telegram(message: str) -> bool:
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
    chat_id = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
    if not token or not chat_id:
        print("radar: TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID not set — skipping the push")
        return False
    payload = json.dumps({"chat_id": chat_id, "text": message}).encode("utf-8")
    request = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return response.status == 200
    except (urllib.error.URLError, OSError) as error:
        print(f"radar: telegram push failed ({error})", file=sys.stderr)
        return False


def format_news(added: list[str], removed: list[str]) -> str:
    """The Telegram message: a headline plus one line per model."""
    lines = [f"Free model radar — {len(added)} new, {len(removed)} gone"]
    lines += [f"new: {model_id}" for model_id in added]
    lines += [f"gone: {model_id}" for model_id in removed]
    return "\n".join(lines)


def write_summary(
    path: Path, *, total: int, added: list[str], removed: list[str], baseline: str | None
) -> None:
    """Write a Markdown summary for a CI run's `$GITHUB_STEP_SUMMARY`."""
    lines = [
        "### Free model radar",
        "",
        f"- free models right now: **{total}**",
        f"- new since the last snapshot: **{len(added)}**",
        f"- gone: **{len(removed)}**",
        f"- baseline: `{baseline or 'none yet'}`",
        "",
    ]
    lines += [f"- added `{model_id}`" for model_id in added]
    lines += [f"- gone `{model_id}`" for model_id in removed]
    if not added and not removed:
        lines.append("_nothing changed since the last snapshot_")
    try:
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    except OSError as error:
        print(f"radar: could not write the summary ({error})", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--update", action="store_true", help="save today's catalog as the baseline")
    parser.add_argument("--all", action="store_true", help="list every free model, not just changes")
    parser.add_argument("--telegram", action="store_true", help="push news to Telegram when it exists")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument(
        "--telegram-from",
        metavar="PATH",
        help="send the news already written to a --json file (no second fetch)",
    )
    parser.add_argument(
        "--summary",
        metavar="PATH",
        help="also write a Markdown summary (GitHub Actions: pass $GITHUB_STEP_SUMMARY)",
    )
    args = parser.parse_args()

    if args.telegram_from:
        # The CI workflow diffs once, then sends what it already has — a second
        # fetch could report a different catalog than the run that decided
        # there was news at all.
        try:
            news = json.loads(Path(args.telegram_from).read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            print(f"radar: could not read {args.telegram_from} — {error}", file=sys.stderr)
            return 1
        added = list(news.get("added") or [])
        removed = list(news.get("removed") or [])
        if not added and not removed:
            print("radar: nothing to announce")
            return 0
        message = format_news(added, removed)
        print(message)
        print("radar:", "sent" if send_telegram(message) else "telegram skipped or failed")
        return 0

    try:
        models = fetch_catalog()
    except (urllib.error.URLError, OSError, ValueError) as error:
        print(f"radar: could not read the catalog — {error}", file=sys.stderr)
        return 1

    snapshot = load_snapshot()
    if args.update:
        # Accept today's catalog *before* diffing, so an --update run reports the
        # new baseline instead of dumping every model as "added".
        save_snapshot(models)
        print(f"radar: baseline updated — {len(models)} free models, snapshot {SNAPSHOT.name}")
        snapshot = load_snapshot()

    known = {model["id"] for model in snapshot.get("models", [])}
    current = {model["id"] for model in models}
    added = sorted(current - known)
    removed = sorted(known - current)

    if args.json:
        print(
            json.dumps(
                {
                    "total": len(models),
                    "added": added,
                    "removed": removed,
                    "checkedAt": snapshot.get("checkedAt"),
                },
                indent=2,
            )
        )
    else:
        first_run = not known
        print(f"radar: {len(models)} free models on OpenRouter right now")
        if first_run:
            print("radar: no baseline yet — nothing to compare. Run --update to set one.")
        elif not added and not removed:
            print("radar: no change since the last snapshot")
        for model_id in added:
            print(f"  + {model_id}")
        for model_id in removed:
            print(f"  - {model_id}")
        if args.all:
            for model in models:
                context = model.get("contextLength")
                suffix = f"  ({context:,} ctx)" if isinstance(context, int) else ""
                print(f"    {model['id']}{suffix}")

    if args.summary:
        write_summary(
            Path(args.summary),
            total=len(models),
            added=added,
            removed=removed,
            baseline=snapshot.get("checkedAt"),
        )

    if args.telegram and (added or removed):
        lines = [f"*Free model radar* — {len(added)} new, {len(removed)} gone"]
        lines += [f"new: {model_id}" for model_id in added]
        lines += [f"gone: {model_id}" for model_id in removed]
        send_telegram("\n".join(lines))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
