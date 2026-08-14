# Web Frontend Guide

## Overview

`src/web/` is a plain HTML/CSS/JS chat interface — no framework, no build step — deployed to a Static Web App that's linked to the existing Function App as its backend (rather than using Static Web Apps' own managed Functions).

Files:

- `index.html` — page structure
- `app.js` — chat logic
- `styles.css` — styling, including rendered-Markdown-specific rules
- `staticwebapp.config.json` — routing and authentication configuration

## Authentication

The whole app (`/*`, not just `/api/*`) requires an authenticated session, via `staticwebapp.config.json`'s `azureActiveDirectory` identity provider and a wildcard route rule with `allowedRoles: ["authenticated"]`. Route order matters: the wildcard route must come last, or the more specific `/login`/`/logout` routes stop working.

`/.auth/*` is explicitly exempted from the authenticated-only rule — without this, the OAuth callback itself (which necessarily runs before the user is authenticated) gets blocked by the app's own route rule, producing what looks exactly like an infinite login loop but is actually the callback never being allowed to complete.

Setting up the actual Entra ID app registration this depends on is `bootstrap/setup_swa_auth.sh` — see `docs/bootstrap.md`.

## Conversation state

`conversation_id` is held client-side, in `sessionStorage` (not a bare JS variable, which would lose the conversation on any accidental refresh; not `localStorage`, which would persist indefinitely past the point it's useful). The server (`ChatWithAgent`) is intentionally stateless beyond what the Foundry conversation object itself holds — there's no server-side session store, by design, since this is a single-user tool with no current need for cross-device session access or server-side session listing.

### Conversation growth is unbounded, and that's a real, structural limit — not a bug

Every message resent to the model carries the *entire* conversation so far, including the agent's own past replies, which are detailed by design (its instructions ask for structured, multi-dimension output on every recommendation). As a conversation grows, so does the size of every subsequent request — and this deployment's model capacity (`GlobalStandard`, capacity 10) is deliberately small to control cost. A long-running conversation can eventually exceed what a single request is allowed to use, surfacing as an HTTP 429 from the model deployment.

Confirmed, empirically, that this is genuinely structural rather than transient: the same failure persisted across gaps of 15+ minutes between retries — far longer than a per-minute quota would need to recover if the issue were simply "too much recent traffic." The size of the specific request itself is the problem, not a temporary spike.

**Server-side compaction (`context_management`/`compact_threshold`) was investigated as a potential fix and deliberately not adopted.** It's compatible with the `conversation=` + `agent_reference` pattern this app uses (confirmed — the parameter is validated and processed, not rejected as unrecognized), but triggering it is itself expensive — one observed compaction event cost roughly 5x a normal turn's tokens — and there's no confirmed evidence it actually reduces the *following* turn's cost for this access pattern. Every official example of getting compaction's benefit assumes the caller manually drops pre-compaction items when constructing the next request (the `previous_response_id`/manual-chaining patterns); the `conversation=` pattern replays whatever the server has stored, with no confirmation that old items get pruned automatically. Given a capacity-10 deployment, spending tokens on an expensive operation with unconfirmed payoff isn't worth it — a "New conversation" button is the actual fix in place instead.

The button (`#new-conversation-button` in `index.html`) clears `sessionStorage` and the visible message list — available at any time, not just reactively after a failure, so a conversation can be reset proactively before it grows unwieldy. A collapsible guidance panel (`#conversation-help`, native `<details>`/`<summary>`, no JS) sits just below the header explaining why this happens and what helps, including that asking for something specific tends to get a shorter reply than an open-ended request for a full analysis — deliberately not phrased as "ask shorter questions," since reply length isn't reliably predicted by question length for an agent instructed to always reason across four dimensions on a concrete recommendation.

### Rate-limit errors get a distinct, clean message

`chat_with_agent` in `function_app.py` catches `openai.RateLimitError` specifically, before the generic exception handler, returning `429` with `status: "rate_limited"` and a message pointing at starting a new conversation — rather than the raw API error body reaching the browser. `app.js` checks this `status` field on the thrown error and shows the backend's message directly, bypassing the generic "Something went wrong" wrapper used for genuinely unexpected failures.

## Markdown rendering

The agent's replies are Markdown by design (its instructions ask for structured output — headers, bold text, lists). `app.js` renders assistant messages via `marked.parse()` (loaded from CDN) then `DOMPurify.sanitize()` before setting `innerHTML` — user and system messages stay as plain `textContent`, since they were never the thing producing formatted output and don't need parsing. The agent's replies are ultimately built from Azure resource names and cost figures, not arbitrary user input, so the realistic injection risk is low, but sanitizing before `innerHTML` costs nothing and removes any need to reason about it further.

**A "choppy" rendering complaint turned out not to be a parsing issue at all.** Tested directly against real agent output: `marked.js`'s `breaks` option made zero difference — the agent already reliably uses correct markdown hard-break syntax, and the parser was honoring it correctly either way. The actual cause was CSS: this agent's output is usually structured as many short, blank-line-separated paragraphs (one per service or signal), and each one's vertical margin stacks up. Fixed by tightening `.message.assistant p` margin, not by touching the Markdown parsing at all.

## Visual design

Styling uses a "milk-glass" treatment — an ambient gradient background with semi-transparent, blurred surfaces (`backdrop-filter`) for the guidance panel, message bubbles, and input area. Assistant bubbles deliberately use a *more opaque* glass variant than other surfaces (85% vs. 62%), since that's where dense cost/security data lives and readability has to win over the aesthetic. The header is intentionally left with its original solid styling, untouched by this pass. Contrast ratios were checked against WCAG AA using the actual blended colors (glass over the ambient background), not the flat hex values alone — a first pass on the guidance panel's muted text only cleared the minimum by a hair (4.57:1) and was darkened for a genuine margin (6.61:1) rather than left at a technical pass.

## Deployment

`deploy-web-frontend.yml` — see `docs/workflows.md` for the deployment-token handling (fetched fresh at runtime, never stored) and the dynamic Static Web App lookup.
