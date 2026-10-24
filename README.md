# Clash 分流助手 v0.2.0

离线小工具：填网站、选直连或代理，导出适合 **OpenClash 软路由**或 **FlClash 电脑客户端**的覆写文件。

**下载整个项目，双击 `index.html` 即可使用。** 无需安装，不上传订阅、节点或账号，不发起网络请求。

![工具界面](02-tool.png)

## 怎么用

1. 选择 FlClash 或 OpenClash。
2. 填网站地址，选择“直连”或“使用主代理组”。主代理组先用 AUTO，识别不合适时填客户端里的完整组名。
3. 生成文件，按页面提示导入客户端。已有自定义脚本时，先备份并导入原脚本。
4. 重新加载配置，在代理页确认新组当前选中的线路，再打开网站检查。

**网站能正常打开，就先保留 DNS 原设置。** 默认示例是 U2 网页直连，不修改 DNS。

具体入口、备份与恢复方法见 [简明教程](TUTORIAL.md)。

## 支持什么

| 场景 | 导出 | 应用位置 |
|---|---|---|
| OpenClash 软路由 | `.sh` | 持久覆写模块 |
| FlClash 电脑客户端 | `.js` | 进阶配置 → 脚本，然后绑定当前配置 |
| 其他 Mihomo / Clash.Meta 客户端 | `.js` | 客户端提供的 `main(config)` 脚本入口 |

两种文件不能互相粘贴。Clash Verge Rev 采用同类入口；其他客户端需核对接口，不能概括为支持所有 VPN 软件。FlClash 可以使用系统代理，不要求为了本工具开启 TUN；系统代理只影响遵循该设置的应用。

FlClash v0.9.2 的入口与执行流程已按官方源码核对；脚本经过隔离执行与实际 Mihomo 格式检查。没有把源码核对当作所有客户端的安装验收。验证范围见 [VALIDATION.md](VALIDATION.md)。

## 直连和 DNS 是什么关系

**DNS 是查地址，直连／代理是决定网页怎样连接。** 它们可以分别选择。

例如 U2 可以这样走：

```text
查 u2.dmhy.org 的地址 → 通过代理查询境外 DNS
打开 U2 网页          → DIRECT，使用当前网络出口
```

这两步同时成立。直连变顺，说明当前直连路径更适合；单凭它不能判断 DNS 有故障。家里路由器的设置也不会自动同步到单位 FlClash。

需要时展开“DNS与Tracker例外”，或点“U2直连＋经代理查地址”。新版默认只为指定网站添加解析策略，保留原默认 DNS 和 fallback；旧版全局方案仍可选。代理节点入口自己的解析又是单独一层，不能用网站 DNS 的测试代替它。

## 会改哪些东西

新增指定网站的策略组和优先规则；开启 DNS 选项后才调整相应解析策略。保留原节点、订阅、监听端口、TUN、IPv6和其他规则。重复应用会更新本工具管理的部分；与已有组同名会拒绝覆盖。

OpenClash 保留原 Shell 文件的其他内容，配置副本通过内核检查后才写入。FlClash 可以串接原 `main(config, profileName)`：先执行原脚本，再追加分流。工具不会审计导入脚本中的外来命令，请只导入自己的可信原脚本。

默认出口不是强制重置，客户端可能保留手动选择，请到代理页确认。工具不操作 qB、BT任务、Tracker重汇报或路由器流量限制，也不保证提升网速。

## 更新与恢复

保留原脚本备份和 `profile.json`。以后导入方案继续编辑。JavaScript 使用安装前的原始脚本作为基础，不要把生成脚本层层嵌套；OpenClash 可以重新导入当前覆写文件。

恢复时还原原脚本并重新加载配置。若此后还有其他修改，先保留当前备份再合并恢复。

## 开发

```text
node --test test_optimizer.js
ruby -EUTF-8 test_optimizer.rb
python build.py
```

源文件：`ui-v2.template.html`、`optimizer.js`、`optimizer.rb`、`exporters.js`。`index.html` 是可直接使用的打包结果；`ui.template.html` 保留为 v0.1 历史界面。

MIT。见 [变更记录](CHANGELOG.md)。参考：[FlClash v0.9.2](https://github.com/chen08209/FlClash/releases/tag/v0.9.2)、[Mihomo DNS](https://wiki.metacubex.one/config/dns/)、[OpenClash](https://github.com/vernesong/OpenClash)。
