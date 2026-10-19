#!/usr/bin/env python3
"""Sincroniza sólo el agua con el dataset servidor; conserva gráficos, techos y bloqueos."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re

PATTERN = re.compile(r'(metadata/data = PackedByteArray\(")([A-Za-z0-9+/=]+)("\))')


def build(source, scenes):
    masks = {int(p.stem[3:]): bytearray(10000) for p in scenes.glob('Map*.tscn') if p.stem[3:].isdigit()}
    if not masks:
        raise ValueError('Faltan escenas de mapas')
    sources = {}
    for path in sorted([*source.glob('objects_*.json'), *source.glob('blocked_*.json')]):
        sources[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        for line in path.read_text().splitlines():
            if not line.strip(): continue
            row = json.loads(line)
            if row.get('t') not in ('water', 'w'): continue
            mid, x, y = (int(row[k]) for k in ('m', 'x', 'y'))
            if mid not in masks or not 1 <= x <= 100 or not 1 <= y <= 100:
                raise ValueError('Agua con mapa o coordenadas inválidas')
            masks[mid][x - 1 + (y - 1) * 100] = 4
    if not sources or not any(any(mask) for mask in masks.values()):
        raise ValueError('Dataset acuático ausente o vacío')
    return {'version': 1, 'sources': sources, 'maps': {str(mid): base64.b64encode(mask).decode('ascii') for mid, mask in sorted(masks.items())}}


def sync_scenes(data, scenes, *, check=False):
    changed = []
    pending = []
    for mid, encoded in data['maps'].items():
        mask = base64.b64decode(encoded, validate=True)
        path = scenes / f'Map{mid}.tscn'
        text = path.read_text()
        match = PATTERN.search(text)
        if match is None: raise ValueError(f'Escena sin datos: {mid}')
        original = base64.b64decode(match[2], validate=True)
        if len(original) != 10000 or len(mask) != 10000: raise ValueError('Longitud de mapa inválida')
        updated = bytes((value & ~4) | water for value, water in zip(original, mask, strict=True))
        if original != updated:
            changed.append(int(mid))
            pending.append((path, text[:match.start(2)] + base64.b64encode(updated).decode('ascii') + text[match.end(2):]))
    # Primero validar todas las escenas; no dejar una sincronización parcial por un error.
    if not check:
        for path, text in pending: path.write_text(text)
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--scenes', type=Path, default=Path('Maps'))
    parser.add_argument('--output', type=Path, default=Path('protocol/water-masks.json'))
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = build(args.source, args.scenes)
    changed = sync_scenes(data, args.scenes, check=args.check)
    if args.check:
        if changed or json.loads(args.output.read_text()) != data: raise SystemExit('Las máscaras acuáticas requieren regeneración')
    else:
        args.output.write_text(json.dumps(data, separators=(',', ':')) + '\n')
    print(json.dumps({'maps': len(data['maps']), 'changed_scenes': len(changed), 'checked': args.check}))


if __name__ == '__main__': main()
