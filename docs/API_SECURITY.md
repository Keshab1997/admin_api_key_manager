# API security — the key pool, today and next

**Status: design note, not implemented.** Written down because the trade-off is
in the code and in several README files, and a trade-off with no plan out of it
turns into a habit.

## Where the keys live today

```
Firestore admin_api_keys  ──read by every signed-in client──▶  provider API
        ▲                                                          ▲
        │ admin writes (rules)                                     │
   admin device                                            end-user device
```

- `admin_api_keys` documents hold live provider keys, in plain text.
- The Firestore rules ship in this repository allow **read for every signed-in
  user**. The admin screen is protected; the secrets are not.
- `ApiKeyManager` selects, cools down and health-checks those keys **on the
  client**, then the client calls the provider directly.
- Which means: anyone who installs the app and signs in can read your keys out
  of Firestore and spend your provider quota. If the app were public, that is a
  bill, not a hypothetical.

This is deliberate for the MVP — one owner, one admin, a handful of keys, an app
that is not on the Play Store yet. It is written down here so it cannot be
mistaken for a design that is finished.

## What it costs to keep it

| Risk | Today | Mitigation while it stays this way |
|---|---|---|
| Key exfiltration from a device | possible | Use keys you can revoke and rotate; never a shared production key |
| Quota burn by a third party | possible | Per-key spend limits at the provider, not in the app |
| Leak through a build | possible | No key in the repository, in a test fixture, or in a log |
| Silent key death | handled | `ApiKeyManager` auto-deactivates after 3 auth failures |

## The direction out: a server-side proxy

The endpoint that needs protecting is **the AI call**, not the key document.
Once the call goes through a proxy, the key never leaves the server and every
per-device protection here becomes a server-side concern.

```
app ──POST /reply (Firebase ID token)──▶ Cloud Function ──▶ provider
                        │                     │
                        │                     └─ holds the keys (Secret Manager)
                        └─ rate limit per uid, allowlist, request size cap
```

### What moves, and what stays

| Concern | Today (client) | After (proxy) |
|---|---|---|
| Key storage | Firestore, client-readable | Secret Manager / server env |
| Key selection, failover, cooldowns | `KeyPoolSelector` + `ApiKeyManager` | the same logic, server-side (this file's models move, not get thrown away) |
| Health checks | every device pings | one scheduled job |
| Error logs | client writes `api_error_logs` | proxy writes them; the admin screen keeps working |
| Rate limiting | none | per-uid quota, enforced once |
| Admin UI | `AdminApiKeysScreen` | unchanged, if the proxy keeps reading `admin_key_groups` |

### The four things that have to be decided first

1. **Auth model.** Firebase ID token on every call; the function verifies it and
   derives the uid. Anonymous use would need an App Check token instead.
2. **Abuse limits.** A per-uid daily cap and a per-ip burst cap. Without one,
   the proxy just moves the bill from the provider to you.
3. **What the client may send.** Today the client builds the whole prompt. A
   proxy that takes `messages[]` verbatim is an open relay for any prompt; one
   that takes `{message, tone, language}` and builds the prompt server-side is
   not. The second is the target — `PromptBuilder` moves to the function.
4. **Guest mode.** The app's rule is that no `google-services.json` must never
   break a screen. With a proxy, guest mode means "no AI, explain why", which is
   what it already says.

### Migration order (each step shippable)

1. Add the proxy function; leave the client path working as a fallback.
2. Move `PromptBuilder` server-side and have the client send `{message, tone,
   language}`. No behaviour change visible to the user.
3. Point `ReplyRepository` at the proxy; keep the key-pool path behind a flag.
4. Move the cooldown/health logic server-side; the admin screen keeps writing
   `admin_key_groups`, which the function reads.
5. Tighten the rules: `admin_api_keys` becomes **no client read**. This is the
   step that actually fixes the leak, and it must come last — flipping it first
   breaks every device that is still on the client path.

## Rules for this repository meanwhile

- No new client read of `admin_api_keys`. If a feature needs the pool, it needs
  the proxy.
- No key in a log line, a test fixture, a screenshot, or a commit message.
- The README's rule sketch stays labelled as an MVP trade-off, not as guidance.
