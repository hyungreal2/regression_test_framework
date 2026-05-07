#!/usr/bin/env python3
import re
import os
import argparse
from datetime import datetime

parser=argparse.ArgumentParser()
parser.add_argument('--libname', '-L', metavar="LIBRARY", default="LS01",
                    help="Library name that contains the test cellViews. Default is LS01")
parser.add_argument('--cellname', '-C', metavar="CELL", default=None,
                    help="Cell name that only testing on this. Default is the cells from --flat and --hier")
parser.add_argument('--flat', '-F', metavar="FILE", default="Flat_list",
                    help="List of cell names to use in tests that do not require hierarchy. Default is Flat_list")
parser.add_argument('--hier', '-H', metavar="FILE", default="Hierarchical_List",
                    help="List of cell names to use in tests that require hierarchy. Default is Hierarchical_List")
parser.add_argument('--template', '-t', metavar="FILE", default="template.il",
                    help="Test template file. Default is template.il")
parser.add_argument('--control', '-c', metavar="FILE", default="control",
                    help="Test template file. Default is control")
parser.add_argument('--list', '-l', metavar="FILE", default="list",
                    help="List of scenarios to test. Default is list")
parser.add_argument('--workspace', '-w', metavar="DIRECTORY", default=os.path.dirname(os.path.abspath(__file__)),
                    help="Location of the workspace.")
parser.add_argument('--results', '-r', metavar="DIRECTORY", default="replay_files",
                    help="Location of the replay files.")
parser.add_argument('--result_folder', '-u', metavar="DATE", default="datetime.now().strftime('%Y%m%d%H%M%S')",
                    help="Location of the workspace.")
# ── Func mode args ────────────────────────────────────────────────────────────
parser.add_argument('--mode', '-M', metavar="MODE", default=None,
                    choices=["checkHier", "renameRefLib", "changeRefLib",
                             "replace", "deleteAllMarkers",
                             "copyHierToEmpty", "copyHierToNonEmpty"],
                    help="Func test mode. If not given, runs as cico mode.")
parser.add_argument('--prefix',   '-prefix',   metavar="PREFIX",   default=None)
parser.add_argument('--fromLib',  '-fromLib',  metavar="FROMLIB",  default="All")
parser.add_argument('--toLib',    '-toLib',    metavar="TOLIB",    default=None)
parser.add_argument('--fromCell', '-fromCell', metavar="FROMCELL", default=None)
# ─────────────────────────────────────────────────────────────────────────────
args=parser.parse_args()

# ═════════════════════════════════════════════════════════════════════════════
# FUNC MODE SETUP: validation + args override
# When --mode is given, override file defaults and initialize flat/hier to [].
# ═════════════════════════════════════════════════════════════════════════════
mode = args.mode
flat_names = []
hier_names = []

if mode:
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

    if args.template == "template.il":
        args.template = f"func_template_{mode}.il"
    if args.control == "control":
        args.control = "func_control"
    if args.list == "list":
        args.list = f"list_{mode}{f'_{args.prefix}' if args.prefix else ''}"
# ═════════════════════════════════════════════════════════════════════════════

#WORKSPACE = os.path.dirname(os.path.abspath(__file__))
WORKSPACE = args.workspace
result_folder = args.results
library_name = args.libname

# Read files
with open(os.path.join(WORKSPACE, args.control), "r") as f:
    control_lines = f.readlines()

with open(os.path.join(WORKSPACE, args.list), "r") as f:
    list_lines = f.readlines()

with open(os.path.join(WORKSPACE, args.template), "r") as f:
    template_content = f.read()

if not mode:
    with open(os.path.join(WORKSPACE, args.flat), "r") as f:
        flat_names = [l.strip() for l in f.readlines() if l.strip()]

    with open(os.path.join(WORKSPACE, args.hier), "r") as f:
        hier_names = [l.strip() for l in f.readlines() if l.strip()]

# Create a the result folder if not exist
os.makedirs(os.path.join(WORKSPACE, result_folder), exist_ok=True)

# Parse control file: mapping from command name -> code
control_map = {}
for cline in control_lines:
    cline = cline.strip()
    if not cline or "->" not in cline:
        continue
    idx = cline.rfind("->")
    code = cline[:idx].strip()
    name = cline[idx+2:].strip()
    # Normalize name: ensure single space after commas
    name = re.sub(r'\s*,\s*', ', ', name)
    control_map[name] = code

# Debug: print control map
print("Control map keys:")
for k in sorted(control_map.keys()):
    print(f"  '{k}' => '{control_map[k][:60]}...'")
print()


def replace_names(code, line_num, cell_name=None):
    """Replace placeholder names with actual values."""
    if mode:
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
    # Replace RowNo_libname_cellname FIRST, before the individual libname/cellname
    # replacements destroy the original token
    code = code.replace('RowNo_libname_cellname', f'Row_{line_num}_{args.libname}_{cell_name}')
    code = code.replace('"libname"', f'"{library_name}"')
    code = code.replace('"cellname"', f'"{cell_name}"')
    return code


def split_statements(code):
    """Split code on standalone '\\n' delimiters into individual statements."""
    code = code.strip()
    # Check if the code is just "\n" (no-op for "Not Modified")
    if code == r'\n':
        return []
    # Split on standalone "\n" delimiter (space-delimited)
    parts = code.split(' '+r'"\n"'+' ')
    return [p.strip() for p in parts if p.strip()]


# Process each line in list
count = 0
flat_idx = 0
hier_idx = 0
pad_width = 3 if not mode else len(str(sum(1 for l in list_lines if l.strip())))
for line_num, line in enumerate(list_lines, start=1):
    line = line.strip()
    if not line:
        continue

    # Parse commands from the line (any number of numbered commands)
    # Format: "1. cmd1, 2. cmd2, 3. cmd3, ..."
    commands = re.findall(r'\d+\.\s*(.+?)(?=,\s*\d+\.|$)', line)
    commands = [cmd.strip() for cmd in commands]

    if not commands:
        print(f"Warning: Line {line_num} has no commands, skipping")
        continue

    # Determine if this line uses Hierarchical Checkout or Checkin
    is_hierarchical = any("Hierarchical" in cmd for cmd in commands)
    if is_hierarchical:
        if args.cellname is not None:
            cell_name = args.cellname
        else:
            cell_name = hier_names[hier_idx] if hier_idx < len(hier_names) else "top"
        hier_idx += 1
    else:
        if args.cellname is not None:
            cell_name = args.cellname
        else:
            cell_name = flat_names[flat_idx] if flat_idx < len(flat_names) else f"top"
        flat_idx += 1

    # Greedily match commands against control_map
    # Try single command first; if not found, combine with next adjacent command(s)
    matched_steps = []  # list of (step_label, code_string)
    i = 0
    while i < len(commands):
        matched = False
        # Try combining from 1 up to remaining commands
        for span in range(1, len(commands) - i + 1):
            combined = ", ".join(commands[i:i+span])
            if combined in control_map:
                step_nums = "&".join(str(i+1+s) for s in range(span))
                step_label = combined
                matched_steps.append((step_nums, step_label, control_map[combined]))
                i += span
                matched = True
                break
        if not matched:
            # No match found even combining all remaining — add as error
            matched_steps.append((str(i+1), commands[i], f';;; ERROR: No mapping for "{commands[i]}"'))
            i += 1

    # Print first line for debug
    if line_num == 1:
        print(f"Line 1 commands ({len(commands)}): {commands}")
        for step_nums, step_label, code in matched_steps:
            print(f"  Step {step_nums} ({step_label}): '{code[:80]}...'")
        print()

    # Replace placeholder names and split statements for each matched step
    processed_steps = []
    all_code_parts = []
    for step_nums, step_label, code in matched_steps:
        code = replace_names(code, line_num, cell_name)
        all_code_parts.append(code)
        stmts = split_statements(code)
        processed_steps.append((step_nums, step_label, stmts))

    # Determine let variables
    all_code = " ".join(all_code_parts)
    # let_vars = "win cv id rval"
    # if "rval1" in all_code:
    #     let_vars = "win cv id rval rval1"

    # Build code block with comments
    block = []
    block.append(r'\i '+f";;; Test Scenario #{line_num}: {line}")
    block.append("")
    if mode:
        block.append(r'\i ' + f"fprintf(fd strcat(\"Test Scenario #{line_num}: {line}\" \"\\n\"))")
        block.append("")

    for step_nums, step_label, stmts in processed_steps:
        block.append(r'\i '+f";;; Step {step_nums}: {step_label}")
        if stmts:
            for s in stmts:
                block.append(r'\i '+s)
        else:
            block.append(r'\i '+f";;; (no-op)")
        block.append("")

    # Remove trailing empty line
    if block and block[-1] == "":
        block.pop()

    code_block = "\n".join(block)

    # Build output from template
    output = template_content
    # Replace CDS_PV_REG_NO to current test number
    output = output.replace('CDS_PV_REGGRESION_NO', f'"{line_num:03d}"')
    output = output.replace('CDS_PV_REG_RES_NO', f'"{args.result_folder}"')
    

    # output = output.replace("let((cv id rval)", f"let(({let_vars})")

    # Replace between the two Test Scenario markers
    marker = r'\i ;;; Test Scenario::Begin'
    first = output.find(marker)
    second = output.find(r'\i ;;; Test Scenario::End', first + len(marker))
    if first != -1 and second != -1:
        before = output[:first + len(marker)] + "\n"
        after = "\n" + output[second:]
        output = before + code_block + "\n" + after

    # Write output
    out_path = os.path.join(WORKSPACE, result_folder, f"replay_{line_num:0{pad_width}d}.il")
    with open(out_path, "w") as f:
        f.write(r'\o '+"\n")
        f.write(r'\p '+"\n")
        f.write(output)
    count += 1

print(f"Successfully generated {count} template files")
