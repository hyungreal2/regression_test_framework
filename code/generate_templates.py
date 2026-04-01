#!/usr/bin/env python3

import re
import os
import argparse

#######################################
# Arguments
#######################################
parser = argparse.ArgumentParser()
parser.add_argument('--libname',   '-L', metavar="LIBRARY",   default="MYLIB",
    help="Library name that contains the test cellViews. Default is MYLIB")
parser.add_argument('--cellname',  '-C', metavar="CELL",      default=None,
    help="Cell name to test. Default is the cells from --flat and --hier")
parser.add_argument('--flat',      '-F', metavar="FILE",      default="Flat_list",
    help="List of cell names for non-hierarchical tests. Default is Flat_list")
parser.add_argument('--hier',      '-H', metavar="FILE",      default="Hierarchical_List",
    help="List of cell names for hierarchical tests. Default is Hierarchical_List")
parser.add_argument('--template',  '-t', metavar="FILE",      default="template.il",
    help="Test template file. Default is template.il")
parser.add_argument('--control',   '-c', metavar="FILE",      default="control",
    help="Control mapping file. Default is control")
parser.add_argument('--list',      '-l', metavar="FILE",      default="list",
    help="List of test scenarios. Default is list")
parser.add_argument('--workspace', '-w', metavar="DIRECTORY",
    default=os.path.dirname(os.path.abspath(__file__)),
    help="Workspace directory. Default is the script's directory")
parser.add_argument('--results',   '-r', metavar="DIRECTORY", default="replay_files",
    help="Output directory for generated replay files. Default is replay_files")
args = parser.parse_args()

WORKSPACE     = args.workspace
result_folder = args.results
library_name  = args.libname

#######################################
# Read input files
#######################################
with open(os.path.join(WORKSPACE, args.control), "r") as f:
    control_lines = f.readlines()

with open(os.path.join(WORKSPACE, args.list), "r") as f:
    list_lines = f.readlines()

with open(os.path.join(WORKSPACE, args.template), "r") as f:
    template_content = f.read()

with open(os.path.join(WORKSPACE, args.flat), "r") as f:
    flat_names = [l.strip() for l in f if l.strip()]

with open(os.path.join(WORKSPACE, args.hier), "r") as f:
    hier_names = [l.strip() for l in f if l.strip()]

#######################################
# Create result folder
#######################################
os.makedirs(os.path.join(WORKSPACE, result_folder), exist_ok=True)

#######################################
# Parse control file: name -> code
#######################################
control_map = {}
for cline in control_lines:
    cline = cline.strip()
    if not cline or "->" not in cline:
        continue
    idx  = cline.rfind("->")
    code = cline[:idx].strip()
    name = cline[idx + 2:].strip()
    name = re.sub(r'\s*,\s*', ', ', name)  # normalize comma spacing
    control_map[name] = code

print("Control map keys:")
for k in sorted(control_map.keys()):
    print(f"  '{k}' => '{control_map[k][:60]}...'")
print()

#######################################
# Helpers
#######################################
def replace_names(code, line_num, cell_name):
    """Replace placeholder tokens with actual lib/cell/row values."""
    code = code.replace('RowNo_libname_cellname', f'Row_{line_num}_{args.libname}_{cell_name}')
    code = code.replace('"libname"',  f'"{library_name}"')
    code = code.replace('"cellname"', f'"{cell_name}"')
    return code


def split_statements(code):
    """Split code on standalone \\n delimiters into individual statements."""
    code = code.strip()
    if code == r'\n':
        return []
    parts = code.split(' ' + r'"\n"' + ' ')
    return [p.strip() for p in parts if p.strip()]


#######################################
# Generate replay files
#######################################
count    = 0
flat_idx = 0
hier_idx = 0

for line_num, line in enumerate(list_lines, start=1):
    line = line.strip()
    if not line:
        continue

    # Parse numbered commands: "1. cmd1, 2. cmd2, ..."
    commands = re.findall(r'\d+\.\s*(.+?)(?=,\s*\d+\.|$)', line)
    commands = [cmd.strip() for cmd in commands]

    if not commands:
        print(f"Warning: Line {line_num} has no commands, skipping")
        continue

    # Assign cell name from flat or hierarchical list
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
            cell_name = flat_names[flat_idx] if flat_idx < len(flat_names) else "top"
            flat_idx += 1

    # Greedily match commands against control_map
    matched_steps = []
    i = 0
    while i < len(commands):
        matched = False
        for span in range(1, len(commands) - i + 1):
            combined = ", ".join(commands[i:i + span])
            if combined in control_map:
                step_nums = "&".join(str(i + 1 + s) for s in range(span))
                matched_steps.append((step_nums, combined, control_map[combined]))
                i += span
                matched = True
                break
        if not matched:
            matched_steps.append((str(i + 1), commands[i], f';;; ERROR: No mapping for "{commands[i]}"'))
            i += 1

    # Debug: print first line
    if line_num == 1:
        print(f"Line 1 commands ({len(commands)}): {commands}")
        for step_nums, step_label, code in matched_steps:
            print(f"  Step {step_nums} ({step_label}): '{code[:80]}...'")
        print()

    # Build processed steps
    processed_steps = []
    for step_nums, step_label, code in matched_steps:
        code  = replace_names(code, line_num, cell_name)
        stmts = split_statements(code)
        processed_steps.append((step_nums, step_label, stmts))

    # Build code block
    block = []
    block.append(r'\i ' + f";;; Test Scenario #{line_num}: {line}")
    block.append("")
    for step_nums, step_label, stmts in processed_steps:
        block.append(r'\i ' + f";;; Step {step_nums}: {step_label}")
        if stmts:
            for s in stmts:
                block.append(r'\i ' + s)
        else:
            block.append(r'\i ' + ";;; (no-op)")
        block.append("")

    if block and block[-1] == "":
        block.pop()

    code_block = "\n".join(block)

    # Insert code block into template between markers
    output = template_content
    marker = r'\i ;;; Test Scenario::Begin'
    first  = output.find(marker)
    second = output.find(r'\i ;;; Test Scenario::End', first + len(marker))

    if first != -1 and second != -1:
        before = output[:first + len(marker)] + "\n"
        after  = "\n" + output[second:]
        output = before + code_block + "\n" + after

    # Write replay file
    out_path = os.path.join(WORKSPACE, result_folder, f"replay_{line_num:03d}.il")
    with open(out_path, "w") as f:
        f.write(r'\o ' + "\n")
        f.write(r'\p ' + "\n")
        f.write(output)

    count += 1

print(f"Successfully generated {count} template files")
