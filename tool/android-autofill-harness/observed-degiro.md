# DEGIRO Android metadata regression

Physical Samsung S22, Android16, installed package `nl.degiro.trader`.
Debug35 first fresh request2026-11-08 15:14:26: six nodes; focused HTML text
input with username hint, HTML password input, both enabled/visible with
AUTOFILL_TYPE_TEXT and native inputType0. Parser returns username1/password1;
request has one domain. Domain value and credential values were not captured.
Service at15:14:27 (DEGIRO focused) reports REJECTED/QUERY_UNAVAILABLE before
candidate lookup. This is not a field classification regression.

Package visibility check from actual Debug35 provider UID:
- shell sees installed target;
- run-as provider sees itself and Chrome (positive controls);
- run-as provider cannot resolve the installed DEGIRO package.
`verify_package_visibility.py` expected visibility and failed before the manifest
change. No app-private data or credentials were read; paths are reduced to booleans.
The generic MAIN/LAUNCHER query addresses requesting apps with no HTTP(S) intents.
Visibility is not a domain association and does not authorize a fill. The new
MANUAL_WEB path still requires exact-host selection and one-use explicit consent.

Physical post-fix package visibility and actual fill acceptance must be recorded
separately. A visible package does not prove the OS accepted a returned Dataset.

Debug36 post-install2026-11-08: the same run-as provider-UID probe now passes
installed=true, provider_uid_control=true, target_visible_to_provider=true.
This confirms generic manifest visibility repair on S22. Actual suggestion,
manual-web consent and credential delivery remain pending physical acceptance.
