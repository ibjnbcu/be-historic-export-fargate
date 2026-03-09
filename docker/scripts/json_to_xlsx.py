#!/usr/bin/env python3
import sys
import json
from openpyxl import Workbook

if len(sys.argv) != 2:
    print("Usage: json_to_xlsx.py output.xlsx", file=sys.stderr)
    sys.exit(1)

output_file = sys.argv[1]

data = json.load(sys.stdin)

if not isinstance(data, list):
    print("Input JSON must be an array", file=sys.stderr)
    sys.exit(1)

wb = Workbook()
ws = wb.active

if not data:
    wb.save(output_file)
    sys.exit(0)

# Header row
headers = list(data[0].keys())
ws.append(headers)

# Data rows
for row in data:
    ws.append([row.get(h) for h in headers])

wb.save(output_file)