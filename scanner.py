import argparse
import json
import re
from datetime import datetime

now_local = datetime.now().astimezone()
formatted_time = now_local.isoformat(timespec='seconds')

parser = argparse.ArgumentParser(description="DLL export scanner")
parser.add_argument("--version", required=True, help="Schema Version Count")
parser.add_argument("--source", required=True, help="Path to DLL file")
parser.add_argument("--out", required=True, help="Output JSON file")
parser.add_argument("--verbose", action="store_true", help="Enable verbose output")


args = parser.parse_args()

with open(args.source, 'r', encoding='utf-8') as src_file:
    source_code = src_file.read()

macro_pattern = re.compile(
    r'^\s*#define\s+(\w+)\s+__declspec\s*\(\s*dllexport\s*\)',
    re.MULTILINE
)

match = macro_pattern.search(source_code)
export_macro = match.group(1) if match else None

if not export_macro:
    raise RuntimeError("No Windows dllexport macro found in source file")

export_macro = match.group(1)
escaped_macro = re.escape(export_macro)

func_pattern = re.compile(
    rf'^\s*{escaped_macro}\s+([\w\s*]+)\s+(\w+)\s*\(([^)]*)\)\s*\{{',
    re.MULTILINE
)

functions = []
for ret_type, name, args_list in func_pattern.findall(source_code):
    functions.append({
        "name": name,
        "return_type": ret_type.strip(),
        "args": args_list.strip()
    })

data = {
    "schema_version": int(args.version),
    "source": args.source,
    "timestamp": formatted_time,
    "exported_functions": functions
}

with open(args.out, "w", encoding="utf-8") as funcs:
    json.dump(data, funcs, indent=3)

if args.verbose:
    print(f"Writing {len(functions)} functions to {args.out}")
    print(f"[VERBOSE] File scanned for functions: {args.source}")