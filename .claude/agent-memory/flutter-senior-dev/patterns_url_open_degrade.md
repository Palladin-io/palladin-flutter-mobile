# URL "open" actions degrade to copy-the-URL

`url_launcher` is **not** a direct dependency of this app (only `url_launcher_web`
appears transitively in the pub tree — do not import `package:url_launcher/...`).

Convention: any "open in browser" affordance (open_in_new icon) **copies the URL
to the clipboard** instead of launching it, and shows the copy snackbar. Precedents:
- `api_keys/.../generate_api_key_sheet.dart` → `_LinkText` (comment states the rule)
- `vault/.../entry_details_tab.dart` read-only URL field → open button calls copy

If real launching is ever needed, add `url_launcher` to `pubspec.yaml` first.
