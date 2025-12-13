
import os

def fix_indentation(file_path):
    print(f"Processing {file_path}...")
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        fixed_lines = []
        for line in lines:
            # Count leading spaces
            leading_spaces = 0
            for char in line:
                if char == ' ':
                    leading_spaces += 1
                else:
                    break
            
            # If line is indented with spaces, convert to tabs
            if leading_spaces > 0:
                # Assuming 4 spaces per tab standard
                tabs = leading_spaces // 4
                # Keep remaining spaces? Godot hates mixed. We'll just force floor division.
                
                content = line.lstrip(' ')
                # If it was mixed tabs/spaces before, lstrip handles the spaces. 
                # But wait, if it was mixed, we need to be careful.
                # Simplest robust way: strip ALL leading whitespace, calculate depth, add tabs.
                
                # REVISED: Just replace 4 spaces with 1 tab at start of string iteratively
                # This handles "    " -> "\t" and "\t    " -> "\t\t" etc.
                
                new_line = line
                while new_line.startswith('    '):
                    new_line = new_line.replace('    ', '\t', 1)
                
                fixed_lines.append(new_line)
            else:
                fixed_lines.append(line)
                
        with open(file_path, 'w', encoding='utf-8', newline='\n') as f:
            f.writelines(fixed_lines)
            
        print(f"Fixed {file_path}")
        
    except Exception as e:
        print(f"Error processing {file_path}: {e}")

files_to_fix = [
    r"c:\Users\rmdou\Desktop\movement-test\scripts\enemies\bosses\effects\OilBurnZone.gd",
    r"c:\Users\rmdou\Desktop\movement-test\scripts\characters\effects\SnowWhiteBurnTrail.gd"
]

for file in files_to_fix:
    fix_indentation(file)
