#!/bin/bash
set -euo pipefail
command -v python3 >/dev/null || { echo "Python 3 não localizado. Nada foi movido."; exit 21; }
python3 - <<'BEREIA_ORGANIZE_PYTHON'
#!/usr/bin/env python3
"""Concentrate known legacy folders without merging/deleting files or changing the live app/data."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import uuid


def source_candidates(home):
    package = home/'Bereia-Local'; preparations = package/'Atualizador/Preparos'
    roots = [preparations] + sorted(preparations.glob('Legado-*')) + [home/'Bereia-Atualizacoes']
    candidates = [home/'Bereia-Local-Build/Fonte'] + sorted(home.glob('Bereia-Cadastro-*/BuildAtualizado/Fonte'))
    for root in roots: candidates += sorted(root.glob('Bereia-Cadastro-*/BuildAtualizado/Fonte'))
    archives = package/'Arquivo/Versoes-antigas'
    for old in [home/'Bereia OLD'] + sorted(archives.glob('Bereia OLD*')):
        candidates += [old/'Bereia-Local-Build/Fonte'] + sorted(old.glob('Bereia-Cadastro-*/BuildAtualizado/Fonte'))
    candidates += sorted(archives.glob('Bereia-Local-Build*/Fonte'))
    return candidates


def matching_source(home, source_sha):
    for folder in source_candidates(home):
        manifest = folder/'integridade_codigo.json'
        if manifest.is_file() and not manifest.is_symlink() and hashlib.sha256(manifest.read_bytes()).hexdigest() == source_sha:
            return folder
    raise ValueError('Não localizei a fonte do aplicativo instalado. Nenhuma pasta será movida.')


def require_closed():
    result = subprocess.run(['/bin/ps', '-axo', 'command='], capture_output=True, text=True, check=True)
    for line in result.stdout.splitlines():
        if '/BereiaMac.app/Contents/MacOS/' in line or '/Bereia.app/Contents/MacOS/' in line or ('xcodebuild' in line and 'ProjetoBereia' in line):
            raise ValueError('Feche o Bereia com Command + Q e aguarde qualquer atualização/compilação terminar.')


def unique(folder, name):
    target = folder/name; index = 2
    while target.exists() or target.is_symlink(): target = folder/(name + ' (' + str(index) + ')'); index += 1
    return target


def organize(home, closed_check=require_closed):
    home = Path(home).resolve(); package = home/'Bereia-Local'
    for folder in [package, package/'Atualizador', package/'Arquivo', package/'Arquivo/Versoes-antigas', package/'Atualizador/Preparos']:
        if folder.is_symlink() or (folder.exists() and not folder.is_dir()): raise ValueError('Uma pasta de destino é um atalho ou arquivo. Nada foi movido.')
    marker_path = package/'bereia-local.json'
    marker_bytes = marker_path.read_bytes(); marker = json.loads(marker_bytes)
    if any(marker.get(key) != value for key, value in dict(schema=1, mode='local', dataDirectory='Dados', mediaDirectory='Hinos').items()): raise ValueError('Instalação local não reconhecida.')
    info_path = package/'Aplicativo/BereiaMac.app/Contents/Info.plist'
    info_bytes = info_path.read_bytes(); info = plistlib.loads(info_bytes)
    if info.get('CFBundleIdentifier') != 'org.bereia.mac': raise ValueError('Aplicativo local não reconhecido.')
    source_sha = info.get('BereiaSourceSHA256')
    if not isinstance(source_sha, str) or len(source_sha) != 64: raise ValueError('Identificação da fonte ausente.')
    matching_source(home, source_sha); closed_check()
    if (package/'.bereia-atualizacao.lock').exists(): raise ValueError('Há uma atualização em andamento. Aguarde sua conclusão.')
    archive = package/'Arquivo/Versoes-antigas'; archive.mkdir(parents=True, exist_ok=True)
    preparations = package/'Atualizador/Preparos'; preparations.mkdir(parents=True, exist_ok=True)
    moves = []
    for name in ['Bereia', 'Bereia OLD', 'Bereia-Local-Build']:
        source = home/name
        if source.is_symlink(): raise ValueError('A pasta ' + name + ' é um atalho; precisa de conferência antes de mover.')
        if source.is_dir(): moves.append((source, unique(archive, name)))
    old_updates = home/'Bereia-Atualizacoes'
    if old_updates.is_symlink(): raise ValueError('Bereia-Atualizacoes é um atalho; precisa de conferência.')
    if old_updates.is_dir(): moves.append((old_updates, preparations/('Legado-' + uuid.uuid4().hex)))
    # Keep direct legacy preparation names at a supported lookup level.
    for source in sorted(home.glob('Bereia-Cadastro-*')):
        if source.is_symlink(): raise ValueError('Há um preparo em forma de atalho; nenhuma movimentação foi iniciada.')
        if source.is_dir():
            if (preparations/source.name).exists():
                bucket = preparations/('Legado-' + uuid.uuid4().hex); bucket.mkdir()
                target = bucket/source.name
            else: target = preparations/source.name
            moves.append((source, target))
    if not moves: return {'moved': 0, 'report': None, 'root': str(package)}
    report = package/'Arquivo'/('organizacao-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8] + '.json')
    record = dict(schema=1, state='planejado', moves=[dict(source=str(a), target=str(b)) for a,b in moves])
    def write_report():
        temporary = report.with_suffix('.tmp'); temporary.write_text(json.dumps(record, ensure_ascii=False, indent=2)); os.replace(temporary, report)
    write_report(); completed = []
    try:
        for source, target in moves:
            closed_check()
            if target.exists() or target.is_symlink(): raise ValueError('O destino foi ocupado; a movimentação foi interrompida.')
            source.rename(target); completed.append((source,target))
            record['completed'] = len(completed); write_report()
        matching_source(home, source_sha)
        if info_path.read_bytes() != info_bytes or marker_path.read_bytes() != marker_bytes: raise ValueError('A instalação foi alterada durante a organização.')
        record['state'] = 'concluido'; write_report()
    except Exception:
        failures = []
        for source,target in reversed(completed):
            try:
                if source.exists() or source.is_symlink(): raise ValueError('Origem ocupada')
                target.rename(source)
            except Exception: failures.append(dict(source=str(source), target=str(target)))
        record['state'] = 'revertido' if not failures else 'reversao-incompleta'; record['pendingRollback'] = failures
        write_report()
        raise ValueError('Organização interrompida. Consulte o relatório: ' + str(report))
    return {'moved':len(moves), 'report':str(report), 'root':str(package)}


def main():
    if sys.platform != 'darwin': raise ValueError('Execute este organizador no Mac onde está o Bereia.')
    result = organize(Path.home())
    print('Pastas reunidas em: ' + result['root'])
    print('Pastas movidas: ' + str(result['moved']))
    print('Nenhum arquivo foi excluído ou mesclado. Aplicativo e dados atuais preservados.')
    if result['report']: print('Relatório para conferência/reversão: ' + result['report'])
    subprocess.run(['/usr/bin/open', result['root']], check=False)


if __name__ == '__main__':
    try: main()
    except Exception as error: print('Organização interrompida: ' + str(error)); sys.exit(1)

BEREIA_ORGANIZE_PYTHON
