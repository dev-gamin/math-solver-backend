import os
from pathlib import Path
import re
import sympy as sp
from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename
from pix2text import Pix2Text
import nltk
from nltk import word_tokenize

# Lazy-load NLTK data
try:
    nltk.data.find('tokenizers/punkt_tab')
except LookupError:
    nltk.download('punkt_tab', quiet=True)

# Set custom home dirs to bundled models
base_dir = Path(__file__).parent
os.environ['CNSTD_HOME'] = str(base_dir / 'models' / '.cnstd')
os.environ['CNOCR_HOME'] = str(base_dir / 'models' / '.cnocr')
os.environ['PIX2TEXT_HOME'] = str(base_dir / 'models' / '.pix2text')

app = Flask(__name__)
p2t = Pix2Text.from_config(device='cpu', engine_formula='mfr')  # Initialize Pix2Text once

def parse_word_problem(text):
    # Basic NLP parsing for word problems using NLTK
    tokens = word_tokenize(text.lower())
    # Simple heuristic: extract numbers and operations
    numbers = [t for t in tokens if t.isdigit()]
    ops = [t for t in tokens if t in ['plus', 'minus', 'times', 'divided', 'equals']]
    # Construct a basic equation, e.g., "x + 5 = 10" from "what plus 5 equals 10"
    if 'what' in tokens and 'equals' in tokens:
        eq = 'x'
        for op, num in zip(ops, numbers):
            if op == 'plus':
                eq += ' + ' + num
            elif op == 'minus':
                eq += ' - ' + num
            # Add more ops as needed
        eq += ' = ' + numbers[-1] if len(numbers) > len(ops) else ''
        return eq
    return text  # Fallback to original if not parsed

def prepare_equation(s):
    s = s.strip('$ ')
    s = ' '.join(s.split())  # Normalize spaces
    # Insert * for implicit multiplication, allowing spaces
    s = re.sub(r'(\d)\s*([a-zA-Z(])', r'\1*\2', s)
    s = re.sub(r'(\))\s*(\d|[a-zA-Z])', r'\1*\2', s)
    s = re.sub(r'([a-zA-Z])\s*(\d|\()', r'\1*\2', s)
    # Handle LaTeX ^{}
    while '^{' in s:
        start = s.find('^{')
        end = s.find('}', start)
        if end > 0:
            power = s[start+2:end]
            s = s[:start] + '**(' + power + ')' + s[end+1:]
    # Handle plain ^
    s = s.replace('^', '**')
    return s.replace(' ', '')  # Remove all spaces for SymPy parsing

def solve_equation(equation_str):
    try:
        # If it looks like a word problem, parse it first
        if re.search(r'\b(what|find|solve|how many)\b', equation_str, re.I):
            equation_str = parse_word_problem(equation_str)
        
        prepared = prepare_equation(equation_str)  # Preprocess
        x = sp.symbols('x')
        eq_str = prepared.replace('=', '-(') + ')'
        eq = sp.sympify(eq_str)
        solutions = sp.solve(eq, x)
        
        steps = [
            f"Original: {equation_str}",
            f"Rewritten: {sp.latex(eq)} = 0",
            f"Solutions: {', '.join([str(sol) for sol in solutions])}",
            "Verify: Plug values back in."
        ]
        return {"solutions": [str(sol) for sol in solutions], "steps": steps}
    except Exception as e:
        return {"error": str(e)}

@app.route('/recognize', methods=['POST'])
def recognize():
    if 'image' not in request.files:
        return jsonify({"error": "No image provided"}), 400
    
    file = request.files['image']
    filename = secure_filename(file.filename)
    img_path = os.path.join('temp', filename)
    os.makedirs('temp', exist_ok=True)
    file.save(img_path)
    
    try:
        outs = p2t.recognize_text_formula(img_path, return_text=False)  # List format
        print("Raw Pix2Text output:", outs)  # Log for debugging
        
        equations = []
        for item in outs:
            text = item.get('text', '').strip()
            item_type = item.get('type')
            if item_type == 'formula' or (item_type in ['isolated', 'text'] and re.search(r'[=+\-*/xX]\s*[-]?[0-9]', text)):
                equations.append(text)
        
        if not equations:
            return jsonify({"error": "No equations detected"}), 404
        
        return jsonify({"equations": equations})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if os.path.exists(img_path):
            os.remove(img_path)

@app.route('/solve', methods=['POST'])
def solve():
    equation_str = request.json.get('equation')
    if not equation_str:
        return jsonify({"error": "No equation provided"}), 400
    
    result = solve_equation(equation_str)
    return jsonify(result)

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port)