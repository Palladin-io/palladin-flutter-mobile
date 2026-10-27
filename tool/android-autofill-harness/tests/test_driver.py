import ast, pathlib, re, runpy, subprocess, sys, types, unittest
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
     return '<hierarchy><node package="fixture" text="Request Autofill" class="android.widget.Button" enabled="true" bounds="[20,40][100,80]"/></hierarchy>'
    if a[:2]==['shell','dumpsys']:return 'result=REJECTED'
    return ''
   with patch.object(sys,'argv',['exercise.py','--serial','emulator-5554','--mode',mode,'--expected','REJECTED']),patch.object(subprocess,'check_output',side_effect=output),patch('time.sleep'):
    runpy.run_path(str(root/'exercise.py'),run_name='__main__')
   self.assertIn(['shell','input','tap','60','60'],calls)
 def test_dropdown_is_not_biometric_prompt(self):
  self.ns['nodes']=lambda:[ET.Element('node',{'text':'Unlock Palladin to autofill','package':'com.android.systemui'})]
  with self.assertRaises(AssertionError):self.ns['authenticate']()
  self.assertEqual(self.calls,[])
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
