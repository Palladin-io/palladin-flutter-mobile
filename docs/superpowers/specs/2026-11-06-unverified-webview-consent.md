# One-operation consent for unverified app WebViews

Owner approved a visible warning and controlled choice instead of silent denial.
Android non-browser current-credential forms reporting exactly one valid HTTPS
host may use explicit MANUAL_WEB selection when association is UNVERIFIED.
Query failures, disabled links, browsers, malformed/ambiguous/HTTP origins remain
rejected. Successful no-App-Links is UNVERIFIED, never trusted.

Reuse the existing authenticated Entries picker and confirmation. Show installed
app label/package, selected Entry and exact reported host; require Fill once.
Search never expands beyond that host. Bind consent to request, selection and
source epoch; retain signature, lock/revoke/lease and one-use checks at completion.
Do not persist associations or consent. Do not enable save/generation for this mode.
Keep iOS behavior unchanged: it has a different OS-provided origin boundary.

Alternatives: removing verification creates phishing risk; hard denial prevents
legitimate unsupported integrations. The owner chose explicit one-time consent.
Release gate remains physical Debug test before cloud review or publication.
