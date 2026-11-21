import re,glob,sys,collections
from spellchecker import SpellChecker
sp=SpellChecker(language='de',case_sensitive=False)
texte=[]
for f in sorted(glob.glob('lib/**/*.dart',recursive=True)):
    s=open(f,encoding='utf-8').read()
    # Kommentare raus
    s=re.sub(r'//[^\n]*','',s)
    for m in re.finditer(r"'(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\"",s):
        t=m.group(0)[1:-1]
        t=re.sub(r'\$\{[^}]*\}|\$\w+',' ',t)
        if re.fullmatch(r'[\w./:-]*',t) and not ' ' in t: continue  # Keys, Pfade
        if t.startswith('http'): continue
        line=s[:m.start()].count('\n')+1
        texte.append((f.split('/')[-1],line,t))
woerter=collections.defaultdict(list)
for f,l,t in texte:
    for w in re.findall(r"[A-Za-zÄÖÜäöüß]+",t):
        if len(w)<3: continue
        woerter[w.lower()].append(f'{f}:{l}')
unbek=sp.unknown(list(woerter))
for w in sorted(unbek):
    print(w, woerter[w][:3])
# Zeichenprobleme
for f,l,t in texte:
    p=[]
    if '  ' in t: p.append('doppeltes Leerzeichen')
    if re.search(r'\s[,.;:!?]',t): p.append('Leerzeichen vor Satzzeichen')
    if re.search(r'"[A-Za-zÄÖÜäöü]',t) or "\\'" in t and False: p.append('gerade Anführungszeichen')
    if re.search(r'[a-zäöüß][.!?][A-ZÄÖÜ]',t): p.append('fehlendes Leerzeichen nach Satzende')
    if re.search(r'\b(\w+) \1\b',t,re.I): p.append('doppeltes Wort')
    if re.search(r'[a-zA-Z] - [a-zA-Z]',t): p.append('Bindestrich statt Gedankenstrich')
    if re.search(r'\.\.\.',t): p.append('drei Punkte statt …')
    if re.search(r'Ã|Â|â€',t): p.append('Kodierungsfehler')
    if p: print('ZEICHEN',f,l,p,t[:90])
