'use strict';
function makeFlClashScript(original, profile, engine) {
  const code = String(original || '').replace(/^\uFEFF/,'').replace(/\r\n/g,'\n');
  if (code.trim() && !/(?:function\s+main\s*\(|(?:const|let|var)\s+main\s*=)/.test(code))
    throw Error('原FlClash脚本中找不到main函数，请核对文件；不要导入OpenClash的.sh文件');
  if (code.includes('BEGIN CLASH ROUTING ASSISTANT'))
    throw Error('这是本工具已生成的脚本。请导入原始脚本备份和profile.json重新生成，避免重复包装');
  const previous = code.trim() ? '  const originalMain = (input) => {\n'+code+'\n    return main(input, profileName);\n  };\n  const source = originalMain(config);\n' : '  const source = config;\n';
  return '// BEGIN CLASH ROUTING ASSISTANT v0.2.0\n// Mihomo JavaScript extension; keep your subscription, select this script in that profile.\nconst main = (config, profileName) => {\n'+previous+
    engine.split('/* MODULE_EXPORT */')[0]+'\n  return applyRoutingProfile(source, '+JSON.stringify(profile,null,2)+');\n};\n// END CLASH ROUTING ASSISTANT\n';
}
function mergeOpenClashHook(source,p,ruby) {
  if (!source.trim()) throw Error('OpenClash需要先导入原覆写文件，以保留已有内容');
  let s=source.replace(/^\uFEFF/,'').replace(/\r\n/g,'\n');
  if (!/^#!.*\bsh\b/.test(s)||!/^\s*CONFIG_FILE=/m.test(s)) throw Error('请选择OpenClash下载的openclash_custom_overwrite.sh');
  const starts=(s.match(/^# BEGIN OPENCLASH OPTIMIZER$/gm)||[]).length,ends=(s.match(/^# END OPENCLASH OPTIMIZER$/gm)||[]).length;
  if(starts!==ends||starts>1)throw Error('原管理段不完整，请先恢复原文件');
  s=s.replace(/\n# BEGIN OPENCLASH OPTIMIZER\n[\s\S]*?\n# END OPENCLASH OPTIMIZER\n/g,'');
  if(!/\nexit 0\s*$/.test(s))throw Error('原脚本末尾应为exit 0，请先核对');
  const block=`
# BEGIN OPENCLASH OPTIMIZER
ocopt_work=$(mktemp -d /tmp/openclash-optimizer.XXXXXX) || exit 1
chmod 700 "$ocopt_work"
cat > "$ocopt_work/profile.json" <<'OCOPT_PROFILE'
${JSON.stringify(p,null,2)}
OCOPT_PROFILE
ruby -ryaml -rYAML -I /usr/share/openclash -E UTF-8 - "$CONFIG_FILE" "$ocopt_work/profile.json" <<'OCOPT_RUBY'
${ruby}
OCOPT_RUBY
ocopt_status=$?
rm -f "$ocopt_work/profile.json"
rmdir "$ocopt_work"
[ "$ocopt_status" -eq 0 ] || exit 1
# END OPENCLASH OPTIMIZER
`;
  return s.replace(/\nexit 0\s*$/,block+'\nexit 0\n');
}
if(typeof module!=='undefined')module.exports={makeFlClashScript,mergeOpenClashHook};
