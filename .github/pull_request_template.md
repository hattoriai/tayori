## Why

<!-- The problem this solves, for whom, and what happened before it (an error, a crash, an entry shown to the wrong readers). -->

Fixes #<!-- the issue; see CONTRIBUTING.md for when a pull request needs one -->

## What

<!-- The change, in a few lines. -->

## How it was tested

<!-- The tests added, on SQLite and PostgreSQL if it touches the database, and what you ran by hand (mix dev). -->

## Checklist

- [ ] One change: anything unrelated is in its own pull request.
- [ ] A bug fix has a test that fails on `main` and passes here.
- [ ] `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix docs`, `mix test --exclude build` and `mix dialyzer` pass.
- [ ] `npm run typecheck` (in `assets/`), `mix test.js` and `mix test.e2e` pass, for a change to `assets/` or to what the browser sees.
- [ ] The guides and the unreleased section of `CHANGELOG.md` are updated, for a change a user can see.
- [ ] Says so here if it changes the public API, the tables, the JSON of the API or of a webhook, or what Tayori does today.
- [ ] No changes to the version or to built files in `priv/static` (the maintainers keep those).
