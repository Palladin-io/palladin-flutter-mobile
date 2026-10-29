# Observed Binance virtual username — 2026-10-29

An owner-authorized metadata-only diagnostic AutofillService inspected the empty
login form of `com.binance.dev` on a physical Samsung Galaxy S22 Ultra, Android
API 36. The diagnostic accepted only that package, returned no FillResponse,
read no field text or AutofillValue, and retained its bounded metadata in memory
for a shell dump. It had no Internet/storage permissions. The diagnostic was
removed and the previously selected Palladin provider restored after capture.

| AssistStructure node | Observed metadata |
| --- | --- |
| WebView container | Class category WEB_VIEW; inputType 0; autofillType 0; visible, enabled, focused; no domain/scheme |
| Focused virtual field | Class category OTHER; inputType 0; autofillType 1 (text); autofillHints `[username]`; visible, enabled, focused |
| Field origin | `https`, `www.binance.com`; exact OS association NOT_DECLARED |

The package's separately observed verified hosts were `accounts.binance.com`,
`app.binance.com`, and `app.binance.info`. These do not authorize the reported
`www.binance.com` origin. Production provider diagnostics reported
REJECTED / passwordCount 0 / domains ONE / origin UNVERIFIED / cache NOT_CHECKED.
That rejection precedes cache matching and is consistent with the origin policy.
It is not evidence of a failed username classifier or absent credential cache.

Accessibility earlier described an EditText with a generated resource identifier.
Accessibility and AssistStructure are different interfaces: the credential field
actually delivered to AutoFill was a virtual text node with an explicit username
hint. The probe intentionally categorized rather than recorded arbitrary class
names, so OTHER does not identify its precise Java class. It did not capture
HTML attributes, labels, idEntry, focusability, values or the later password step.

`ObservedVirtualUsernameTest` reduces this observation to a WebView containing
that virtual field and exercises the production generic parser and origin policy.
Noncredential layout/text nodes are omitted. The exact verified-host positive
case and OTP/search/confirmation/hidden/disabled/nontext/HTTP variants are
synthetic counterfactuals, not additional phone observations. They prove that
explicit semantics recognize the username independently of native inputType,
while only authority for the exact HTTPS host permits the web origin. The tests
use synthetic signer/statement material for the exact-host Digital Asset Links
positive case. The separately inspected public HTTPS statement contained the
credential-sharing relation for the installed package/signing certificate, but
these regressions do not depend on a live merchant endpoint or claim successful
physical filling. No merchant-specific production rule is added.
