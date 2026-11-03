"""Narrow system-dialog recognition shared by disposable Android harnesses."""
import re


def launcher_anr_close(nodes):
    return _system_anr_close(nodes, "Pixel Launcher isn't responding")


def sdk_setup_anr_close(nodes):
    return _system_anr_close(nodes, "com.google.android.googlesdksetup isn't responding")


def _system_anr_close(nodes, title):
    titles = [node for node in nodes if "isn't responding" in node.get('text', '')]
    if (len(titles) != 1 or titles[0].get('text') != title
            or titles[0].get('package') != 'android'):
        return None
    controls = [node for node in nodes if node.get('text') == 'Close app']
    if len(controls) != 1:
        return None
    control = controls[0]
    if (control.get('package') != 'android' or control.get('class') != 'android.widget.Button'
            or control.get('enabled') != 'true'
            or not re.fullmatch(r'\[\d+,\d+\]\[\d+,\d+\]', control.get('bounds', ''))):
        return None
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', control.get('bounds')))
    if x2 <= x1 or y2 <= y1:
        return None
    return control
