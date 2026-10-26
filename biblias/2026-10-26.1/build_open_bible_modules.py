#!/usr/bin/env python3
"""Convert pinned open Bible sources; never translate, renumber or invent verses.

Downloads are a separate preparation step. This converter is offline and uses
only the Python standard library. Original licenses are retained in each module.
"""
import argparse
import collections
import gzip
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

def sha(data): return hashlib.sha256(data).hexdigest()
def read_json(path): return json.loads(path.read_text(encoding="utf-8-sig"))
def dump(data): return (json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()

class Builder:
    def __init__(self, sources, output):
        self.sources, self.output = Path(sources), Path(output)
        self.output.mkdir(parents=True, exist_ok=True)
        canonical_path = ROOT / "BereiaApp/Research/ScriptureReferenceIndex.swift"
        if canonical_path.exists():
            canonical = canonical_path.read_text()
            self.canonical = dict((name, int(n)) for name,n in re.findall(r'\("([^"]+)", (\d+)\)', canonical))
        else:
            self.canonical = dict(read_json(Path(__file__).with_name("canonical-books.json")))
        assert len(self.canonical) == 66
        self.entries = []
        self.source_records = []
        base = self.load("scrollmapper__bible_databases", "sources/pt/PorBLivreTR/PorBLivreTR.json")
        self.english = dict(zip([b["name"] for b in base["books"]], self.canonical, strict=True))
        self.english.update({"Tobit":"Tobias", "Judith":"Judite", "Wisdom":"Sabedoria", "Sirach":"Eclesiástico", "Baruch":"Baruc", "I Maccabees":"1 Macabeus", "II Maccabees":"2 Macabeus", "Prayer of Manasses":"Oração de Manassés (apêndice)", "I Esdras":"1 Esdras (apêndice)", "II Esdras":"2 Esdras (apêndice)", "Additional Psalm":"Salmo adicional (apêndice)", "Laodiceans":"Laodicenses (apêndice)"})

    def source(self, repo, path):
        info = read_json(self.sources / (repo + ".json"))
        raw = (self.sources / repo / path).read_bytes()
        url = "https://raw.githubusercontent.com/" + info["repo"] + "/" + info["sha"] + "/" + path
        self.source_records.append(dict(url=url, sha256=sha(raw), bytes=len(raw)))
        return raw, url

    def load(self, repo, path): return json.loads(self.source(repo, path)[0])

    def save(self, identifier, title, language, rights, verses, books, numbering, note=None, labels=None, source_start=0):
        assert verses and books
        academic = identifier in {"WLC", "SBLGNT", "LXX", "VUL"}
        limits = {b["name"]: b["chapters"] for b in books}
        assert len(limits) == len(books)
        if not academic: assert all(self.canonical.get(k) == n for k,n in limits.items())
        for key,text in verses.items():
            b,c,v = key.split("|")
            assert 1 <= int(c) <= limits[b] <= 200 and str(int(c)) == c, key
            assert re.fullmatch(r"(0|[1-9][0-9]{0,2})[A-Za-z0-9]{0,4}", v) and int(re.match(r"\d+",v)[0]) <= 300, key
            if not academic: assert v.isdigit() and 1 <= int(v) <= 176, key
            assert text.strip() and "<range>" not in text and "<w " not in text, key
        records = self.source_records[source_start:]
        provenance = "Conversão de formato para o Bereia; sem tradução automática. Fontes fixadas:\n" + "\n".join(r["url"] + " (SHA-256 " + r["sha256"] + ")" for r in records)
        edition = dict(id=identifier,title=title,language=language,provenance=provenance,rights=rights,verses=verses,books=books,numbering=numbering)
        if note: edition["coverageNote"] = note
        if labels: edition["chapterLabels"] = labels
        raw = dump(edition)
        assert len(raw) < 20*1024*1024
        compressed = gzip.compress(raw, mtime=0)
        (self.output/(identifier+".json")).write_bytes(raw)
        import base64
        encoded = base64.b64encode(compressed)
        (self.output/(identifier+".json.gz.b64")).write_bytes(encoded)
        self.entries.append(dict(id=identifier,title=title,path=identifier+".json.gz.b64",sha256=sha(raw),downloadSHA256=sha(encoded),bytes=len(raw),downloadBytes=len(encoded),verseCount=len(verses),bookCount=len(books),license=rights))
        print(identifier, len(books), "books", len(verses), "verses", len(encoded), "download bytes")

    def scrollmapper(self, source_id, identifier, title, language, rights, note=None):
        start = len(self.source_records)
        paths = [p for p in (self.sources/"scrollmapper__bible_databases/sources").glob("*/"+source_id+"/"+source_id+".json")]
        assert len(paths)==1
        path=str(paths[0].relative_to(self.sources/"scrollmapper__bible_databases"))
        obj=self.load("scrollmapper__bible_databases",path)
        license_text=self.source("scrollmapper__bible_databases",str(Path(path).with_name("README.md")))[0].decode()
        verses={}; books=[]
        for b in obj["books"]:
            name=self.english[b["name"]]
            books.append(dict(name=name,chapters=max(c["chapter"] for c in b["chapters"])))
            for c in b["chapters"]:
                for v in c["verses"]:
                    key=f"{name}|{c['chapter']}|{v['verse']}"
                    text=v["text"].strip()
                    if not text: continue # Empty source verse is unavailable, never generated.
                    assert key not in verses,key
                    verses[key]=text
        self.save(identifier,title,language,rights+"\n\nRegistro da fonte:\n"+license_text,verses,books,"Numeração da edição de origem",note=note,source_start=start)

    def web(self):
        start=len(self.source_records); verses={}; books=[]
        names={re.sub(r"[^a-z0-9]","",re.sub(r"^III ","3 ",re.sub(r"^II ","2 ",re.sub(r"^I ","1 ",en))).lower()):pt for en,pt in self.english.items() if pt in self.canonical}
        names["revelation"]=names.pop("revelationofjohn")
        by_book={}
        for p in sorted((self.sources/"TehShrike__world-english-bible/json").glob("*.json")):
            name=names[p.stem]; by_book[name]=[]
            for row in self.load("TehShrike__world-english-bible","json/"+p.name):
                if row["type"] not in {"paragraph text","line text"}: continue
                assert "chapterNumber" in row and "verseNumber" in row
                key=f"{name}|{row['chapterNumber']}|{row['verseNumber']}"
                if not row["value"].strip(): continue
                # A verse can have several paragraphs/poetry lines; retain all sections.
                verses[key]=verses.get(key,"")+row["value"]
                by_book[name].append(row["chapterNumber"])
        books=[dict(name=n,chapters=max(by_book[n])) for n in self.canonical]
        self.save("WEB","World English Bible","en","Domínio público. World English Bible / Michael Paul Johnson. Fonte oficial e condições: https://ebible.org/web/ . Conversão estrutural; palavras preservadas, sem notas editoriais. O nome World English Bible identifica o texto original, não uma tradução alterada.", {k:v.strip() for k,v in verses.items()}, books,"Numeração inglesa da edição WEB",source_start=start)

    def sbl(self):
        start=len(self.source_records); verses={}; books=[]
        code_names=dict(zip(["Matt","Mark","Luke","John","Acts","Rom","1Cor","2Cor","Gal","Eph","Phil","Col","1Thess","2Thess","1Tim","2Tim","Titus","Phlm","Heb","Jas","1Pet","2Pet","1John","2John","3John","Jude","Rev"],list(self.canonical)[39:],strict=True))
        for code,name in code_names.items():
            text=self.source("LogosBible__SBLGNT","data/sblgnt/text/"+code+".txt")[0].decode("utf-8-sig")
            for line in text.splitlines():
                if "\t" not in line: continue # Book title, not a verse.
                ref,value=line.split("\t",1)
                match=re.fullmatch(r"\S+ (\d+):(\d+)",ref); assert match,ref
                key=f"{name}|{int(match[1])}|{int(match[2])}"
                assert key not in verses and value.strip(),key
                verses[key]=value.strip()
            books.append(dict(name=name,chapters=self.canonical[name]))
        license_text=self.source("LogosBible__SBLGNT","LICENSE")[0].decode()
        self.save("SBLGNT","SBL Greek New Testament — v1.2","grc","© 2010 Society of Biblical Literature e Logos Bible Software. CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/ . Fonte: https://www.sblgnt.com/ . Apenas conversão de formato; sinais críticos preservados.\n\n"+license_text,verses,books,"Numeração do Novo Testamento SBLGNT",source_start=start)

    def hebrew(self):
        start=len(self.source_records); verses={}; books=[]
        codes=["Gen","Exod","Lev","Num","Deut","Josh","Judg","Ruth","1Sam","2Sam","1Kgs","2Kgs","1Chr","2Chr","Ezra","Neh","Esth","Job","Ps","Prov","Eccl","Song","Isa","Jer","Lam","Ezek","Dan","Hos","Joel","Amos","Obad","Jonah","Mic","Nah","Hab","Zeph","Hag","Zech","Mal"]
        ns={"o":"http://www.bibletechnologies.net/2003/OSIS/namespace"}
        for code,name in zip(codes,list(self.canonical)[:39],strict=True):
            tree=ET.fromstring(self.source("openscriptures__morphhb","wlc/"+code+".xml")[0])
            chapters=[]
            for verse in tree.findall(".//o:verse",ns):
                _,c,v=verse.attrib["osisID"].split("."); chapters.append(int(c)); tokens=[]
                for child in verse:
                    tag=child.tag.rsplit("}",1)[-1]
                    if tag=="w": tokens.append("".join(child.itertext()).replace("/",""))
                    elif tag=="seg":
                        value="".join(child.itertext())
                        if tokens: tokens[-1]+=value
                        else: tokens.append(value)
                    # qere/critical notes are not silently merged with the ketiv text.
                text=" ".join(tokens).replace("־ ","־").strip()
                key=f"{name}|{c}|{v}"; assert key not in verses and text,key
                verses[key]=text
            books.append(dict(name=name,chapters=max(chapters)))
        license_text=self.source("openscriptures__morphhb","LICENSE.md")[0].decode()
        self.save("WLC","Bíblia Hebraica — WLC / OSHB","hbo","Texto-base Westminster Leningrad Codex em domínio público. Edição Open Scriptures Hebrew Bible: CC BY 4.0; créditos a Open Scriptures, Daniel Owens, David Troidl e Christopher V. Kimball. Fonte: https://github.com/openscriptures/morphhb . Conversão de formato: delimitadores morfológicos removidos; texto escrito (ketiv), sem incorporar notas de leitura (qere). Morfologia não incluída nesta primeira edição.\n\n"+license_text,verses,books,"Numeração hebraica da edição OSHB; pode diferir da portuguesa",note="Antigo Testamento em hebraico e seus trechos em aramaico. Texto vocalizado e acentuado; notas e análises morfológicas não fazem parte deste módulo de leitura.",source_start=start)

    def lxx(self):
        start=len(self.source_records); verses={}; books=[]; labels={}
        names={1:"Gênesis",2:"Êxodo",3:"Levítico",4:"Números",5:"Deuteronômio",6:"Josué",8:"Juízes",10:"Rute",11:"1 Samuel",12:"2 Samuel",13:"1 Reis",14:"2 Reis",15:"1 Crônicas",16:"2 Crônicas",17:"1 Esdras (grego)",18:"Esdras B",19:"Ester",20:"Judite",21:"Tobias",23:"1 Macabeus",24:"2 Macabeus",25:"3 Macabeus",26:"4 Macabeus",27:"Salmos",28:"Odes",29:"Provérbios",31:"Cântico dos Cânticos",32:"Jó",33:"Sabedoria de Salomão",34:"Eclesiástico",35:"Salmos de Salomão",36:"Oseias",37:"Amós",38:"Miqueias",39:"Joel",40:"Obadias",41:"Jonas",42:"Naum",43:"Habacuque",44:"Sofonias",45:"Ageu",46:"Zacarias",47:"Malaquias",48:"Isaías",49:"Jeremias",50:"Baruc",51:"Lamentações",52:"Carta de Jeremias",53:"Ezequiel",54:"Susana (grego antigo)",55:"Susana (Teodócio)",56:"Daniel (grego antigo)",57:"Daniel (Teodócio)",58:"Bel e o Dragão (grego antigo)",59:"Bel e o Dragão (Teodócio)"}
        files=sorted((self.sources/"nathans__lxx-swete/data").glob("*.txt"))
        assert len(files)==len(names)
        for p in files:
            code=int(p.name.split(".",1)[0]); name=names[code]
            rows=[]
            for line in self.source("nathans__lxx-swete","data/"+p.name)[0].decode().splitlines():
                ref,token=line.split(" ",1); b,c,v=ref.split(".")
                assert int(b)==code and token.strip(),line
                rows.append((c,v,token))
            numeric={int(c) for c,_,_ in rows if c.isdigit() and int(c)>0}
            special=list(dict.fromkeys(c for c,_,_ in rows if not c.isdigit() or int(c)==0))
            mapping={c:max(numeric,default=0)+1+i for i,c in enumerate(special)}
            for c,n in mapping.items(): labels[f"{name}|{n}"]=("Texto integral (sem numeração na fonte)" if not numeric else "Prólogo") if c in {"prologue","0"} else c.upper()
            for c,v,token in rows:
                chapter=int(c) if c.isdigit() and int(c)>0 else mapping[c]
                key=f"{name}|{chapter}|{v}"
                verses[key]=verses.get(key,"")+(" " if key in verses else "")+token
            books.append(dict(name=name,chapters=max(numeric|set(mapping.values()))))
        self.source("nathans__lxx-swete","README.md")
        self.save("LXX","Septuaginta Swete — coleção digital","grc","CC BY-SA 4.0 — https://creativecommons.org/licenses/by-sa/4.0/ . Henry Barclay Swete; digitalização Open Greek and Latin / First1KGreek; extração Nathan D. GitHub nathans/lxx-swete. Conversão de palavras em versículos e nomes de navegação em português; texto grego e rótulos de origem preservados. Esta adaptação do texto permanece CC BY-SA 4.0.",verses,books,"Numeração grega da fonte Swete, sem alinhamento automático ao hebraico",note=f"Coleção digital de {len(books)} livros/testemunhos da fonte, incluindo deuterocanônicos, outros escritos e versões alternativas. Eclesiastes não está disponível nesta coleção. A Carta de Jeremias vem sem divisão em versículos na fonte. A presença de um livro aqui não define o cânon do Bereia.",labels=labels,source_start=start)

    def run(self):
        self.scrollmapper("PorBLivreTR","BLIVRE","Bíblia Livre — Textus Receptus","pt-BR","© Projeto Bíblia Livre: Diego Santos, Mario Sérgio e Marco Teles. Edição digital PorBLivreTR: CC BY 3.0 Brasil — https://creativecommons.org/licenses/by/3.0/br/ . Fonte: https://sites.google.com/site/biblialivre/ . Conversão de formato e nomes de navegação; palavras preservadas.")
        self.scrollmapper("ASV","ASV","American Standard Version — 1901","en","Domínio público; American Standard Version (1901).")
        self.scrollmapper("BSB","BSB","Berean Standard Bible","en","Domínio público / CC0. Berean Bible: dedicação ao domínio público em 30/04/2023 — https://berean.bible/licensing.htm .")
        self.scrollmapper("SpaRV","RVR1909","Reina-Valera — 1909","es","Domínio público; Reina-Valera 1909.")
        self.scrollmapper("VulgClementine","VUL","Vulgata Clementina — latim","la","Domínio público; edição digital VulgClementine.",note="Edição histórica com deuterocanônicos e apêndices. A fonte inclui Oração de Manassés, Esdras adicionais, Salmo adicional e Laodicenses; os apêndices não integram o cânon protestante.")
        self.web(); self.sbl(); self.hebrew(); self.lxx()
        manifest=dict(format=1,editions=self.entries,sources=self.source_records)
        (self.output/"manifest.json").write_bytes(dump(manifest))
        return manifest

if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("sources");parser.add_argument("output")
    args=parser.parse_args();Builder(args.sources,args.output).run()
