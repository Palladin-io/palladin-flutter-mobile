# Observed iFirma native fields

On 2026-10-30 the owner authorized an empty-form, metadata-only S22 trace for
`pl.ifirma.ifirmafaktury`, version code 5094. The temporary diagnostic provider
received a request after password focus. The original release provider was
restored and the diagnostic provider removed afterwards. No entered values,
credential data, raw field labels or screenshots are part of this fixture.

The sanitized request visited 27 nodes without hitting its limit. Relevant fields:

| Category | Depth | inputType | autofillType | autofillHints | Enabled | Focused |
|---|---:|---:|---:|---|---|---|
| EDIT_TEXT | 2 | 33 | 1 (TEXT) | username | yes | no |
| EDIT_TEXT | 2 | 129 | 1 (TEXT) | password | yes | yes |
| EDIT_TEXT | 3 | 16385 | 1 (TEXT) | none | no | no |

These fields were visible/focusable with Autofill IDs, no HTML, no domain and
no scheme. The trace does not retain exact parent identities, resource IDs or
class names beyond the categories above. The regression therefore uses a reduced
synthetic tree preserving relevant depth and eligibility, not a claim to reproduce
the complete AssistStructure. IDs and container edges are synthetic; text-only
non-target nodes are omitted. The second test iteration switches focus to username
as a counterfactual, not another claimed physical observation.

`CredentialFieldIdsTest.observedIfirmaSemanticFieldsRemainTargetsRegardlessOfFocusedField`
is GREEN on the existing parser. Both explicit semantic fields are selected and
the disabled field excluded. No label fallback or merchant-specific rule is
necessary for these observed fields. This replaces the earlier inference that the
real request had only a React Native placeholder; that older synthetic fixture
remains useful as a generic fallback regression.

This evidence proves neither that the release service received the same request
nor that its cache, origin resolution, authentication or IME presentation succeeded.
It does not establish the cause of the missing production prompt. A current
release-provider diagnosis is still needed to separate those later boundaries.

## Follow-up on 2026-11-05

S22 with iFirma 3.1.17 (5098) and Palladin Debug18 reproduced no visible
suggestion on username focus, followed by a suggestion on password focus. The
value-free password-focus trace again contained 27 nodes: an enabled text
username (inputType33, explicit username hint, not focused), an enabled current
password (inputType129, explicit password hint, focused), and a disabled extra
text field (inputType16385). No field values were collected.

This does not establish the structure delivered on username focus. Earlier
bounded diagnostic snapshots reaching 128 nodes cannot be attributed to that
login field from their value-free content alone. Do not replace the first-focus
unknown with the password-focus fixture or weaken field eligibility heuristics.
The separate request-handoff failure was reproduced by delayed `hidden` lifecycle
notifications canceling a newly opened request before presentation.
