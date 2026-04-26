#!/usr/bin/env python3
"""
Functional test replay generator.
Reads control + list + template files from --workspace directory
and generates one replay_NNN.il file per test scenario.
"""

import re
import os
import argparse

VALID_MODES = [
    "checkHier", "renameRefLib", "changeRefLib",
    "replace", "deleteAllMarkers",
    "copyHierToEmpty", "copyHierToNonEmpty",
]

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--mode",     "-M", required=True, choices=VALID_MODES)
parser.add_argument("--prefix",         default=None)
parser.add_argument("--libname",        default=None)
parser.add_argument("--cellname",       default=None)
parser.add_argument("--fromLib",        default="All")
parser.add_argument("--toLib",          default=None)
parser.add_argument("--fromCell",       default=None)
parser.add_argument("--workspace", "-w",
                    default=os.path.dirname(os.path.abspath(__file__)),
                    help="Directory containing control/list/template files.")
parser.add_argument("--template",  "-t", default=None,
                    help="Template file name (default: template_<mode>.il)")
parser.add_argument("--control",   "-c", default=None,
                    help="Control file name (default: control)")
parser.add_argument("--list",      "-l", default=None,
                    help="List file name (default: list_<mode>[_<prefix>])")
parser.add_argument("--results",   "-r", default="replay_files",
                    help="Output folder name (relative to --workspace)")
args = parser.parse_args()

mode = args.mode

# ── Mode-specific required arg validation ─────────────────────────────────────
def require_arg(name, val):
    if not val:
        parser.error(f"--{name} is required for mode '{mode}'")

if mode == "checkHier":
    require_arg("libname",  args.libname)
    require_arg("cellname", args.cellname)
elif mode == "renameRefLib":
    require_arg("libname",  args.libname)
    require_arg("fromLib",  args.fromLib)
    require_arg("toLib",    args.toLib)
    require_arg("cellname", args.cellname)
elif mode == "changeRefLib":
    require_arg("libname",  args.libname)
    require_arg("toLib",    args.toLib)
elif mode in ("replace", "deleteAllMarkers"):
    require_arg("libname",  args.libname)
    require_arg("cellname", args.cellname)
elif mode in ("copyHierToEmpty", "copyHierToNonEmpty"):
    require_arg("fromLib",  args.fromLib)
    require_arg("fromCell", args.fromCell)
    require_arg("toLib",    args.toLib)

# ── Resolve file paths ─────────────────────────────────────────────────────────
WS = args.workspace
template_file = args.template or f"template_{mode}.il"
control_file  = args.control  or "control"
list_file     = args.list     or f"list_{mode}" + (f"_{args.prefix}" if args.prefix else "")
result_folder = args.results

# ── Read files ─────────────────────────────────────────────────────────────────
with open(os.path.join(WS, control_file), "r") as f:
    control_lines = f.readlines()

with open(os.path.join(WS, list_file), "r") as f:
    list_lines = f.readlines()

with open(os.path.join(WS, template_file), "r") as f:
    template_content = f.read()

os.makedirs(os.path.join(WS, result_folder), exist_ok=True)

# ── Parse control file: step_name → SKILL code ────────────────────────────────
control_map = {}
for cline in control_lines:
    cline = cline.strip()
    if not cline or "->" not in cline:
        continue
    idx = cline.rfind("->")
    code = cline[:idx].strip()
    name = re.sub(r'\s*,\s*', ', ', cline[idx+2:].strip())
    control_map[name] = code

# ── Placeholder substitution (mode-aware) ─────────────────────────────────────
def replace_names(code, line_num):
    if mode in ("checkHier", "replace", "deleteAllMarkers"):
        code = code.replace("RowNo_libname_cellname",
                            f"Row_{line_num}_{args.libname}_{args.cellname}")
        code = code.replace('"RowNo"',    f'"Row_{line_num}"')
        code = code.replace('"libname"',  f'"{args.libname}"')
        code = code.replace('"cellname"', f'"{args.cellname}"')

    elif mode in ("renameRefLib", "changeRefLib"):
        code = code.replace("RowNo_libname_cellname",
                            f"Row_{line_num}_{args.libname}_{args.cellname}")
        code = code.replace('"RowNo"',    f'"Row_{line_num}"')
        code = code.replace('"libname"',  f'"{args.libname}"')
        code = code.replace('"fromLib"',  f'"{args.fromLib}"')
        code = code.replace('"toLib"',    f'"{args.toLib}"')
        code = code.replace('"cellname"', f'"{args.cellname}"')

    elif mode in ("copyHierToEmpty", "copyHierToNonEmpty"):
        code = code.replace("RowNo_fromLib_fromCell_toLib",
                            f"Row_{line_num}_{args.fromLib}_{args.fromCell}_{args.toLib}")
        code = code.replace('"RowNo"',    f'"Row_{line_num}"')
        code = code.replace('"fromLib"',  f'"{args.fromLib}"')
        code = code.replace('"fromCell"', f'"{args.fromCell}"')
        code = code.replace('"toLib"',    f'"{args.toLib}"')

    return code


def split_statements(code):
    """Split on standalone \\n delimiters into individual SKILL statements."""
    code = code.strip()
    if code == r'\n':
        return []
    parts = code.split(' ' + r'"\n"' + ' ')
    return [p.strip() for p in parts if p.strip()]


# ── Process each list line → one replay file ──────────────────────────────────
pad_width = len(str(len(list_lines)))
count = 0

for line_num, line in enumerate(list_lines, start=1):
    line = line.strip()
    if not line:
        continue

    # Extract ordered step names from the list line
    commands = re.findall(r'\d+\.\s*(.+?)(?=,\s*\d+\.|$)', line)
    commands = [cmd.strip() for cmd in commands]

    if not commands:
        print(f"Warning: line {line_num} has no commands, skipping")
        continue

    # Greedy match against control_map (handles multi-word step names)
    matched_steps = []
    i = 0
    while i < len(commands):
        matched = False
        for span in range(len(commands) - i, 0, -1):
            combined = ", ".join(commands[i:i + span])
            if combined in control_map:
                step_nums = "&".join(str(i + 1 + s) for s in range(span))
                matched_steps.append((step_nums, combined, control_map[combined]))
                i += span
                matched = True
                break
        if not matched:
            matched_steps.append((str(i + 1), commands[i],
                                  f';;; ERROR: No mapping for "{commands[i]}"'))
            i += 1

    # Build code block for this test scenario
    block = [
        r'\i ' + f';;; Test Scenario #{line_num}: {line}',
        "",
        r'\i ' + f'fprintf(fd strcat("Test Scenario #{line_num}: {line}" "\\n"))',
        "",
    ]
    for step_nums, step_label, code in matched_steps:
        code = replace_names(code, line_num)
        block.append(r'\i ' + f';;; Step {step_nums}: {step_label}')
        stmts = split_statements(code)
        if stmts:
            for s in stmts:
                block.append(r'\i ' + s)
        else:
            block.append(r'\i ;;; (no-op)')
        block.append("")

    if block and block[-1] == "":
        block.pop()

    code_block = "\n".join(block)

    # Insert between markers in template
    output = template_content
    begin_marker = r'\i ;;; Test Scenario::Begin'
    end_marker   = r'\i ;;; Test Scenario::End'
    first  = output.find(begin_marker)
    second = output.find(end_marker, first + len(begin_marker))
    if first != -1 and second != -1:
        before = output[:first + len(begin_marker)] + "\n"
        after  = "\n" + output[second:]
        output = before + code_block + "\n" + after
    else:
        print(f"Warning: markers not found in template for line {line_num}")

    out_path = os.path.join(WS, result_folder, f"replay_{line_num:0{pad_width}d}.il")
    with open(out_path, "w") as f:
        f.write(r'\o ' + "\n")
        f.write(r'\p ' + "\n")
        f.write(output)
    count += 1

print(f"Generated {count} replay files → {os.path.join(WS, result_folder)}")
