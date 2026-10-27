import ast, json, os, pathlib, re, runpy, subprocess, sys, tempfile, types, unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
root = pathlib.Path(__file__).resolve().parents[1]
class DriverChecks(unittest.TestCase):
 def setUp(self):
  tree=ast.parse((root/'exercise.py').read_text())
  self.calls=[]
  self.ns={'args':types.SimpleNamespace(mode='web-login'),'re':re,'time':types.SimpleNamespace(sleep=lambda _:None),'form':'fixture','command':lambda *a:self.calls.append(a)}
  exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)],type_ignores=[]),'driver','exec'),self.ns)
  self.ns['command']=lambda *a:self.calls.append(a)
 def test_focus_ignores_foreign_and_disabled_fields(self):
  nodes=[ET.Element('node',{'package':'system','class':'android.widget.EditText','bounds':'[0,0][20,20]'}),ET.Element('node',{'package':'fixture','class':'android.widget.EditText','enabled':'false','bounds':'[0,0][20,20]'}),ET.Element('node',{'package':'fixture','class':'android.widget.EditText','enabled':'true','bounds':'[20,40][100,80]'})]
  self.ns['nodes']=lambda:nodes
  self.ns['focus_field']()
  self.assertEqual(self.calls,[('shell','input','tap','60','60')])
 def test_missing_accessible_field_fails_without_coordinate_fallback(self):
  self.ns['nodes']=lambda:[]
  with self.assertRaises(AssertionError):self.ns['focus_field']()
  self.assertEqual(self.calls,[])
 def test_dropdown_uses_observed_bounds(self):
  self.ns['nodes']=lambda:[ET.Element('node',{'text':'Unlock Palladin to autofill','bounds':'[10,200][310,280]','enabled':'true'})]
  self.assertTrue(self.ns['tap_text']('Unlock Palladin to autofill'))
  self.assertEqual(self.calls,[('shell','input','tap','160','240')])
 def test_negative_fixtures_without_edittext_request_autofill(self):
  for mode in ('native-hidden','native-container','web-disabled'):
   calls=[]
   def output(cmd,**kwargs):
    a=cmd[3:];calls.append(a)
    if a[:2]==['shell','cat']:
     return '<hierarchy><node package="fixture" text="Request Autofill" class="android.widget.Button" enabled="true" bounds="[20,40][100,80]"/><node package="io.palladin.autofill.harness.form" text="Verify fill" enabled="true" bounds="[20,90][100,130]"/><node package="io.palladin.autofill.harness.form" text="requestIssued=true unavailable=true uiShown=false enabled=true"/><node package="io.palladin.autofill.harness.form" text="fieldsUnchanged=true"/></hierarchy>'
    if a[:2]==['shell','dumpsys']:return 'result=REJECTED'
    if a[:3]==['shell','settings','get']:return 'io.palladin.autofill.harness.provider/io.palladin.mobile.autofill.PalladinAutofillService'
    return ''
   with patch.object(sys,'argv',['exercise.py','--serial','emulator-5554','--mode',mode,'--expected','REJECTED']),patch.object(subprocess,'check_output',side_effect=output),patch('time.sleep'):
    runpy.run_path(str(root/'exercise.py'),run_name='__main__')
   self.assertIn(['shell','input','tap','60','60'],calls)
 def test_dropdown_is_not_biometric_prompt(self):
  self.ns['nodes']=lambda:[ET.Element('node',{'text':'Unlock Palladin to autofill','package':'com.android.systemui'})]
  with self.assertRaises(AssertionError):self.ns['authenticate']()
  self.assertEqual(self.calls,[])
 def test_unlock_dropdown_is_selected_from_interactive_windows(self):
  self.ns['ET']=ET
  all_windows=False
  def command(*parts):
   nonlocal all_windows
   self.calls.append(parts)
   if parts[:2]==('shell','uiautomator'):
    all_windows='--windows' in parts
    return 'UI hierarchy dumped'
   if parts[:2]==('shell','cat'):
    if not all_windows:return '<hierarchy><node text="Synthetic username"/></hierarchy>'
    return '<displays><display><window><node package="android" text="Unlock Palladin to autofill" bounds="[10,200][310,280]" enabled="true"/></window></display></displays>'
   return ''
  self.ns['command']=command
  self.assertTrue(self.ns['tap_text']('Unlock Palladin to autofill'))
  self.assertIn(('shell','input','tap','160','240'),self.calls)
 def test_failure_evidence_omits_node_text_and_values(self):
  with tempfile.TemporaryDirectory() as directory:
   self.ns.update({'os':os,'Path':pathlib.Path,'json':json,'subprocess':subprocess,'adb':'adb','__file__':str(pathlib.Path(directory)/'exercise.py'),'args':types.SimpleNamespace(mode='native-login',inspect_response=False,serial='emulator-5554')})
   self.ns['service']='synthetic/service'
   self.ns['command']=lambda *parts:'domains=ZERO\norigin=VERIFIED\nresult=RESPONSE_OFFERED\nsecret=must-not-be-recorded\n'
   self.ns['nodes']=lambda:[ET.Element('node',{'text':'arbitrary-field-value','value':'arbitrary-value','package':'fixture','class':'android.widget.EditText'}),ET.Element('node',{'text':'Unlock Palladin to autofill','package':'android'})]
   with patch.dict(os.environ,{'GITHUB_ACTIONS':'true'}),patch.object(subprocess,'check_output',return_value=b'synthetic-screen'):
    self.ns['record_failure']()
   raw=(pathlib.Path(directory)/'build/exercise/native-login-handoff/nodes.json').read_text()
   self.assertNotIn('arbitrary-',raw)
   self.assertEqual(json.loads(raw)[1]['role'],'unlock-suggestion')
   request=(pathlib.Path(directory)/'build/exercise/native-login-handoff/request.json').read_text()
   self.assertEqual(json.loads(request),{'domains':'ZERO','origin':'VERIFIED','result':'RESPONSE_OFFERED'})
   self.assertNotIn('must-not-be-recorded',request)
 def test_textless_inline_chip_uses_unique_observed_suggestion_bounds(self):
  root_node=ET.fromstring('<node package="ime.test" resource-id="ime.test:id/key_pos_proactive_suggestions"><node package="ime.test" class="android.view.ViewGroup" clickable="true" focusable="true" enabled="true" bounds="[265,1051][815,1161]"/></node>')
  self.ns['nodes']=lambda:list(root_node.iter('node'))
  def command(*parts):
   self.calls.append(parts)
   return 'ime.test/.Keyboard' if parts[:3]==('shell','settings','get') else ''
  self.ns['command']=command
  self.assertTrue(self.ns['tap_text']('Unlock Palladin to autofill'))
  self.assertIn(('shell','input','tap','540','1106'),self.calls)
 def test_textless_inline_chip_rejects_ambiguous_or_unrelated_nodes(self):
  for container in ('ime.test:id/key_pos_proactive_suggestions','ime.test:id/keyboard_header_view_holder'):
   root_node=ET.fromstring(f'<node package="ime.test" resource-id="{container}"><node package="ime.test" class="android.view.ViewGroup" clickable="true" focusable="true" enabled="true" bounds="[0,10][30,40]"/><node package="ime.test" class="android.view.ViewGroup" clickable="true" focusable="true" enabled="true" bounds="[40,10][60,40]"/></node>')
   self.ns['nodes']=lambda:list(root_node.iter('node'))
   def command(*parts):
    self.calls.append(parts)
    return 'ime.test/.Keyboard'
   self.ns['command']=command
   self.assertFalse(self.ns['tap_text']('Unlock Palladin to autofill'))
  self.assertFalse(any(c[:3]==('shell','input','tap') for c in self.calls))
 def test_null_root_transition_retries_without_reading_missing_xml(self):
  for filename in ('exercise.py','prepare_ci.py'):
   with self.subTest(driver=filename):
    tree=ast.parse((root/filename).read_text())
    ns={'ET':ET,'subprocess':subprocess}
    exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)],type_ignores=[]),filename,'exec'),ns)
    calls=[]
    dumps=iter(['ERROR: null root node returned by UiTestAutomationBridge.','UI hierarchy dumped'])
    def command(*parts):
     calls.append(parts)
     if parts[:2]==('shell','uiautomator'):return next(dumps)
     if parts[:2]==('shell','cat'):return '<hierarchy><node text="Ready"/></hierarchy>'
     return ''
    ns['command']=command
    self.assertEqual(ns['nodes'](),[])
    self.assertFalse(any(c[:2]==('shell','cat') for c in calls))
    self.assertEqual(ns['nodes']()[0].get('text'),'Ready')
 def test_ui_dump_timeouts_and_other_failures_are_not_hidden(self):
  for filename in ('exercise.py','prepare_ci.py'):
   for error in (subprocess.TimeoutExpired('adb',15),subprocess.CalledProcessError(1,'adb',output='unexpected failure')):
    with self.subTest(driver=filename,error=type(error).__name__):
     tree=ast.parse((root/filename).read_text())
     ns={'ET':ET,'subprocess':subprocess}
     exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)],type_ignores=[]),filename,'exec'),ns)
     def command(*parts):
      if parts[:2]==('shell','uiautomator'):raise error
      return ''
     ns['command']=command
     with self.assertRaises(type(error)):ns['nodes']()
 def test_keyguard_is_unlocked_with_observed_synthetic_pin_keys(self):
  state={'page':-1,'digits':''}
  ticks=iter(range(0,1000,5))
  def output(cmd,**kwargs):
   a=cmd[3:]
   if a==['shell','getprop','ro.kernel.qemu']:return '1'
   if a==['shell','getprop','ro.build.version.sdk']:return '35'
   if a[:3]==['shell','locksettings','set-pin']:return "Pin set to '246813'"
   if a[:2]==['shell','cat']:
    if state['page']==-1:
     keys=[f'<node package="com.android.systemui" resource-id="com.android.systemui:id/key{i}" enabled="true" bounds="[{i*10},0][{i*10+8},8]"/>' for i in range(10)]
     return '<hierarchy><node package="com.android.systemui" resource-id="com.android.systemui:id/keyguard_pin_view"/>'+''.join(keys)+'<node package="com.android.systemui" resource-id="com.android.systemui:id/key_enter" enabled="true" bounds="[110,0][118,8]"/></hierarchy>'
    text=['I agree','Touch the sensor','Lift, then touch again','Fingerprint added'][state['page']]
    return f'<hierarchy><node package="com.android.settings" text="{text}" enabled="true" bounds="[0,20][10,30]"/></hierarchy>'
   if a[:3]==['shell','input','tap']:
    if state['page']==-1:
     x=int(a[3])
     if x==114:
      self.assertEqual(state['digits'],'246813');state['page']=0
     else:state['digits']+=str(x//10)
    elif state['page']==0:state['page']=1
   if a==['emu','finger','touch','1']:
    self.assertIn(state['page'],(1,2));state['page']+=1
   if a==['exec-out','screencap','-p']:return b'synthetic-image'
   return ''
  with patch.object(sys,'argv',['prepare_ci.py','--serial','emulator-5554']),patch.dict(os.environ,{'GITHUB_ACTIONS':'true'}),patch.object(subprocess,'check_output',side_effect=output),patch('time.sleep'),patch('time.monotonic',side_effect=lambda:next(ticks)),patch.object(pathlib.Path,'write_text'),patch.object(pathlib.Path,'write_bytes'):
   runpy.run_path(str(root/'prepare_ci.py'),run_name='__main__')
  self.assertEqual(state['page'],3)
 def test_keyguard_pin_is_not_typed_into_partial_or_foreign_keypad(self):
  tree=ast.parse((root/'prepare_ci.py').read_text())
  ns={}
  exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)],type_ignores=[]),'prepare','exec'),ns)
  taps=[]
  ns['tap']=lambda node:taps.append(node) or True
  for package in ('com.android.systemui','other.app'):
   keypad=[ET.Element('node',{'package':package,'resource-id':'com.android.systemui:id/'+key,'enabled':'true'}) for key in ('keyguard_pin_view','key2','key4','key6','key8','key1','key_enter')]
   self.assertFalse(ns['unlock_keyguard'](keypad))
  self.assertEqual(taps,[])
 def test_settings_enrollment_requires_ui_confirmation(self):
  state={'page':0,'touches':0}
  def output(cmd,**kwargs):
   a=cmd[3:]
   if a==['shell','getprop','ro.kernel.qemu']:return '1'
   if a==['shell','getprop','ro.build.version.sdk']:return '35'
   if a[:3]==['shell','locksettings','set-pin']:return "Pin set to '246813'\n"
   if a[:2]==['shell','cat']:
    pages=[('Enter your PIN','android.widget.EditText'),('I agree','android.widget.Button'),('Touch the sensor','android.widget.TextView'),('Lift, then touch again','android.widget.TextView'),('Fingerprint added','android.widget.TextView')]
    text,cls=pages[state['page']]
    return f'<hierarchy><node package="com.android.settings" text="{text}" class="{cls}" enabled="true" bounds="[20,40][100,80]"/></hierarchy>'
   if a==['shell','input','keyevent','KEYCODE_ENTER']:state['page']=1
   if a[:3]==['shell','input','tap'] and state['page']==1:state['page']=2
   if a==['emu','finger','touch','1']:
    self.assertIn(state['page'],(2,3));state['page']+=1;state['touches']+=1
   if a==['exec-out','screencap','-p']:return b'synthetic-image'
   return ''
  with patch.object(sys,'argv',['prepare_ci.py','--serial','emulator-5554']),patch.dict('os.environ',{'GITHUB_ACTIONS':'true'}),patch.object(subprocess,'check_output',side_effect=output),patch('time.sleep'),patch.object(pathlib.Path,'write_text'),patch.object(pathlib.Path,'write_bytes'):
   runpy.run_path(str(root/'prepare_ci.py'),run_name='__main__')
  self.assertEqual(state['touches'],2)
if __name__ == '__main__':
    unittest.main()
