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

## Markdown rendering

The agent's replies are Markdown by design (its instructions ask for structured output — headers, bold text, lists). `app.js` renders assistant messages via `marked.parse()` (loaded from CDN) then `DOMPurify.sanitize()` before setting `innerHTML` — user and system messages stay as plain `textContent`, since they were never the thing producing formatted output and don't need parsing. The agent's replies are ultimately built from Azure resource names and cost figures, not arbitrary user input, so the realistic injection risk is low, but sanitizing before `innerHTML` costs nothing and removes any need to reason about it further.

## Deployment

`deploy-web-frontend.yml` — see `docs/workflows.md` for the deployment-token handling (fetched fresh at runtime, never stored) and the dynamic Static Web App lookup.
