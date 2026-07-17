#!/usr/bin/env python3
"""Lightweight repository check; no simulator required."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
sources = list((root / "src").rglob("*.sv")) + list((root / "src").rglob("*.svh"))
errors = []
classes = {}

for path in sources:
    text = path.read_text(errors="ignore")
    for include in re.findall(r'`include\s+"([^"]+)"', text):
        if include == "uvm_macros.svh":
            continue
        if not (root / "src" / include).exists():
            errors.append(f"{path.relative_to(root)}: missing include {include}")
    for name in re.findall(r"\bclass\s+([A-Za-z_]\w*)", text):
        classes.setdefault(name, []).append(path)

    clean = re.sub(r"//.*", "", text)
    clean = re.sub(r"/\*.*?\*/", "", clean, flags=re.S)
    for left, right, label in (("(", ")", "parentheses"), ("[", "]", "brackets"), ("{", "}", "braces")):
        if clean.count(left) != clean.count(right):
            errors.append(f"{path.relative_to(root)}: unbalanced {label}")
    if path.suffix == ".sv":
        if len(re.findall(r"\bclass\s+[A-Za-z_]\w*", clean)) != len(re.findall(r"\bendclass\b", clean)):
            errors.append(f"{path.relative_to(root)}: class/endclass mismatch")

for name, paths in classes.items():
    if len(paths) > 1:
        errors.append(f"duplicate class {name}: " + ", ".join(str(p.relative_to(root)) for p in paths))

for path in list(root.rglob("*.sv")) + list(root.rglob("*.svh")) + list(root.rglob("*.md")):
    for line_no, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
        if line.rstrip() != line:
            errors.append(f"{path.relative_to(root)}:{line_no}: trailing whitespace")

# Hoang Ho: known-pattern transactions must use the width-expansion helper.
# A direct 32-bit equality on data[] silently leaves upper lanes untested.
for path in (root / "src" / "seq").rglob("*.sv"):
    text = path.read_text(errors="ignore")
    if re.search(r"\bdata\s*\[[^\]]+\]\s*==\s*32'h", text):
        errors.append(f"{path.relative_to(root)}: fixed 32-bit data constraint; use axi4_expand_legacy_word")

# Hoang Ho: Release R3 keeps six user-facing Makefile command groups.
# Internal targets are intentionally prefixed with an underscore.
makefile_text = (root / "sim" / "Makefile").read_text(errors="ignore")
for required in (
    "run:", "gui:", "regress:", "regress_all:",
    "clean:", "clean_all:", "merge_cov:", "cov_report:",
    "_run_cli:", "_regress_width:",
):
    if required not in makefile_text:
        errors.append(f"sim/Makefile: missing simplified release feature {required}")

for width in ("32", "64", "128", "256", "512", "1024"):
    if width not in makefile_text:
        errors.append(f"sim/Makefile: missing supported DATA_WIDTH={width}")

if errors:
    print("[STATIC-CHECK] FAILED")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print(f"[STATIC-CHECK] PASS: {len(sources)} SV/SVH files, {len(classes)} classes, all includes resolved")
