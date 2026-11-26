"""Build isolated visual experiments from the actual Flutter preview widgets.

Only disposable source copies are patched. The working app and its default
preview stay unchanged. Run after accepting a new preview baseline to refresh
the comparison; inspect the variants before adopting any recipe in product code.
"""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FLUTTER = shutil.which("flutter") or "/Users/patryk/Sdk/flutter/bin/flutter"
OUTPUT = ROOT / "build/mobile-variants"
RECIPES = {
    "a": dict(inset=14, row=12, title=14, body=12, section=16, field=12, control=44),
    "b": dict(inset=16, row=12, title=14, body=12, section=16, field=12, control=44),
    "c": dict(inset=16, row=16, title=15, body=13, section=20, field=16, control=48),
}


def replace(root, file, old, new):
    path = root / file
    text = path.read_text()
    if old not in text:
        raise RuntimeError(f"Preview baseline changed: {file}: {old!r}")
    path.write_text(text.replace(old, new))


def recipe(root, name, values):
    def patch(file, old, new):
        replace(root, file, old, new)

    spacing = "lib/core/theme/app_spacing.dart"
    for token, old, new in [
        ("cardPadding", 14, values["inset"]),
        ("headerGap", 12, values["field"]),
        ("section", 16, values["section"]),
        ("fieldGap", 12, values["field"]),
        ("controlHeight", 44, values["control"]),
    ]:
        patch(spacing, f"{token} = {old};", f"{token} = {new};")
    entries = "lib/features/vault/presentation/widgets/entry_list_card.dart"
    patch(entries, "vertical: AppSpacing.md", f'vertical: {values["row"]}')
    patch(entries, "fontSize: compact ? 14 : 15", f'fontSize: compact ? {values["title"]} : 15')
    patch(entries, "fontSize: compact ? 12 : 13", f'fontSize: compact ? {values["body"]} : 13')
    patch(entries, "SizedBox(width: AppSpacing.innerGap)", "SizedBox(width: AppSpacing.innerGap)")
    if name != "a":
        patch(entries, "SizedBox(height: AppSpacing.xxs)", "SizedBox(height: AppSpacing.xs)")
    agents = "lib/features/agents/presentation/widgets/agent_card.dart"
    patch(agents, "vertical: AppSpacing.lg,", f'vertical: {values["row"]},')
    patch(agents, "fontSize: 14,", f'fontSize: {values["title"]},')
    patch(agents, "fontSize: 12,", f'fontSize: {values["body"]},')
    logs = "lib/features/audit/presentation/widgets/audit_log_row.dart"
    patch(logs, "padding: const EdgeInsets.symmetric(\n            horizontal: AppSpacing.cardPadding,\n            vertical: AppSpacing.md,\n          )",
          f'padding: const EdgeInsets.symmetric(horizontal: AppSpacing.cardPadding, vertical: {values["row"]})')
    patch(logs, "fontSize: 14,", f'fontSize: {values["title"]},')
    # Use the same neutral tab type ramp instead of the custom Agent weight.
    agent_detail = "lib/features/agents/presentation/widgets/agent_detail_body.dart"
    patch(agent_detail, "fontWeight: FontWeight.w500",
          "fontWeight: FontWeight.w500")
    patch(agent_detail, "borderRadius: BorderRadius.circular(6)",
          "borderRadius: BorderRadius.circular(6)")
    patch(agent_detail, "vertical: AppSpacing.innerGap", "vertical: AppSpacing.innerGap")
    # Inbox retains its card structure; shared tokens alone set its rhythm.
    if name == "c":
        header = "lib/core/widgets/list_screen_header.dart"
        patch(header, "fontSize: 16,", "fontSize: 18,")
        fields = "lib/features/onboarding/presentation/widgets/onboarding_text_field.dart"
        patch(fields, "fontSize: 13,", "fontSize: 14,")


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="palladin-mobile-variants-") as temp:
        base = Path(temp)
        for name, values in RECIPES.items():
            work = base / name
            work.mkdir()
            for folder in ("lib", "assets", "web", "design"):
                shutil.copytree(ROOT / folder, work / folder)
            for file in ("pubspec.yaml", "pubspec.lock", ".metadata",
                         ".flutter-plugins-dependencies", "l10n.yaml"):
                if (ROOT / file).exists():
                    shutil.copy2(ROOT / file, work / file)
            (work / ".dart_tool").mkdir()
            for file in ("package_config.json", "package_graph.json"):
                shutil.copy2(ROOT / ".dart_tool" / file, work / ".dart_tool" / file)
            recipe(work, name, values)
            replace(work, "lib/core/router/app_router.dart",
                    "initialLocation: '/login'",
                    "initialLocation: Uri.base.queryParameters['screen'] ?? '/entries'")
            replace(work, "design/mobile/main.dart",
                    "themeMode: context.watch<ThemeCubit>().state",
                    "themeMode: Uri.base.queryParameters['theme'] == 'light' ? ThemeMode.light : ThemeMode.dark")
            dest = OUTPUT / name
            with (OUTPUT / f"{name}.log").open("w") as log:
                print(f"Building variant {name.upper()}…", flush=True)
                subprocess.run([
                    FLUTTER, "build", "web", "--no-pub",
                    "-t", "design/mobile/main.dart",
                    "--base-href", f"/variants/{name}/",
                    "--output", str(dest),
                ], cwd=work, stdout=log, stderr=subprocess.STDOUT, check=True)
            shutil.copytree(ROOT / "design/mobile/public", dest, dirs_exist_ok=True)
            subprocess.run(["python3", str(ROOT / "design/mobile/prepare_preview.py"), str(dest)], check=True)
            print(f"Variant {name.upper()} ready", flush=True)
    (OUTPUT / "recipes.json").write_text(json.dumps(RECIPES, indent=2))
    preview = ROOT / "build/mobile-preview"
    for name in RECIPES:
        shutil.copytree(OUTPUT / name, preview / "variants" / name, dirs_exist_ok=True)
    shutil.copy2(ROOT / "design/mobile/public/compare.html", preview / "compare.html")
    print("Comparison ready: http://127.0.0.1:5461/compare.html", flush=True)


if __name__ == "__main__":
    main()
