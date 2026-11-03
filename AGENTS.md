# AinkradCoreApp — agent guide

Thin native SwiftUI client for Ainkrad Core (Mac now, iPhone later). Plan and decisions live outside this repo:
`~/Home/Projects/Ainkrad/Docs/Plans/2026-11-03-ainkrad-core-e5-mac-plan.md` (Jira epic KAN-457). Never write docs here.

- `make build` / `make test` / `make run`. The Xcode project is generated from `project.yml`; never edit or commit it.
- `Packages/AinkradClient` is vendored: change it in `AinkradCore` (`make clients`), then `make sync-client`. Never edit it here.
- Visual spec: `Designs/core/ds/proto/mac/` in the project; tokens from `Designs/core/ds/system/`. No business logic in the client.
- PRs target `development`; never commit to `main`/`development` directly. Merge commits only; merging needs an explicit instruction.
- Conventional Commits with a scope. No AI/tool attribution anywhere.
