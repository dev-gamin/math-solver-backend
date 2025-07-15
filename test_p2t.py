from pix2text import Pix2Text

p2t = Pix2Text.from_config()  # Loads default models
img_path = r'c:\MathSolver\Equation Images\a.png'  # Use raw string (r prefix) for Windows paths
outs = p2t.recognize_text_formula(img_path, return_text=True)  # For mixed images with formulas
print(outs)  # Outputs list of dicts, e.g., [{'type': 'formula', 'text': '\\frac{1}{2}'}]