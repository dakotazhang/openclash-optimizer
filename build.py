"""Build a self-contained offline UI. No router credentials or private config."""
from pathlib import Path
import json

base = Path(__file__).resolve().parent
html = (base/'ui.template.html').read_text(encoding='utf8')
for token, value in [('__RUBY__', (base/'optimizer.rb').read_text(encoding='utf8')), ('__PROFILE__', json.loads((base/'profile.json').read_text(encoding='utf8')))]:
    html = html.replace(token, json.dumps(value, ensure_ascii=False).replace('</', '<\\/'))
(base/'index.html').write_text(html, encoding='utf8', newline='\n')
print('Built index.html (self-contained, offline)')
