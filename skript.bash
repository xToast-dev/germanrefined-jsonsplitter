#!/usr/bin/env bash

if [ "$#" -lt 1 ]; then
  echo "Fehler: Fehlende Argumente."
  echo "Nutzung zum Aufteilen:  $0 split de.json"
  echo "Nutzung zum Zusammenfügen: $0 merge [zielordner]"
  exit 1
fi

MODE="$1"

categories=(
    'itemdesc-' 'blockdesc-' 'blockhelp-' 'meal-ingredient-' 'recipeingredient-'
    'setting-name-' 'worldconfig-' 'worldattribute-' 'itemcraftdesc-' 'prefixandcreature-'
    'charattribute-' 'handbook-' 'dialogue-' 'deathmsg-' 'skinpart-' 'clutter-'
    'block-' 'item-' 'incontainer-' 'fruittree-' 'playstyle-' 'blockcraftdesc-'
    'material-' 'smeltdesc-' 'mealcreation-' 'ore-' 'rock-' 'setting-'
    'tradingwindow-' 'placefailure-' 'creaturegroup-' 'we-' 'pie-'
)

if [ "$MODE" == "split" ]; then
  if [ "$#" -ne 2 ]; then
    echo "Nutzung zum Aufteilen: $0 split de.json"
    exit 1
  fi
  source_file="$2"
  outdir="$(cd "$(dirname "$source_file")" && pwd)"

  echo "Spalte $source_file in valide JSON-Dateien auf..."

  python3 - "$source_file" "$outdir" "${categories[@]}" <<'PY'
import sys
import json
import re
from pathlib import Path

source_file = Path(sys.argv[1])
outdir = Path(sys.argv[2])
categories = sorted(sys.argv[3:], key=len, reverse=True)

def auto_fix_broken_json(content):
    pattern = re.compile(r'^\s*"([^"]+)"\s*:\s*"', re.M)
    matches = list(pattern.finditer(content))
    data = {}
    for i, match in enumerate(matches):
        key = match.group(1)
        start_val = match.end()
        end_val = matches[i+1].start() if i + 1 < len(matches) else len(content)
        raw_val = content[start_val:end_val].strip()
        while raw_val and raw_val[-1] in ' \t\n\r},,':
            if raw_val.endswith(','):
                raw_val = raw_val[:-1].strip()
            elif raw_val.endswith('}'):
                raw_val = raw_val[:-1].strip()
            else:
                break
        if raw_val.endswith('"'):
            raw_val = raw_val[:-1]
        val_cleaned = ""
        escaped = False
        for char in raw_val:
            if char == '\\':
                escaped = not escaped
                val_cleaned += char
            elif char == '"':
                if not escaped:
                    val_cleaned += '\\"'
                else:
                    val_cleaned += char
                escaped = False
            elif char == '\n':
                val_cleaned += '\\n'
                escaped = False
            elif char == '\r':
                pass
            else:
                val_cleaned += char
                escaped = False
        try:
            data[key] = json.loads(f'"{val_cleaned}"')
        except Exception:
            data[key] = val_cleaned
    return data

try:
    with open(source_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
except json.JSONDecodeError:
    print(f"[!] Warnung: Quell-JSON ist beschädigt! Starte automatische Reparatur vor dem Split...")
    content = source_file.read_text(encoding='utf-8', errors='ignore')
    data = auto_fix_broken_json(content)
    if not data:
        print("[-] Reparatur fehlgeschlagen.")
        sys.exit(1)
    print(f"[+] Reparatur erfolgreich. {len(data)} Einträge gerettet!")

split_data = {cat: {} for cat in categories}
split_data['other-'] = {}

for key, value in data.items():
    matched = False
    for cat in categories:
        if key.startswith(cat):
            split_data[cat][key] = value
            matched = True
            break
    if not matched:
        split_data['other-'][key] = value

for cat, items in split_data.items():
    filename = f"{cat[:-1]}.json"
    if not items:
        continue
    with open(outdir / filename, 'w', encoding='utf-8') as f:
        json.dump(items, f, ensure_ascii=False, indent=4)
PY
  echo "Fertig. Valide JSON-Dateien wurden in $outdir erstellt."

elif [ "$MODE" == "merge" ]; then
  target_dir="${2:-.}"
  target_dir="$(cd "$target_dir" && pwd)"

  echo "Füge JSON-Dateien aus Ordner $target_dir zusammen..."

  python3 - "$target_dir" "${categories[@]}" <<'PY'
import sys
import json
import re
from pathlib import Path

target_dir = Path(sys.argv[1])
categories = sys.argv[2:]

expected_files = [f"{cat[:-1]}.json" for cat in categories] + ["other.json"]
merged_data = {}
errors_found = False

def auto_fix_broken_json(content):
    pattern = re.compile(r'^\s*"([^"]+)"\s*:\s*"', re.M)
    matches = list(pattern.finditer(content))
    data = {}
    for i, match in enumerate(matches):
        key = match.group(1)
        start_val = match.end()
        end_val = matches[i+1].start() if i + 1 < len(matches) else len(content)
        raw_val = content[start_val:end_val].strip()
        while raw_val and raw_val[-1] in ' \t\n\r},,':
            if raw_val.endswith(','):
                raw_val = raw_val[:-1].strip()
            elif raw_val.endswith('}'):
                raw_val = raw_val[:-1].strip()
            else:
                break
        if raw_val.endswith('"'):
            raw_val = raw_val[:-1]
        val_cleaned = ""
        escaped = False
        for char in raw_val:
            if char == '\\':
                escaped = not escaped
                val_cleaned += char
            elif char == '"':
                if not escaped:
                    val_cleaned += '\\"'
                else:
                    val_cleaned += char
                escaped = False
            elif char == '\n':
                val_cleaned += '\\n'
                escaped = False
            elif char == '\r':
                pass
            else:
                val_cleaned += char
                escaped = False
        try:
            data[key] = json.loads(f'"{val_cleaned}"')
        except Exception:
            data[key] = val_cleaned
    return data

for fname in expected_files:
    file_path = target_dir / fname
    if not file_path.exists():
        continue

    content = file_path.read_text(encoding='utf-8', errors='ignore').strip()
    if not content or content == "{}":
        continue

    try:
        file_data = json.loads(content)
    except json.JSONDecodeError:
        print(f"\n[!] Warnung in {fname}: Beschädigtes JSON-Format entdeckt! Starte Reparatur...")
        file_data = auto_fix_broken_json(content)
        if not file_data:
            print(f"[-] Reparatur in {fname} fehlgeschlagen. Datei wird übersprungen.")
            errors_found = True
            continue
        print(f"[+] Reparatur erfolgreich. {len(file_data)} Einträge gerettet!")

    for key, value in file_data.items():
        if key in merged_data:
            print(f"Fehler: Doppelter Schlüssel gefunden! '{key}' existiert bereits.")
            errors_found = True

        if fname != "other.json":
            expected_prefix = fname.replace('.json', '-')
            if not key.startswith(expected_prefix):
                print(f"Validierungsfehler in {fname}: Schlüssel '{key}' gehört hier nicht rein!")
                errors_found = True
        else:
            for cat in categories:
                if key.startswith(cat):
                    print(f"Validierungsfehler in other.json: Schlüssel '{key}' gehört eigentlich in {cat[:-1]}.json!")
                    errors_found = True

        merged_data[key] = value

if errors_found:
    print("\n[!] Es wurden Validierungsfehler gefunden. Die 'de.json' wird dennoch erstellt.")

output_file = target_dir / "de.json"
with open(output_file, 'w', encoding='utf-8') as f:
    json.dump(merged_data, f, ensure_ascii=False, indent=4)

print(f"\nErfolgreich zusammengefügt! Datei erstellt: {output_file}")
PY
fi
