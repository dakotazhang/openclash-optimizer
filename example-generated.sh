#!/bin/sh
. /usr/share/openclash/ruby.sh
. /usr/share/openclash/log.sh
. /lib/functions.sh
CONFIG_FILE="$1"
# Tutorial fixture only. Import your own router's original file for real use.
# Existing custom configuration stays above the generated block.
# BEGIN OPENCLASH OPTIMIZER
ocopt_work=$(mktemp -d /tmp/openclash-optimizer.XXXXXX) || exit 1
chmod 700 "$ocopt_work"
cat > "$ocopt_work/profile.json" <<'OCOPT_PROFILE'
{
  "version": 1,
  "proxy_group": "AUTO",
  "dns_enabled": false,
  "dns_scope": "scoped",
  "groups": [
    {
      "name": "OC · U2网页",
      "default": "DIRECT",
      "match": "exact",
      "dns": "inherit",
      "domains": [
        "u2.dmhy.org"
      ]
    },
    {
      "name": "OC · PT站点",
      "default": "DIRECT",
      "match": "suffix",
      "dns": "domestic",
      "domains": [
        "m-team.cc",
        "m-team.io",
        "hdsky.me",
        "chdbits.co",
        "totheglory.im",
        "ourbits.club"
      ]
    },
    {
      "name": "OC · 哔哩哔哩",
      "default": "DIRECT",
      "match": "suffix",
      "dns": "domestic",
      "domains": [
        "bilibili.com",
        "bilivideo.com",
        "hdslb.com",
        "b23.tv"
      ]
    },
    {
      "name": "OC · 巴哈姆特",
      "default": "PROXY",
      "match": "suffix",
      "dns": "foreign",
      "domains": [
        "gamer.com.tw",
        "bahamut.com.tw"
      ]
    },
    {
      "name": "OC · HBO",
      "default": "PROXY",
      "match": "suffix",
      "dns": "foreign",
      "domains": [
        "hbo.com",
        "hbomax.com",
        "max.com"
      ]
    }
  ],
  "direct_domains": [
    "tracker.m-team.cc"
  ],
  "dns_exceptions": {}
}
OCOPT_PROFILE
ruby -ryaml -rYAML -I /usr/share/openclash -E UTF-8 - "$CONFIG_FILE" "$ocopt_work/profile.json" <<'OCOPT_RUBY'
# frozen_string_literal: true
require 'yaml'

module OpenClashOptimizer
  MARKER = 'x-openclash-optimizer'.freeze
  def self.domain(value)
    s = value.to_s.strip.downcase
    raise '请填写纯域名，不能含路径、端口或通配符' unless s.size <= 253 && s.match?(/\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/) && s.include?('.') && !s.include?('..') && s.split('.').all? { |x| x.size <= 63 && !x.start_with?('-') && !x.end_with?('-') }
    s
  end

  def self.apply(v, profile)
    raise '配置版本应为1' unless profile['version'] == 1
    specs = profile.fetch('groups')
    raise '至少添加一个策略组' unless specs.is_a?(Array) && !specs.empty?
    names = specs.map { |s| s.fetch('name') }
    raise '策略组名称不能重复' unless names.uniq.size == names.size
    names.each { |n| raise '组名不能为空或含逗号、换行、#、&' unless n.is_a?(String) && !n.strip.empty? && !n.match?(/[,\r\n#&]/) && !%w[DIRECT REJECT GLOBAL].include?(n) }
    old = v.delete(MARKER) || {}
    raise '未知管理标记' unless old.empty? || old['version'] == 1
    original_groups = v['proxy-groups'] ||= []
    original_groups.reject! { |g| Array(old['groups']).include?(g['name']) }
    raise '与现有组同名，请改名，避免覆盖现有设置' if original_groups.any? { |g| names.include?(g['name']) }
    v['rules'] = Array(v['rules']).reject { |r| Array(old['rules']).include?(r) }
    dns = v['dns'] || {}
    (old['dns_previous'] || {}).each { |k, previous| previous.nil? ? dns.delete(k) : dns[k] = previous }
    policy = dns['nameserver-policy'] || {}
    (old['policy_previous'] || {}).each { |k, previous| previous.nil? ? policy.delete(k) : policy[k] = previous }
    dns.delete('nameserver-policy') if old['policy_absent'] && policy.empty?
    v.delete('dns') if old['dns_absent'] && dns.empty?
    dns_absent = !v.key?('dns')
    policy_absent = !dns.key?('nameserver-policy')
    base_name = profile.fetch('proxy_group', 'AUTO')
    base = if base_name == 'AUTO'
             original_groups.find { |g| g['type'] == 'select' && g['name'].to_s.include?('TAGSS') } || original_groups.find { |g| g['type'] == 'select' }
           else
             original_groups.find { |g| g['name'] == base_name }
           end
    raise '找不到主代理组，请在工具中填写现有组名' unless base
    nodes = Array(v['proxies']).map { |p| p['name'] }.compact
    raise '分组与原节点同名' if nodes.any? { |n| names.include?(n) }
    raise '主代理组无可用出口' if Array(base['proxies']).empty? && Array(base['use']).empty?
    domestic = ['https://dns.alidns.com/dns-query', 'https://doh.pub/dns-query']
    foreign = ['https://1.1.1.1/dns-query#' + base['name'], 'https://8.8.8.8/dns-query#' + base['name']]
    generated = []; previous = {}; occupied = {}; used_foreign = false
    scope = profile.fetch('dns_scope', 'global')
    raise '未知DNS范围' unless %w[scoped global].include?(scope)
    specs.each do |spec|
      default = spec.fetch('default', 'DIRECT')
      raise '默认出口只能选 DIRECT 或 PROXY' unless %w[DIRECT PROXY].include?(default)
      choices = default == 'DIRECT' ? ['DIRECT', base['name'], *nodes] : [base['name'], 'DIRECT', *nodes]
      g = {'name'=>spec['name'], 'type'=>'select', 'proxies'=>choices.uniq}
      g['use'] = base['use'].dup if base['use']
      original_groups << g
      match = spec.fetch('match', 'suffix')
      raise '匹配方式应为 exact 或 suffix' unless %w[exact suffix].include?(match)
      resolver = spec.fetch('dns', 'inherit')
      raise 'DNS选项无效' unless %w[inherit domestic foreign].include?(resolver)
      domains = spec.fetch('domains')
      raise '每组至少填写一个域名，domains应为数组' unless domains.is_a?(Array) && !domains.empty?
      domains.each do |value|
        host = domain(value); key = [match, host]
        raise "域名重复分配：#{host}" if occupied[key]
        occupied[key] = true
        generated << "#{match == 'exact' ? 'DOMAIN' : 'DOMAIN-SUFFIX'},#{host},#{spec['name']}"
        next if resolver == 'inherit' || !profile.fetch('dns_enabled', true)
        pk = match == 'exact' ? host : '+.' + host
        previous[pk] = policy[pk] unless previous.key?(pk)
        policy[pk] = resolver == 'domestic' ? domestic : foreign
        used_foreign ||= resolver == 'foreign'
      end
    end
    Array(profile['direct_domains']).each { |d| generated.unshift("DOMAIN,#{domain(d)},DIRECT") }
    dns_previous = {}
    if profile.fetch('dns_enabled', true) && scope == 'global'
      %w[nameserver fallback default-nameserver proxy-server-nameserver respect-rules fallback-filter].each { |k| dns_previous[k] = dns[k] }
      dns['nameserver'] = domestic
      dns['fallback'] = foreign
      dns['default-nameserver'] = ['223.5.5.5', '119.29.29.29']
      dns['proxy-server-nameserver'] = ['223.5.5.5', '119.29.29.29']
      dns['respect-rules'] = false
      dns['fallback-filter'] ||= {'geoip'=>true, 'geoip-code'=>'CN', 'ipcidr'=>['240.0.0.0/4', '0.0.0.0/32']}
    end
    (profile['dns_exceptions'] || {}).each do |host, kind|
      raise 'DNS例外只能选 domestic 或 foreign' unless %w[domestic foreign].include?(kind)
      pk = '+.' + domain(host)
      previous[pk] = policy[pk] unless previous.key?(pk)
      if profile.fetch('dns_enabled', true)
        policy[pk] = kind == 'foreign' ? foreign : domestic
        used_foreign ||= kind == 'foreign'
      else
        previous.delete(pk)
      end
    end
    if profile.fetch('dns_enabled', true) && scope == 'scoped' && !previous.empty?
      set_dns = lambda do |key, value|
        dns_previous[key] = dns[key] unless dns_previous.key?(key)
        dns[key] = value
      end
      set_dns.call('enable', true) unless dns['enable'] == true
      set_dns.call('nameserver', ['223.5.5.5', '119.29.29.29']) if Array(dns['nameserver']).empty?
      set_dns.call('default-nameserver', ['223.5.5.5', '119.29.29.29']) if Array(dns['default-nameserver']).empty?
      set_dns.call('proxy-server-nameserver', ['223.5.5.5', '119.29.29.29']) if used_foreign && Array(dns['proxy-server-nameserver']).empty?
      if !Array(dns['direct-nameserver']).empty? && dns['direct-nameserver-follow-policy'] != true
        set_dns.call('direct-nameserver-follow-policy', true)
      end
    end
    if used_foreign && base['name'].match?(/[#&\r\n]/)
      raise '主代理组含DNS参数分隔符，请使用不含#或&的组名'
    end
    dns['nameserver-policy'] = policy unless previous.empty?
    v['dns'] = dns unless dns_absent && dns.empty?
    v['rules'] = generated.uniq + v['rules']
    v[MARKER] = {'version'=>1, 'groups'=>names, 'rules'=>generated.uniq, 'policy_previous'=>previous, 'dns_previous'=>dns_previous, 'dns_absent'=>dns_absent, 'policy_absent'=>policy_absent}
    v
  end

  def self.run(path, profile_path)
    profile = YAML.safe_load(File.read(profile_path), aliases: true)
    v = apply(YAML.safe_load(File.read(path), aliases: true), profile)
    tmp = path + '.optimizer.tmp'
    File.open(tmp, 'w', 0600) { |f| YAML.dump(v, f) }
    core = '/etc/openclash/core/clash_meta'
    if File.executable?(core)
      log = path + '.optimizer-check.log'
      ok = File.open(log, 'w', 0600) { |f| system(core, '-t', '-d', '/etc/openclash', '-f', tmp, out:f, err:f) }
      unless ok
        File.delete(tmp)
        raise "内核检查失败，未写入配置；本机诊断文件：#{log}"
      end
      File.delete(log)
    elsif ENV['OCOPT_TEST'] != '1'
      File.delete(tmp)
      raise '未找到 Mihomo 内核，拒绝写入；仅离线测试可设 OCOPT_TEST=1'
    end
    File.rename(tmp, path)
  end
end

OpenClashOptimizer.run(ARGV.fetch(0), ARGV.fetch(1)) if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME == '-'

OCOPT_RUBY
ocopt_status=$?
rm -f "$ocopt_work/profile.json"
rmdir "$ocopt_work"
[ "$ocopt_status" -eq 0 ] || exit 1
# END OPENCLASH OPTIMIZER

exit 0
