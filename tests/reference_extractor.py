"""Modelo ejecutable de la guía manual; NO se ejecuta en Architect ni consulta pedidos."""
DIGITS = '0123456789'
LETTERS = 'abcdefghijklmnopqrstuvwxyzáéíóúüñ'

def extract_order(body):
    if body is None:
        return '', False
    if len(body) > 16000:
        return '', True
    remaining = body.lower().replace('\r', ' ').replace('\n', ' ').replace('\t', ' ').replace('ú', 'u')
    first = ''
    ambiguous = False
    for _ in range(10):
        pos = remaining.find('pedido')
        if pos < 0:
            return first, ambiguous
        before = remaining[pos - 1] if pos > 0 else ''
        after = remaining[pos + 6:].strip()
        remaining = after
        if before and before in LETTERS + DIGITS:
            continue
        if after.startswith(':'):
            after = after[1:].strip()
        if after.startswith('numero '):
            after = after[7:].strip()
        if after.startswith(':'):
            after = after[1:].strip()
        candidate = ''
        for char in after[:8]:
            if char not in DIGITS:
                break
            candidate += char
        if len(candidate) != 7:
            continue
        if len(after) > 7 and after[7] in LETTERS + DIGITS:
            continue
        if not first:
            first = candidate
        elif candidate != first:
            ambiguous = True
    return first, ambiguous or 'pedido' in remaining
