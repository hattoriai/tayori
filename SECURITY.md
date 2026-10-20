# Security

## Reporting a vulnerability

Do not open a public issue for a security problem. Report it privately
through GitHub: [Report a vulnerability](https://github.com/hattoriai/tayori/security/advisories/new).

Say what an attacker can do, and how: the mount (the admin, the JSON API,
the public page, the MCP server, the ingest or GitHub route), the request
or the payload, and the steps. We answer within a week, agree on a fix
and a date, and credit you in the advisory unless you ask us not to.

## Supported versions

Security fixes are made to the latest release. Tayori is before 1.0, so
a fix is not backported to an earlier minor version.

## What is in scope

Tayori runs in your app, behind your pipelines and your resolver, and
takes requests that any person can craft: the admin's events, the JSON
API and the embed, the public page and its subscription form, the
machine routes for CI and GitHub, and the MCP tools. A problem is in
scope when such a request can:

- show an entry to a reader it is not for: a draft, a scheduled entry,
  or an entry for segments the reader is not in;
- reach the admin, or do there more than the resolver's access allows
  (`:read_only`, or nothing), or more than an MCP token's scopes allow;
- forge a reader token of the embed, an ingest token, an unsubscribe
  link, or a GitHub or webhook signature, or use one past its life;
- run a script in the admin, the news or the public page, from an
  entry, a translation, a change in the inbox or an upload;
- read the encrypted settings (the AI key, the GitHub secret, the
  webhooks' addresses and secrets) or the subscribers' addresses;
- crash the app, or make the server, the database or the model do
  unbounded work.

Who is an admin, and who a reader is, are decided by your resolver and
your pipelines: those are the app's job (see the guides on the admin,
readers and any frontend). What a model writes is a suggestion an admin
accepts; a wrong draft is not a vulnerability.
