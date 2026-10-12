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
  "dns_enabled": true,
  "groups": [
    {
      "name": "OC · U2网页",
      "default": "PROXY",
      "match": "exact",
      "dns": "foreign",
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
  "dns_exceptions": {
    "chdbits.co": "foreign"
  }
}
OCOPT_PROFILE
ruby -ryaml -rYAML -I /usr/share/openclash -E UTF-8 - "$CONFIG_FILE" "$ocopt_work/profile.json" <<'OCOPT_RUBY'
# frozen_string_literal: true
require 'yaml'

module OpenClashOptimizer
  MARKER = 'x-openclash-optimizer'.freeze
  def self.domain(value)
    s = value.to_s.strip.downcase
    raise '请填写纯域名，不能含路径、端口或通配符' unless s.match?(/\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/) && s.include?('.') && !s.include?('..') && s.split('.').all? { |x| x.size <= 63 && !x.start_with?('-') && !x.end_with?('-') }
    s
  end

  def self.apply(v, profile)
    raise '配置版本应为1' unless profile['version'] == 1
    specs = profile.fetch('groups')
    raise '至少添加一个策略组' unless specs.is_a?(Array) && !specs.empty?
    names = specs.map { |s| s.fetch('name') }
    raise '策略组名称不能重复' unless names.uniq.size == names.size
    names.each { |n| raise '组名不能为空或含逗号、换行、#' unless n.is_a?(String) && !n.strip.empty? && !n.match?(/[,\r\n#]/) && !%w[DIRECT REJECT GLOBAL].include?(n) }
    old = v.delete(MARKER) || {}
    raise '未知管理标记' unless old.empty? || old['version'] == 1
    original_groups = v['proxy-groups'] ||= []
    original_groups.reject! { |g| Array(old['groups']).include?(g['name']) }
    raise '与现有组同名，请改名，避免覆盖现有设置' if original_groups.any? { |g| names.include?(g['name']) }
    v['rules'] = Array(v['rules']).reject { |r| Array(old['rules']).include?(r) }
    dns = v['dns'] ||= {}
    (old['dns_previous'] || {}).each { |k, previous| previous.nil? ? dns.delete(k) : dns[k] = previous }
    policy = dns['nameserver-policy'] ||= {}
    (old['policy_previous'] || {}).each { |k, previous| previous.nil? ? policy.delete(k) : policy[k] = previous }
    base_name = profile.fetch('proxy_group', 'AUTO')
    base = if base_name == 'AUTO'
             original_groups.find { |g| g['name'].to_s.include?('TAGSS') } || original_groups.find { |g| g['type'] == 'select' }
           else
             original_groups.find { |g| g['name'] == base_name }
           end
    raise '找不到主代理组，请在工具中填写现有组名' unless base
    nodes = Array(v['proxies']).map { |p| p['name'] }.compact
    raise '主代理组无可用出口' if Array(base['proxies']).empty? && Array(base['use']).empty?
    domestic = ['https://dns.alidns.com/dns-query', 'https://doh.pub/dns-query']
    foreign = ['https://1.1.1.1/dns-query#' + base['name'], 'https://8.8.8.8/dns-query#' + base['name']]
    generated = []; previous = {}; occupied = {}
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
      Array(spec.fetch('domains')).each do |value|
        host = domain(value); key = [match, host]
        raise "域名重复分配：#{host}" if occupied[key]
        occupied[key] = true
        generated << "#{match == 'exact' ? 'DOMAIN' : 'DOMAIN-SUFFIX'},#{host},#{spec['name']}"
        next if resolver == 'inherit' || !profile.fetch('dns_enabled', true)
        pk = match == 'exact' ? host : '+.' + host
        previous[pk] = policy[pk]
        policy[pk] = resolver == 'domestic' ? domestic : foreign
      end
    end
    Array(profile['direct_domains']).each { |d| generated.unshift("DOMAIN,#{domain(d)},DIRECT") }
    dns_previous = {}
    if profile.fetch('dns_enabled', true)
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
      policy[pk] = kind == 'foreign' ? foreign : domestic if profile.fetch('dns_enabled', true)
    end
    v['rules'] = generated.uniq + v['rules']
    v[MARKER] = {'version'=>1, 'groups'=>names, 'rules'=>generated.uniq, 'policy_previous'=>previous, 'dns_previous'=>dns_previous}
    v
  end

  def self.run(path, profile_path)
    profile = YAML.load_file(profile_path)
    v = apply(YAML.load_file(path), profile)
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
