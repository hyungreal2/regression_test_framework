#!/usr/bin/env python3
import re
import os
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--mode', '-M', metavar="MODE", required=True,
                    choices=["checkHier", "renameRefLib", "changeRefLib",
                             "replace", "deleteAllMarkers",
                             "copyHierToEmpty", "copyHierToNonEmpty"],
                    help="Mode for the test. Determines which list/template/control files to use.")

parser.add_argument('--prefix',    '-prefix',   metavar="PREFIX",   default=None)
parser.add_argument('--libname',   '-lib',      metavar="LIBRARY",  default=None)
parser.add_argument('--cellname',  '-cell',     metavar="CELL",     default=None)
parser.add_argument('--fromLib',   '-fromLib',  metavar="FROMLIB",  default="All")
parser.add_argument('--toLib',     '-toLib',    metavar="TOLIB",    default=None)
parser.add_argument('--fromCell',  '-fromCell', metavar="FROMCELL", default=None)

parser.add_argument('--template', '-t', metavar="FILE", default=None,
                    help="Test template file. Default is func_template_<mode>.il")
parser.add_argument('--control',  '-c', metavar="FILE", default=None,
                    help="Control file. Default is control")
parser.add_argument('--list',     '-l', metavar="FILE", default=None,
                    help="List file. Default is list_<mode>")
parser.add_argument('--workspace', '-w', metavar="DIRECTORY",
                    default=os.path.dirname(os.path.abspath(__file__)),
                    help="Location of the workspace.")
parser.add_argument('--results', '-r', metavar="DIRECTORY", default="replay_files",
                    help="Output folder for replay files.")
args = parser.parse_args()

# ─── Mode-specific argument validation ────────────────────────────────────────
def require_arg(name, val):
    if not val:
        parser.error(f"--{name} is required for mode '{args.mode}'")

mode = args.mode
if mode == "checkHier":
    require_arg("libname",  args.libname)
    require_arg("cellname", args.cellname)
elif mode == "renameRefLib":
    require_arg("libname",  args.libname)
    require_arg("fromLib",  args.fromLib)
    require_arg("toLib",    args.toLib)
    require_arg("cellname",  args.cellname)
elif mode == "changeRefLib":
    require_arg("libname",  args.libname)
    require_arg("toLib",    args.toLib)
elif mode == "replace":
    require_arg("libname",  args.libname)
    require_arg("cellname", args.cellname)
elif mode == "deleteAllMarkers":
    require_arg("libname",  args.libname)
    require_arg("cellname", args.cellname)
elif mode in ("copyHierToEmpty", "copyHierToNonEmpty"):
    require_arg("fromLib",  args.fromLib)
    require_arg("fromCell", args.fromCell)
    require_arg("toLib",    args.toLib)

# ─── Resolve file paths based on mode ─────────────────────────────────────────
WORKSPACE     = args.workspace
result_folder = args.results

template_file = args.template or f"func_template_{mode}.il"
control_file  = args.control  or "func_control"
list_file     = args.list     or f"list_{mode}{f'_{args.prefix}' if args.prefix else ''}"

# ─── Read files ───────────────────────────────────────────────────────────────
with open(os.path.join(WORKSPACE, control_file), "r") as f:
    control_lines = f.readlines()

with open(os.path.join(WORKSPACE, list_file), "r") as f:
    list_lines = f.readlines()

with open(os.path.join(WORKSPACE, template_file), "r") as f:
    template_content = f.read()

# ─── Create result folder ─────────────────────────────────────────────────────
os.makedirs(os.path.join(WORKSPACE, result_folder), exist_ok=True)

# ─── Parse control file: mapping from command name -> code ────────────────────
control_map = {}
for cline in control_lines:
    cline = cline.strip()
    if not cline or "->" not in cline:
        continue
    idx = cline.rfind("->")
    code = cline[:idx].strip()
    name = cline[idx+2:].strip()
    name = re.sub(r'\s*,\s*', ', ', name)
    control_map[name] = code

# ─── replace_names: mode-aware placeholder substitution ───────────────────────
def replace_names(code, line_num):
    if mode in ("checkHier", "replace", "deleteAllMarkers"):
        code = code.replace('RowNo_libname_cellname',
                            f'Row_{line_num}_{args.libname}_{args.cellname}')
        code = code.replace('"RowNo"',    f'"Row_{line_num}"')
        code = code.replace('"libname"',  f'"{args.libname}"')
        code = code.replace('"cellname"', f'"{args.cellname}"')

    elif mode in ("renameRefLib", "changeRefLib"):
        code = code.replace('RowNo_libname_cellname',
                            f'Row_{line_num}_{args.libname}_{args.cellname}')
        code = code.replace('"libname"',  f'"{args.libname}"')
        code = code.replace('"fromLib"',  f'"{args.fromLib}"')
        code = code.replace('"toLib"',    f'"{args.toLib}"')
        code = code.replace('"cellname"', f'"{args.cellname}"')

    elif mode in ("copyHierToEmpty", "copyHierToNonEmpty"):
        code = code.replace('RowNo_fromLib_fromCell_toLib',
                            f'Row_{line_num}_{args.fromLib}_{args.fromCell}_{args.toLib}')
        code = code.replace('"fromLib"',  f'"{args.fromLib}"')
        code = code.replace('"fromCell"', f'"{args.fromCell}"')
        code = code.replace('"toLib"',    f'"{args.toLib}"')

    return code


def split_statements(code):
    """Split code on standalone '\\n' delimiters into individual statements."""
    code = code.strip()
    if code == r'\n':
        return []
    parts = code.split(' ' + r'"\n"' + ' ')
    return [p.strip() for p in parts if p.strip()]


# ─── Process each line in list ────────────────────────────────────────────────
non_empty_count = sum(1 for l in list_lines if l.strip())
pad_width = len(str(non_empty_count))

count = 0
for line_num, line in enumerate(list_lines, start=1):
    line = line.strip()
    if not line:
        continue

    commands = re.findall(r'\d+\.\s*(.+?)(?=,\s*\d+\.|$)', line)
    commands = [cmd.strip() for cmd in commands]

    if not commands:
        print(f"Warning: Line {line_num} has no commands, skipping")
        continue

    # Greedily match commands against control_map (longest span first)
    matched_steps = []
    i = 0
    while i < len(commands):
        matched = False
        for span in range(len(commands) - i, 0, -1):
            combined = ", ".join(commands[i:i+span])
            if combined in control_map:
                step_nums = "&".join(str(i+1+s) for s in range(span))
                matched_steps.append((step_nums, combined, control_map[combined]))
                i += span
                matched = True
                break
        if not matched:
            matched_steps.append((str(i+1), commands[i],
                                  f';;; ERROR: No mapping for "{commands[i]}"'))
            i += 1

    # Build code block with comments
    block = []
    block.append(r'\i ' + f";;; Test Scenario #{line_num}: {line}")
    block.append("")
    block.append(r'\i ' + f"fprintf(fd strcat(\"Test Scenario #{line_num}: {line}\" \"\\n\"))")
    block.append("")

    for step_nums, step_label, code in matched_steps:
        code = replace_names(code, line_num)
        block.append(r'\i ' + f";;; Step {step_nums}: {step_label}")
        stmts = split_statements(code)
        if stmts:
            for s in stmts:
                block.append(r'\i ' + s)
        else:
            block.append(r'\i ' + ";;; (no-op)")
        block.append("")

    if block and block[-1] == "":
        block.pop()

    code_block = "\n".join(block)

    # Insert code block into template
    output = template_content
    marker = r'\i ;;; Test Scenario::Begin'
    first  = output.find(marker)
    second = output.find(r'\i ;;; Test Scenario::End', first + len(marker))
    if first != -1 and second != -1:
        before = output[:first + len(marker)] + "\n"
        after  = "\n" + output[second:]
        output = before + code_block + "\n" + after

    out_path = os.path.join(WORKSPACE, result_folder,
                            f"replay_{line_num:0{pad_width}d}.il")
    with open(out_path, "w") as f:
        f.write(r'\o ' + "\n")
        f.write(r'\p ' + "\n")
        f.write(output)
    count += 1

print(f"Generated {count} replay files → {os.path.join(WORKSPACE, result_folder)}")
