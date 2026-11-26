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
OUTPUT = ROOT / "build/entry-list-variants"
RECIPES = {"entry-list": {}}


def replace(root, file, old, new):
    path = root / file
    text = path.read_text()
    if old not in text:
        raise RuntimeError(f"Preview baseline changed: {file}: {old!r}")
    path.write_text(text.replace(old, new))


def recipe(root, name, values):
    file = "lib/features/vault/presentation/widgets/entry_list_card.dart"
    path = root / file
    text = path.read_text()
    text = text.replace("    final l10n =", "    final layout = Uri.base.queryParameters['layout'] ?? 'a';\n    final l10n =", 1)
    start = text.index("              // Compact library rows")
    end = text.index("              // Reveal panel", start)
    text = text[:start] + (ROOT / "design/mobile/experiments/entry_header.dart.txt").read_text() + text[end:]
    path.write_text(text)
    file = "lib/core/widgets/app_record_list.dart"
    replace(root, file, "    final brightness =", "    final separate = Uri.base.queryParameters['layout'] == 'c';\n    final brightness =")
    replace(root, file, "    return DecoratedSliver(", "    if (separate) return SliverList.separated(itemCount: itemCount, itemBuilder: itemBuilder, separatorBuilder: (_, _) => const SizedBox(height: 10));\n    return DecoratedSliver(")
    replace(root, "lib/features/vault/presentation/pages/global_entries_page.dart", "compact: true,", "compact: Uri.base.queryParameters['layout'] != 'c',")


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
    shutil.copy2(ROOT / "design/mobile/public/entries-compare.html", preview / "entries-compare.html")
    print("Comparison ready: http://127.0.0.1:5461/entries-compare.html", flush=True)


if __name__ == "__main__":
    main()
