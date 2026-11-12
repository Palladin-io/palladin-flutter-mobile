#!/usr/bin/env python3
"""Disposable emulator: real OS two-step virtual-field auth and result application."""
import subprocess,time,xml.etree.ElementTree as ET,re
from pathlib import Path
import argparse
import atexit
parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--application-context-manager', action='store_true')
args = parser.parse_args()
if not args.serial.startswith('emulator-'): parser.error('Disposable emulator required')
adb='adb'; serial=args.serial
def run(*a): return subprocess.check_output([adb,'-s',serial,*a],text=True, timeout=30).strip()
for _ in range(180):
 try:
  if run('shell','getprop','sys.boot_completed')=='1':break
 except subprocess.CalledProcessError:
  pass
 time.sleep(.5)
else: raise RuntimeError('Emulator did not finish booting')
base=Path(__file__).resolve().parent
p='io.palladin.autofill.harness.provider';f='io.palladin.autofill.harness.form'
for m in ['provider','form']:run('install','-r',str(base/m/'build/outputs/apk/debug'/f'{m}-debug.apk'))
prior_service = run('shell','settings','get','secure','autofill_service')
def restore_service():
 if prior_service == 'null': run('shell','settings','delete','secure','autofill_service')
 else: run('shell','settings','put','secure','autofill_service',prior_service)
atexit.register(restore_service)
def tap(text):
 for _ in range(8):
  run('shell','uiautomator','dump','--windows','/sdcard/probe.xml')
  root=ET.fromstring(run('shell','cat','/sdcard/probe.xml'))
  for n in root.iter('node'):
   if n.get('text','').lower()==text.lower():
    x,y,X,Y=map(int,re.findall(r'\d+',n.get('bounds')));run('shell','input','tap',str((x+X)//2),str((y+Y)//2));return
  time.sleep(.3)
 raise Exception('synthetic button missing: '+text)
for trampoline in [False,True]:
 run('logcat','-c')
 for pkg in [p,f]:run('shell','am','force-stop',pkg)
 run('shell','am','start','-W','-n',p+'/io.palladin.mobile.ReturnPickerProbe')
 run('shell','settings','delete','secure','autofill_service')
 run('shell','settings','put','secure','autofill_service',p+'/io.palladin.mobile.VirtualSessionProbeService')
 time.sleep(1)
 if trampoline:run('shell','run-as',p,'touch','files/virtual-session-trampoline')
 else:run('shell','run-as',p,'rm','-f','files/virtual-session-trampoline')
 run('shell','am','start','-W','-n',f+'/io.palladin.autofill.form.VirtualSessionProbe','--ez','applicationContextManager',str(args.application_context_manager).lower())
 time.sleep(1)
 tap('Next password step');time.sleep(1)
 manager=run('shell','run-as',f,'cat','files/virtual-manager')
 print(manager)
 assert manager == 'sameManager='+str(not args.application_context_manager).lower(), 'Wrong manager context'
 print('trampoline',trampoline,run('shell','run-as',p,'cat','files/virtual-session-request'))
 tap('Synthetic unlock')
 time.sleep(8)
 lifecycle=run('shell','run-as',f,'cat','files/virtual-lifecycle')
 print('awaiting_auth',lifecycle)
 assert ('stopped=true' in lifecycle) == trampoline, 'Requester visibility did not match direct/opaque-task scenario'
 tap('Select synthetic credential')
 time.sleep(.7)
 result=run('shell','run-as',f,'cat','files/virtual-fill')
 print(result)
 if args.application_context_manager:
  assert result == 'pending', 'Invalid requester context unexpectedly received a fill'
  logs=run('logcat','-d','-s','AutofillManager')
  assert 'sessionId=2147483647 not active' in logs, 'Missing expected inactive-client result rejection'
  dump=run('shell','dumpsys','autofill')
  blocks=re.split(r'(?m)^    #\d+\s*$',dump)[1:]
  active=any('mComponentName: ComponentInfo{'+f+'/io.palladin.autofill.form.VirtualSessionProbe}' in block and
             re.search(r'(?m)^\s*state:\s*STATE_ACTIVE\s*$',block) for block in blocks)
  assert active, 'Expected server session to survive the inactive-client rejection'
  print('client_inactive_no_session=true server_session_active=true')
 else:
  assert result == 'verified=true;count=1', 'OS did not apply exactly the current password field'
 assert run('shell','run-as',p,'cat','files/virtual-session-request') == 'contexts=2;username=0;password=1', 'Not a two-step current-password response' 
