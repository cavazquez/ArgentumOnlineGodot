#!/usr/bin/env python3
"""Convierte MIDI del cliente AO propio a Ogg con un banco General MIDI explícito."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--soundfont',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=Path('Assets/Music'))
    parser.add_argument('--jobs',type=int,default=2)
    args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    sf=args.soundfont.resolve()
    def convert(source):
        destination=args.output/(source.stem+'.ogg')
        with tempfile.TemporaryDirectory(prefix='pyao-music-') as work:
            wave=Path(work)/'track.wav'
            subprocess.run(['fluidsynth','-ni','-F',str(wave),'-r','22050','-o','synth.cpu-cores=1','-o','synth.reverb.active=0','-o','synth.chorus.active=0',str(sf),str(source)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=60,env=dict(os.environ,OMP_NUM_THREADS='1',OMP_THREAD_LIMIT='1'))
            subprocess.run(['ffmpeg','-nostdin','-v','error','-y','-i',str(wave),'-map_metadata','-1','-ac','1','-ar','22050','-c:a','libvorbis','-q:a','3',str(destination)],check=True,timeout=60)
        return {'id':int(source.stem),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'ogg_sha256':hashlib.sha256(destination.read_bytes()).hexdigest()}
    sources=sorted((p for p in args.source.iterdir() if p.suffix.lower()=='.mid' and p.stem.isdigit()),key=lambda p:int(p.stem))
    with ThreadPoolExecutor(max_workers=max(1,min(4,args.jobs))) as pool:
        tracks=list(pool.map(convert,sources))
    manifest={'soundfont_sha256':hashlib.sha256(sf.read_bytes()).hexdigest(),'sample_rate':22050,'channels':1,'codec':'vorbis q3','tracks':tracks,'fluidsynth':subprocess.check_output(['fluidsynth','--version'],text=True,stderr=subprocess.STDOUT).splitlines()[0]}
    (args.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'tracks':len(tracks),'output':str(args.output)}))

if __name__=='__main__':main()
