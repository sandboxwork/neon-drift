#!/usr/bin/env python3
"""Build a separate iOS simulator fixture and capture actual native app screens.

Does not sign, upload, or modify the production project. Requires macOS/Xcode.
"""
import json
from pathlib import Path
import shutil
import subprocess
import time
import export_ios

ROOT = export_ios.ROOT
BUILD = ROOT / 'build'
BUNDLE = 'com.jkchat.neondrift.capture'

def run(args, **kwargs):
    print('+', ' '.join(map(str,args)), flush=True)
    return subprocess.run(list(map(str,args)), check=True, **kwargs)

def read(args):
    return subprocess.check_output(list(map(str,args)), text=True).strip()

def main():
    stage = BUILD / 'capture-source'
    output = BUILD / 'capture-xcode'
    stage.mkdir(parents=True)
    output.mkdir(parents=True)
    export_ios.stage_source(stage)
    shutil.copy2(ROOT/'tools/capture_ios_screens.gd', stage/'capture_driver.gd')
    (stage/'capture.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://capture_driver.gd" id="1"]\n[node name="StoreCapture" type="Node"]\nscript = ExtResource("1")\n')
    project = stage/'project.godot'
    project.write_text(project.read_text().replace('run/main_scene="res://main.tscn"','run/main_scene="res://capture.tscn"'))
    template = ROOT/'.cache/godot/templates/ios.zip'
    export_ios.configure_preset(stage/'export_presets.cfg', {
        'application/app_store_team_id': '0000000000',
        'application/bundle_identifier': BUNDLE,
        'application/export_project_only': True,
        'custom_template/debug': str(template), 'custom_template/release': str(template),
    })
    godot=ROOT/'.cache/godot/godot'
    run([godot,'--headless','--editor','--path',stage,'--import','--quit'])
    run([godot,'--headless','--path',stage,'--export-release','iOS',output/'neondrift.ipa'])
    derived=BUILD/'SimulatorDerivedData'
    run(['xcodebuild','-project',output/'neondrift.xcodeproj','-scheme','neondrift','-configuration','Release','-sdk','iphonesimulator','-destination','generic/platform=iOS Simulator','-derivedDataPath',derived,'ARCHS=x86_64','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=NO','build'])
    app=derived/'Build/Products/Release-iphonesimulator/neondrift.app'
    devices=json.loads(read(['xcrun','simctl','list','devices','available','--json']))['devices']
    pool=[d for runtime, ds in devices.items() if 'iOS' in runtime for d in ds]
    selected=[]
    for label, match in [('iphone',lambda n: 'iPhone' in n and 'Pro Max' in n),('ipad',lambda n: 'iPad Pro' in n and '13-inch' in n)]:
        choices=[d for d in pool if match(d['name'])]
        if not choices: raise RuntimeError('No compatible '+label+' simulator: '+str([d['name'] for d in pool]))
        selected.append((label,choices[-1]))
    for label, device in selected:
        udid=device['udid']
        run(['xcrun','simctl','shutdown','all'])
        run(['xcrun','simctl','boot',udid])
        run(['xcrun','simctl','bootstatus',udid,'-b'])
        run(['xcrun','simctl','status_bar',udid,'override','--time','9:41','--dataNetwork','wifi','--wifiMode','active','--wifiBars','3','--batteryState','charged','--batteryLevel','100'])
        run(['xcrun','simctl','install',udid,app])
        run(['xcrun','simctl','launch',udid,BUNDLE])
        container=Path(read(['xcrun','simctl','get_app_container',udid,BUNDLE,'data']))
        destination=BUILD/'app-store-screenshots'/label
        destination.mkdir(parents=True,exist_ok=True)
        deadline=time.monotonic()+240
        captures=[]
        while time.monotonic()<deadline:
            completed=list(container.rglob('store-capture/complete.json'))
            if completed:
                evidence=json.loads(completed[0].read_text())
                evidence.update({'device':device['name'],'captures':captures})
                (destination/'capture-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
                break
            markers=list(container.rglob('store-capture/ready.json'))
            for marker in markers:
                state=json.loads(marker.read_text())
                name=state['name']
                if any(c['name']==name for c in captures): continue
                time.sleep(0.3)
                run(['xcrun','simctl','io',udid,'screenshot','--type=png',destination/(name+'.png')])
                captures.append(state)
                marker.unlink()
                (marker.parent/'ack').write_text('captured\n')
            time.sleep(0.3)
        else: raise RuntimeError('Simulator capture timed out: '+device['name'])
        if len(captures)!=6: raise RuntimeError('Incomplete screenshots')
        run(['xcrun','simctl','shutdown',udid])

if __name__=='__main__': main()
