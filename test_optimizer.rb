require 'minitest/autorun'
require_relative 'optimizer'
class OptimizerTest < Minitest::Test
  def setup
    @v = {'proxy-groups'=>[{'name'=>'Main','type'=>'select','proxies'=>['Node']}], 'proxies'=>[{'name'=>'Node','type'=>'ss'}], 'rules'=>['MATCH,Main'], 'dns'=>{'listen'=>'127.0.0.1:7874','enhanced-mode'=>'redir-host','nameserver-policy'=>{'+.unrelated.test'=>['9.9.9.9']}}}
    @p = {'version'=>1,'proxy_group'=>'Main','groups'=>[{'name'=>'OC · PT','default'=>'DIRECT','domains'=>['sky.test'],'dns'=>'domestic'}],'dns_exceptions'=>{'sky.test'=>'foreign'}}
  end
  def apply(v=@v,p=@p); OpenClashOptimizer.apply(Marshal.load(Marshal.dump(v)),p); end
  def test_preserves_other_settings_and_rules
    r=apply; assert_equal 'MATCH,Main',r['rules'].last
    assert_equal '127.0.0.1:7874',r['dns']['listen']; assert_equal ['9.9.9.9'],r['dns']['nameserver-policy']['+.unrelated.test']
    assert_equal ['DIRECT','Main','Node'],r['proxy-groups'].last['proxies']
    assert_equal @v['proxies'],r['proxies']
  end
  def test_idempotent; r=apply; assert_equal r,apply(r); end
  def test_foreign_exception; assert apply['dns']['nameserver-policy']['+.sky.test'].all?{|x| x.end_with?('#Main')}; end
  def test_removed_domain_restores_previous_policy
    @v['dns']['nameserver-policy']['+.sky.test']=['8.8.4.4']; r=apply
    p=Marshal.load(Marshal.dump(@p));p['groups'][0]['domains']=['new.test'];p['dns_exceptions']={}; n=apply(r,p)
    assert_equal ['8.8.4.4'],n['dns']['nameserver-policy']['+.sky.test']; refute n['rules'].any?{|x|x.include?('sky.test')}
  end
  def test_reject_group_collision; @p['groups'][0]['name']='Main'; assert_raises(RuntimeError){apply}; end
  def test_reject_invalid_domain; @p['groups'][0]['domains']=['https://sky.test/path']; assert_raises(RuntimeError){apply}; end
  def test_missing_proxy; @p['proxy_group']='Nope'; assert_raises(RuntimeError){apply}; end
  def test_auto_without_tagss; @p['proxy_group']='AUTO'; assert_equal 'Main',apply['proxy-groups'].last['proxies'][1]; end
  def test_provider_only
    @v['proxy-groups'][0].delete('proxies');@v['proxy-groups'][0]['use']=['airport']; assert_equal ['airport'],apply['proxy-groups'].last['use']
  end
  def test_dns_disabled
    @p['dns_enabled']=false; @p['dns_exceptions']={}; assert_equal @v['dns'],apply['dns']
  end
  def test_disable_dns_restores_original
    r=apply; @p['dns_enabled']=false; @p['dns_exceptions']={}; assert_equal @v['dns'],apply(r)['dns']
  end
end
