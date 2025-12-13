
import os

file_path = r"c:\Users\rmdou\Desktop\movement-test\scripts\enemies\bosses\effects\OilBurnZone.gd"

print(f"Checking {file_path} for mixed tabs and spaces...")

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.read().split('\n') # splitlines() eats endings
    
    for i, line in enumerate(lines):
        line_num = i + 1
        
        # Check for mixed tabs and spaces at the start
        has_space = False
        has_tab = False
        
        prefix = ""
        for char in line:
            if char == ' ':
                has_space = True
                prefix += "[S]"
            elif char == '\t':
                has_tab = True
                prefix += "[T]"
            else:
                break
        
        if has_space and has_tab:
             print(f"LINE {line_num} MIXED: {prefix} -> {line.strip()}")
        elif has_space:
             # Just reporting purely space lines to see if we have them
             # Godot shouldn't fail on pure spaces unless the file is inconsistent
             print(f"LINE {line_num} SPACES: {prefix} -> {line.strip()}")
        # elif has_tab:
        #      print(f"LINE {line_num} TABS: {prefix}")

except Exception as e:
    print(f"Error: {e}")
