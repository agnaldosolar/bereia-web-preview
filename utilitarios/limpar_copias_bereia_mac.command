#!/bin/bash
set -euo pipefail
command -v python3 >/dev/null || { echo "Python 3 não localizado. Nada foi removido."; exit 21; }
python3 - <<'BEREIA_CLEANUP_PYTHON'
#!/usr/bin/env python3
"""Select only app rollback copies and verified Xcode output; recycle with native macOS Trash."""
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import uuid


def require_closed():
    text = subprocess.run(['/bin/ps','-axo','command='],capture_output=True,text=True,check=True).stdout
    if any('/BereiaMac.app/Contents/MacOS/' in line or '/Bereia.app/Contents/MacOS/' in line or
           '/Contents/MacOS/Xcode' in line or ('xcodebuild' in line and 'ProjetoBereia' in line) for line in text.splitlines()):
        raise ValueError('Feche o Bereia com Command + Q e aguarde qualquer compilação terminar.')


def app_info(path):
    if path.is_symlink() or not path.is_dir(): raise ValueError('Aplicativo inválido.')
    info = plistlib.loads((path/'Contents/Info.plist').read_bytes())
    sha = info.get('BereiaSourceSHA256','')
    if info.get('CFBundleIdentifier') != 'org.bereia.mac' or not re.fullmatch('[a-f0-9]{64}',sha): raise ValueError('Identificação do aplicativo inválida.')
    return info


def roots(home):
    preps = home/'Bereia-Local/Atualizador/Preparos'
    return [preps] + sorted(preps.glob('Legado-*')) + [home/'Bereia-Atualizacoes']


def sources(home):
    candidates = [home/'Bereia-Local-Build/Fonte'] + sorted(home.glob('Bereia-Cadastro-*/BuildAtualizado/Fonte'))
    for root in roots(home): candidates += sorted(root.glob('Bereia-Cadastro-*/BuildAtualizado/Fonte'))
    archive = home/'Bereia-Local/Arquivo/Versoes-antigas'
    for old in [home/'Bereia OLD'] + sorted(archive.glob('Bereia OLD*')):
        candidates += [old/'Bereia-Local-Build/Fonte'] + sorted(old.glob('Bereia-Cadastro-*/BuildAtualizado/Fonte'))
    return candidates + sorted(archive.glob('Bereia-Local-Build*/Fonte'))


def source_hash(folder):
    manifest = folder/'integridade_codigo.json'
    if folder.is_symlink() or manifest.is_symlink(): raise ValueError('Fonte em forma de atalho.')
    data = manifest.read_bytes()
    if not isinstance(json.loads(data),dict): raise ValueError('Manifesto inválido.')
    return hashlib.sha256(data).hexdigest()


def plan_cleanup(home):
    home = Path(home).resolve(); package = home/'Bereia-Local'
    for path in [package,package/'Aplicativo',package/'Atualizador',package/'Atualizador/Preparos',package/'Arquivo']:
        if path.is_symlink(): raise ValueError('O caminho principal contém um atalho; limpeza não iniciada.')
    marker = json.loads((package/'bereia-local.json').read_bytes())
    if any(marker.get(k)!=v for k,v in dict(schema=1,mode='local',dataDirectory='Dados',mediaDirectory='Hinos').items()): raise ValueError('Instalação local não reconhecida.')
    current = package/'Aplicativo/BereiaMac.app'; info = app_info(current)
    known_sources = []
    for folder in sources(home):
        try:
            sha = source_hash(folder)
            known_sources.append((folder,sha))
        except (OSError,ValueError): pass
    matching = [folder for folder,sha in known_sources if sha == info['BereiaSourceSHA256']]
    if not matching: raise ValueError('Não localizei a fonte exata do aplicativo instalado. Nada será removido.')
    backups = []; skipped = []
    for path in (package/'Aplicativo').glob('BereiaMac-anterior-*.app'):
        try:
            if not re.fullmatch(r'BereiaMac-anterior-[a-f0-9]{32}\.app',path.name): raise ValueError('Nome não reconhecido')
            previous = app_info(path)
            backups.append((path, previous, getattr(path.stat(),'st_birthtime',(path/'Contents/Info.plist').stat().st_mtime)))
        except (OSError,ValueError): skipped.append(str(path))
    backups.sort(key=lambda item:(item[2],item[0].name),reverse=True)
    reserve = backups[0][0] if backups else None
    protected_hashes = {info['BereiaSourceSHA256']}
    if backups: protected_hashes.add(backups[0][1]['BereiaSourceSHA256'])
    moves = [path for path,_,_ in backups[1:]]
    builds = []
    for root in roots(home):
        if root.is_symlink(): raise ValueError('Pasta de preparos em forma de atalho; limpeza interrompida.')
        for build in root.glob('Bereia-Cadastro-*/BuildAtualizado'):
            generated = build/'Build'
            if not generated.exists(): continue
            try:
                if any(p.is_symlink() for p in [build.parent,build,generated]): raise ValueError('Atalho')
                sha = source_hash(build/'Fonte')
                identity = json.loads((build/'Logs/build-identity.json').read_bytes())
                if identity.get('sourceSHA256') != sha or not (generated/'Build/Intermediates.noindex').is_dir(): raise ValueError('Saída não confirmada')
                builds.append((generated,sha,build.stat().st_mtime))
            except (OSError,ValueError): skipped.append(str(generated))
    newest = max(builds,key=lambda b:b[2])[0] if builds else None
    for generated,sha,_ in builds:
        if sha not in protected_hashes and generated != newest: moves.append(generated)
    return dict(package=str(package),current=str(current),reserve=str(reserve) if reserve else None,
                sourceSHA256=info['BereiaSourceSHA256'],sources=[str(p) for p in matching],
                keepNewestBuild=str(newest) if newest else None,moves=[str(p) for p in moves],skipped=skipped)


SWIFT_TRASH = r'''
import AppKit
import Foundation
let paths = try JSONDecoder().decode([String].self, from: FileHandle.standardInput.readDataToEndOfFile())
final class CompletionState: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func finish() { lock.lock(); done = true; lock.unlock() }
    var isDone: Bool { lock.lock(); defer { lock.unlock() }; return done }
}
let state = CompletionState()
NSWorkspace.shared.recycle(paths.map { URL(fileURLWithPath: $0) }) { [state] mapping, error in
    let entries = (mapping ?? [:]).map { ["source": $0.key.path, "trash": $0.value.path] }
    let result: [String: Any] = ["moved": entries, "error": error?.localizedDescription ?? ""]
    if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
    state.finish()
}
while !state.isDone { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05)) }
'''


def recycle(paths):
    with tempfile.TemporaryDirectory(prefix='Bereia-Limpeza-') as temporary:
        helper = Path(temporary)/'Trash.swift'; helper.write_text(SWIFT_TRASH)
        result = subprocess.run(['/usr/bin/swift',str(helper)],input=json.dumps(paths),text=True,capture_output=True)
        if result.returncode: raise ValueError('O macOS não confirmou a movimentação para a Lixeira: '+result.stderr[-2000:])
        return json.loads(result.stdout.strip())


def clean(home,closed_check=require_closed,recycler=recycle):
    plan = plan_cleanup(home); closed_check()
    package = Path(plan['package'])
    if (package/'.bereia-atualizacao.lock').exists(): raise ValueError('Há uma atualização em andamento.')
    if not plan['moves']: return plan,dict(moved=[],error=''),None
    folder = package/'Arquivo/Relatorios'; folder.mkdir(parents=True,exist_ok=True)
    report = folder/('limpeza-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8]+'.json')
    record = dict(schema=1,plan=plan,state='planejado')
    report.write_text(json.dumps(record,ensure_ascii=False,indent=2))
    closed_check()
    # Recompute immediately before recycling: changed apps, newer backups or builds invalidate the plan.
    if plan_cleanup(home) != plan: raise ValueError('As pastas mudaram durante a conferência. Execute novamente.')
    result = recycler(plan['moves'])
    record.update(state='concluido' if not result.get('error') else 'parcial',result=result)
    report.write_text(json.dumps(record,ensure_ascii=False,indent=2))
    if app_info(Path(plan['current']))['BereiaSourceSHA256'] != plan['sourceSHA256'] or not any(source_hash(Path(p))==plan['sourceSHA256'] for p in plan['sources']): raise ValueError('Confira a instalação antes de esvaziar a Lixeira. Relatório: '+str(report))
    return plan,result,str(report)


def main():
    if sys.platform != 'darwin': raise ValueError('Execute no Mac do Bereia.')
    plan = plan_cleanup(Path.home()); require_closed()
    print('Aplicativo atual e fonte necessária às atualizações: preservados.',flush=True)
    print('Versão anterior de reserva: '+(plan['reserve'] or 'nenhuma encontrada'),flush=True)
    print('Itens selecionados para a Lixeira: '+str(len(plan['moves'])),flush=True)
    allocated = 0
    for path in plan['moves']:
        output = subprocess.run(['/usr/bin/du','-sk',path],capture_output=True,text=True)
        try: allocated += int(output.stdout.split()[0]) * 1024
        except (ValueError,IndexError): pass
    print('Tamanho aproximado selecionado: {:.1f} GB'.format(allocated / 1024**3),flush=True)
    if plan['skipped']: print('Itens não reconhecidos e mantidos: '+str(len(plan['skipped'])),flush=True)
    plan,result,report = clean(Path.home())
    print('Itens enviados à Lixeira: '+str(len(result.get('moved',[]))))
    print('Dados, Hinos, fontes e Arquivo/Versoes-antigas não foram removidos.')
    print('O espaço só será liberado após esvaziar a Lixeira. Primeiro, abra e confira o Bereia.')
    if report: print('Relatório: '+report)
    if result.get('error'): raise ValueError(result['error'])


if __name__=='__main__':
    try: main()
    except Exception as error: print('Limpeza interrompida: '+str(error)); sys.exit(1)

BEREIA_CLEANUP_PYTHON
