"""Narrow system-dialog recognition shared by disposable Android harnesses."""
import re


def launcher_anr_close(nodes):
    titles = [node for node in nodes if "isn't responding" in node.get('text', '')]
    if (len(titles) != 1 or titles[0].get('text') != "Pixel Launcher isn't responding"
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
    return control
