"""Generate SQL INSERT statements from the Material Design Icons directory tree."""
import os
import re

BASE = 'C:/Git/KM/pure-admin-icons/.cache/icons/material/material-design-icons-master'
OUT  = '999-examples-icons-data.sql'


def path_to_ltree(p: str) -> str:
    segs = p.lower().split('/')
    out = []
    for s in segs:
        if not s:
            continue
        c = re.sub(r'[^a-z0-9_]', '_', s)
        c = re.sub(r'_+', '_', c)
        c = c.strip('_')
        if c:
            out.append(c)
    return '.'.join(out)


def main():
    rows = []
    for root, dirs, files in os.walk(BASE):
        root_n = root.replace(os.sep, '/')
        rel_root = root_n[len(BASE) + 1:] if len(root_n) > len(BASE) else ''
        for d in sorted(dirs):
            rel = d if not rel_root else rel_root + '/' + d
            rows.append((rel, 'folder', d))
        for f in sorted(files):
            rel = f if not rel_root else rel_root + '/' + f
            rows.append((rel, 'file', f))

    def sqlesc(s: str) -> str:
        return s.replace("'", "''")

    with open(OUT, 'w', encoding='utf-8') as fh:
        fh.write('-- Auto-generated from Material Design Icons repository\n')
        fh.write('-- Regenerate via: python gen_icons_inserts.py\n')
        fh.write(f'-- Total rows: {len(rows)}\n\n')
        batch = 500
        for i in range(0, len(rows), batch):
            chunk = rows[i:i + batch]
            tuples = []
            for rel, kind, name in chunk:
                lt = path_to_ltree(rel)
                if not lt:
                    continue
                tuples.append(
                    f"('{lt}'::ext.ltree, '/{sqlesc(rel)}', '{kind}', '{sqlesc(name)}')"
                )
            if not tuples:
                continue
            fh.write('insert into demo.fs_item (path, display_path, kind, name) values\n')
            fh.write(',\n'.join(tuples))
            fh.write('\non conflict (path) do nothing;\n\n')

    print(f'wrote {len(rows)} rows to {OUT}')


if __name__ == '__main__':
    main()
