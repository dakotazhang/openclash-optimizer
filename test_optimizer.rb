require 'minitest/autorun'
require 'tmpdir'
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
  def test_reject_empty_or_non_array_domains
    [[], 'sky.test', nil].each do |value|
      @p['groups'][0]['domains']=value
      assert_raises(RuntimeError){apply}
    end
  end
  def test_file_runner_accepts_plain_yaml_anchors
    Dir.mktmpdir do |dir|
      config_path=File.join(dir,'config.yaml');profile_path=File.join(dir,'profile.yaml')
      shared=['192.0.2.53'];@v['dns']['nameserver']=shared;@v['dns']['fallback']=shared
      @p['dns_enabled']=false
      File.write(config_path,YAML.dump(@v));File.write(profile_path,YAML.dump(@p))
      previous=ENV['OCOPT_TEST'];ENV['OCOPT_TEST']='1'
      begin
        OpenClashOptimizer.run(config_path,profile_path)
        result=YAML.safe_load(File.read(config_path),aliases:true)
        assert_equal shared,result['dns']['nameserver']
        assert_equal 'DOMAIN-SUFFIX,sky.test,OC · PT',result['rules'].first
      ensure
        ENV['OCOPT_TEST']=previous
      end
    end
  end
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
  def test_scoped_preserves_default_and_fallback
    @p['dns_scope']='scoped';@v['dns']['enable']=true;@v['dns']['nameserver']=['192.0.2.1'];@v['dns']['fallback']=['192.0.2.2']
    r=apply
    assert_equal ['192.0.2.1'],r['dns']['nameserver'];assert_equal ['192.0.2.2'],r['dns']['fallback']
    assert_equal r,apply(r)
  end
  def test_missing_dns_not_created_when_disabled
    @v.delete('dns');@p['dns_enabled']=false
    refute apply.key?('dns')
  end
  def test_scoped_missing_dns_restores_absence
    @v.delete('dns');@p['dns_scope']='scoped'
    r=apply;assert_equal true,r['dns']['enable'];@p['dns_enabled']=false
    refute apply(r).key?('dns')
  end
  def test_scoped_direct_dns_follows_policy_and_restores
    @p['dns_scope']='scoped';@v['dns']['direct-nameserver']=['system'];@v['dns']['direct-nameserver-follow-policy']=false
    r=apply;assert_equal true,r['dns']['direct-nameserver-follow-policy'];@p['dns_enabled']=false
    assert_equal @v['dns'],apply(r)['dns']
  end
end
