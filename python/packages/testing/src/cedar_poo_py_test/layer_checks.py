"""Check local Lean import closure for library and Production isolation."""
from pathlib import Path
import re


def imports(source: str) -> list[str]:
    # Lean block comments nest. Preserve newlines so commands in comments cannot
    # invent edges and a comment cannot join two otherwise separate lines.
    cleaned = []
    depth = 0
    index = 0
    while index < len(source):
        if source.startswith('/-', index):
            depth += 1
            cleaned.extend('  ')
            index += 2
        elif depth and source.startswith('-/', index):
            depth -= 1
            cleaned.extend('  ')
            index += 2
        elif not depth and source.startswith('--', index):
            end = source.find('\n', index)
            if end < 0:
                break
            cleaned.extend(' ' * (end - index))
            index = end
        else:
            cleaned.append(source[index] if not depth or source[index] == '\n' else ' ')
            index += 1
    if depth:
        raise ValueError("Unclosed Lean block comment")
    result = []
    reading = False
    commands = {"namespace", "section", "open", "def", "theorem", "structure", "class",
                "instance", "inductive", "abbrev", "opaque", "axiom", "attribute",
                "set_option", "universe", "variable", "noncomputable", "export"}
    for token in re.findall(r"[A-Za-z_][A-Za-z0-9_'.]*|\S", ''.join(cleaned)):
        if token == "prelude" and not reading:
            continue
        if token == "import":
            reading = True
        elif reading and token not in commands and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_'.]*", token):
            result.append(token)
        else:
            break
    return result



def run(repository: Path) -> None:
    repository = repository.resolve()
    files = list(repository.glob('*.lean'))
    for layer in ('CedarPooSpec', 'Productions', 'Examples', 'Tests', 'Benchmarks'):
        files.extend((repository / layer).rglob('*.lean'))
    graph = {str(p.relative_to(repository))[:-5].replace('/', '.'): imports(p.read_text())
             for p in files}
    for root in sorted(graph):
        if not (root == 'CedarPooSpec' or root == 'Productions' or root.startswith(('CedarPooSpec.', 'Productions.'))):
            continue
        forbidden = ('Examples', 'Tests', 'Productions') if root.startswith('CedarPooSpec') else ('Examples', 'Tests')
        todo = [(root, [root])]
        seen = set()
        while todo:
            module, path = todo.pop()
            if module in seen:
                continue
            seen.add(module)
            for dependency in graph.get(module, []):
                if any(dependency == layer or dependency.startswith(layer + '.') for layer in forbidden):
                    raise ValueError('Lean layer boundary: ' + ' -> '.join(path + [dependency]))
                if dependency not in graph:
                    target = repository / (dependency.replace('.', '/') + '.lean')
                    if target.is_file():
                        graph[dependency] = imports(target.read_text())
                todo.append((dependency, path + [dependency]))
    print(f'LEAN-LAYERS-OK {len(graph)} local modules; library/Production import closures checked', flush=True)
