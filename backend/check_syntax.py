import ast, sys

try:
    with open('main.py', 'r', encoding='utf-8') as f:
        s = f.read()
    ast.parse(s)
    print('AST parse OK')
except SyntaxError as e:
    print('SyntaxError at line', e.lineno, e.msg)
    print('Text:', e.text)
    sys.exit(1)
except Exception as e:
    print('Error:', e)
    sys.exit(1)
