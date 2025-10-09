# HOSS Integration Phases 4–6 – Test Report Template

Use this template to capture evidence once Demon delivers ritual alias support (#245) and the HTTP ritual API (#243).

## Phase 4 – CLI Ritual Alias

- **Command:** `demonctl run hoss:hoss-validate <args>`
- **Environment:** `<cluster / version>`
- **Result Envelope Path:** `<attach link>`
- **Highlights:**
  - Alias resolution succeeded (`demonctl run <app>:<ritual>`)
  - Envelope validated against `hoss/validate.result`
  - Diagnostics / warnings (if any)
- **Inputs:**
  - `<app>` name: `hoss`
  - `<ritual>` alias: `hoss-validate`
  - Optional flags: `--strict`, `--fab-config`

## Phase 5 – HTTP Ritual API

- **Endpoint:** `POST /api/v1/rituals/hoss-validate/runs`
- **Payload:**
  ```json
  {
    "input": {
      "diagramPath": "samples/topology-min.yaml",
      "strict": false
    }
  }
  ```
- **Run ID:** `<value>`
- **Status Polling:** `GET /api/v1/runs/<runId>` (attach response)
- **Envelope Retrieval:** `GET /api/v1/runs/<runId>/envelope` (attach response)
- **Validation:** `demonctl contracts validate-envelope <path>`
- **Inputs:**
  - HTTP headers: `Authorization`, `Content-Type: application/json`
  - Expected response codes: `202 Accepted` (start), `200 OK` (status/envelope)

## Phase 6 – Operate UI Card Sanity

- **Operate URL:** `<https://...>`
- **Card:** `HOSS Validation`
- **Screenshots:** `<attach>`
- **Observed Fields:** status, counts.validated, counts.warnings, counts.failures, tool.version, tool.imageDigest, timestamp
- **Notes:** `<UI quirks, latency, etc.>`
- **Inputs:**
  - Test account / token: `<user>`
  - Filters applied: `<filters>`

## Follow‑ups & Risks

- `[ ]` `<description>`
- `[ ]` `<description>`

## Attachments

- Phase 4 logs: `<link>`
- Phase 5 logs: `<link>`
- Phase 6 screenshots: `<link>`
