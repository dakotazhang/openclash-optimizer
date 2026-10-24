/* Pure Mihomo configuration transform; no network, filesystem or browser access. */
'use strict';
function applyRoutingProfile(input, profile) {
  const copy = value => JSON.parse(JSON.stringify(value));
  const own = (obj, key) => Object.prototype.hasOwnProperty.call(obj, key);
  const object = value => value && typeof value === 'object' && !Array.isArray(value);
  const domain = value => {
    const s = String(value).trim().toLowerCase();
    if (!/^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/.test(s) || s.length > 253 || !s.includes('.') || s.includes('..') || s.split('.').some(x => x.length > 63 || x.startsWith('-') || x.endsWith('-')))
      throw Error('域名格式有误，请只填主机名');
    return s;
  };
  if (!object(input) || !object(profile) || profile.version !== 1 || !Array.isArray(profile.groups) || !profile.groups.length)
    throw Error('配置格式有误：至少添加一个网站分组');
  const p = copy(profile), v = copy(input), marker = 'x-openclash-optimizer';
  const names = p.groups.map(g => g.name);
  if (new Set(names).size !== names.length || names.some(n => typeof n !== 'string' || !n.trim() || /[,\r\n#&]/.test(n) || ['DIRECT','REJECT','GLOBAL'].includes(n)))
    throw Error('分组名称重复或含不支持的字符');
  const old = v[marker] || {};
  if (Object.keys(old).length && old.version !== 1) throw Error('未知旧版管理标记，请保留原配置核对');
  delete v[marker];
  const oldNames = new Set(old.groups || []), oldRules = new Set(old.rules || []);
  v['proxy-groups'] = (v['proxy-groups'] || []).filter(g => !oldNames.has(g.name));
  v.rules = (v.rules || []).filter(r => !oldRules.has(r));
  if (Object.keys(old).length && v.dns) {
    for (const [k, val] of Object.entries(old.dns_previous || {})) val === null ? delete v.dns[k] : v.dns[k] = val;
    const policy = v.dns['nameserver-policy'];
    if (policy) {
      for (const [k, val] of Object.entries(old.policy_previous || {})) val === null ? delete policy[k] : policy[k] = val;
      if (old.policy_absent && !Object.keys(policy).length) delete v.dns['nameserver-policy'];
    }
    if (old.dns_absent && !Object.keys(v.dns).length) delete v.dns;
  }
  const nodes = (v.proxies || []).map(n => n.name).filter(Boolean);
  if (v['proxy-groups'].some(g => names.includes(g.name)) || nodes.some(n => names.includes(n)))
    throw Error('新分组与原组或节点同名，请改名后生成');
  const baseName = p.proxy_group || 'AUTO';
  const base = baseName === 'AUTO'
    ? v['proxy-groups'].find(g => g.type === 'select' && String(g.name).includes('TAGSS')) || v['proxy-groups'].find(g => g.type === 'select')
    : v['proxy-groups'].find(g => g.name === baseName);
  if (!base || !(Array.isArray(base.proxies) && base.proxies.length || Array.isArray(base.use) && base.use.length))
    throw Error('找不到可用主代理组，请填写订阅里已有的组名');
  const dnsAbsent = !own(v,'dns'), policyAbsent = !v.dns || !own(v.dns,'nameserver-policy');
  const dnsPrevious = {}, policyPrevious = {}, generated = [], occupied = new Set();
  const domestic = ['https://dns.alidns.com/dns-query','https://doh.pub/dns-query'];
  const foreign = ['https://1.1.1.1/dns-query#'+base.name,'https://8.8.8.8/dns-query#'+base.name];
  const dnsEnabled = p.dns_enabled !== false, scope = p.dns_scope || 'global';
  if (!['scoped','global'].includes(scope)) throw Error('未知DNS范围');
  const getDns = () => {
    if (v.dns !== undefined && !object(v.dns)) throw Error('原dns字段不是对象');
    return v.dns ||= {};
  };
  const setDns = (k,val) => {
    const d = getDns();
    if (!own(dnsPrevious,k)) dnsPrevious[k] = own(d,k) ? copy(d[k]) : null;
    d[k] = val;
  };
  let usedForeign = false, usedPolicy = false;
  const setPolicy = (key,kind) => {
    if (!dnsEnabled || kind === 'inherit') return;
    const d = getDns();
    if (d['nameserver-policy'] !== undefined && !object(d['nameserver-policy'])) throw Error('原DNS域名策略不是对象');
    const policy = d['nameserver-policy'] ||= {};
    if (!own(policyPrevious,key)) policyPrevious[key] = own(policy,key) ? copy(policy[key]) : null;
    if (kind === 'foreign' && /[#&\r\n]/.test(base.name)) throw Error('主代理组含DNS参数分隔符，请使用不含#或&的组名');
    policy[key] = kind === 'foreign' ? foreign : domestic;
    usedForeign ||= kind === 'foreign'; usedPolicy = true;
  };
  for (const spec of p.groups) {
    const match = spec.match || 'suffix', resolver = spec.dns || 'inherit', exit = spec.default || 'DIRECT';
    if (!['suffix','exact'].includes(match) || !['inherit','domestic','foreign'].includes(resolver) || !['DIRECT','PROXY'].includes(exit) || !Array.isArray(spec.domains) || !spec.domains.length)
      throw Error('网站分组的出口、范围或DNS选项有误');
    const group = {name:spec.name,type:'select',proxies:[...new Set(exit === 'DIRECT' ? ['DIRECT',base.name,...nodes] : [base.name,'DIRECT',...nodes])]};
    if (base.use) group.use = copy(base.use);
    v['proxy-groups'].push(group);
    for (const value of spec.domains) {
      const host = domain(value), key = match+' '+host;
      if (occupied.has(key)) throw Error('同一域名重复分配：'+host);
      occupied.add(key);
      generated.push((match === 'exact' ? 'DOMAIN' : 'DOMAIN-SUFFIX')+','+host+','+spec.name);
      setPolicy(match === 'exact' ? host : '+.'+host,resolver);
    }
  }
  for (const d of p.direct_domains || []) generated.unshift('DOMAIN,'+domain(d)+',DIRECT');
  for (const [host,kind] of Object.entries(p.dns_exceptions || {})) {
    if (!['domestic','foreign'].includes(kind)) throw Error('DNS例外选项有误');
    setPolicy('+.'+domain(host),kind);
  }
  if (dnsEnabled && scope === 'global') {
    setDns('nameserver',domestic);setDns('fallback',foreign);
    setDns('default-nameserver',['223.5.5.5','119.29.29.29']);
    setDns('proxy-server-nameserver',['223.5.5.5','119.29.29.29']);
    setDns('respect-rules',false);
    if (!getDns()['fallback-filter']) setDns('fallback-filter',{'geoip':true,'geoip-code':'CN','ipcidr':['240.0.0.0/4','0.0.0.0/32']});
    else dnsPrevious['fallback-filter'] = copy(getDns()['fallback-filter']);
  } else if (usedPolicy) {
    if (getDns().enable !== true) setDns('enable',true);
    if (!getDns().nameserver || !getDns().nameserver.length) setDns('nameserver',['223.5.5.5','119.29.29.29']);
    if (!getDns()['default-nameserver'] || !getDns()['default-nameserver'].length) setDns('default-nameserver',['223.5.5.5','119.29.29.29']);
    if (usedForeign && (!getDns()['proxy-server-nameserver'] || !getDns()['proxy-server-nameserver'].length)) setDns('proxy-server-nameserver',['223.5.5.5','119.29.29.29']);
    if (getDns()['direct-nameserver'] && getDns()['direct-nameserver'].length && getDns()['direct-nameserver-follow-policy'] !== true) setDns('direct-nameserver-follow-policy',true);
  }
  v.rules = [...new Set(generated),...v.rules];
  v[marker] = {version:1,groups:names,rules:[...new Set(generated)],policy_previous:policyPrevious,dns_previous:dnsPrevious,dns_absent:dnsAbsent,policy_absent:policyAbsent};
  return v;
}
/* MODULE_EXPORT */
if (typeof module !== 'undefined') module.exports = {applyRoutingProfile};
