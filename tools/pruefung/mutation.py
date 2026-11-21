import subprocess,sys,shutil,os
root=sys.argv[1]; testcmd=sys.argv[2]; cwd=sys.argv[3]
muts=eval(open(sys.argv[4]).read())
for name,(f,a,b) in muts.items():
    p=os.path.join(root,f); orig=open(p).read()
    if a not in orig: print(f'{name}: MUSTER NICHT GEFUNDEN'); continue
    open(p,'w').write(orig.replace(a,b,1))
    try:
        r=subprocess.run(testcmd,shell=True,cwd=cwd,capture_output=True,text=True,timeout=900)
        out=r.stdout+r.stderr
        erkannt = 'Some tests failed' in out or 'Failed to load' in out or r.returncode!=0
        grund=''
        for l in out.splitlines():
            if 'Seed' in l or 'Expected' in l or 'fehlt' in l or 'Error' in l:
                grund=l.strip()[:150]; break
        print(f'{name}: {"ERKANNT" if erkannt else "NICHT ERKANNT"}  {grund}',flush=True)
    finally:
        open(p,'w').write(orig)
