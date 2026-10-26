# Bíblias abertas para o Bereia — pacote 2026-10-26.1

Nove módulos de leitura local. Arquivos `.json.gz.b64` são JSON UTF-8 compactado com gzip e codificado em base64. O manifesto contém os hashes SHA-256 do download e do JSON descompactado, contagens e fontes fixadas por commit.

| Módulo | Conteúdo | Direitos |
|---|---|---|
| BLIVRE | Bíblia Livre, edição digital Textus Receptus (PorBLivreTR) | © Projeto Bíblia Livre; Diego Santos, Mario Sérgio, Marco Teles; CC BY 3.0 Brasil, conforme esta edição da fonte |
| WEB | World English Bible | Domínio público; nome identifica o texto original |
| BSB | Berean Standard Bible | Domínio público / CC0 |
| ASV | American Standard Version 1901 | Domínio público |
| RVR1909 | Reina-Valera 1909 | Domínio público |
| WLC | Westminster Leningrad Codex / OSHB | Texto-base em domínio público; edição OSHB CC BY 4.0 |
| SBLGNT | SBL Greek New Testament v1.2 | © 2010 Society of Biblical Literature e Logos Bible Software; CC BY 4.0 |
| LXX | Septuaginta Swete, coleção digital | Henry Barclay Swete; digitalização Open Greek and Latin / First1KGreek; extração Nathan D.; adaptação CC BY-SA 4.0 |
| VUL | Vulgata Clementina, incluindo apêndices da fonte | Domínio público |

## Escopo e fidelidade

Conversão estrutural, sem tradução automática, reconstrução de versículos ausentes ou preenchimento com outra tradução. Notas editoriais não integram estes módulos de leitura. As palavras gregas da coleção Swete e os fragmentos de parágrafos/poesia da WEB foram auditados contra as fontes. O WLC preserva vocalização e acentos do texto escrito (ketiv); delimitadores de morfologia foram removidos e variantes de leitura (qere) não foram fundidas ao texto. Morfologia não incluída nesta primeira versão.

A coleção Swete contém **55 livros/testemunhos**, incluindo variantes e escritos fora do cânon protestante. **Não contém Eclesiastes**. A Carta de Jeremias não apresenta divisão em versículos na fonte. Prólogos e seções com nomes próprios mantêm seus rótulos em `chapterLabels`; o índice numérico interno serve apenas à navegação. A Vulgata inclui deuterocanônicos e apêndices (inclusive Laodicenses), identificados como históricos. Essas coleções não definem o cânon do aplicativo. Não há alinhamento automático da numeração acadêmica com as traduções comuns.

## Licenças e fontes

Os créditos completos, links e condições acompanham **cada módulo** em `rights` e `provenance`. O texto convertido da LXX permanece sob [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/); o texto da Bíblia Livre desta edição digital permanece sob [CC BY 3.0 Brasil](https://creativecommons.org/licenses/by/3.0/br/). OSHB e SBLGNT estão sob [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). O uso desses dados em uma coleção não atribui às demais obras uma licença única.

Fontes: [Projeto Bíblia Livre](https://sites.google.com/site/biblialivre/), [WEB](https://ebible.org/web/), [Berean Bible](https://berean.bible/licensing.htm), [SBLGNT](https://www.sblgnt.com/), [OSHB](https://github.com/openscriptures/morphhb), [Swete digital](https://github.com/nathans/lxx-swete), [módulos digitalizados](https://github.com/scrollmapper/bible_databases), [WEB estruturada](https://github.com/TehShrike/world-english-bible). Os commits e hashes de cada arquivo usado constam do manifesto.

Não há ARA, NAA, NVI, NVT nem outro texto comercial protegido neste pacote. Bíblias e dados importados anteriormente pelo usuário não são publicados nem substituídos.
