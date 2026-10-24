# v0.2.0 验证记录

日期：2026-10-25。

| 检查 | 结果 |
|---|---|
| JavaScript 自动测试 | 16 项通过 |
| Ruby 3.3.12 自动测试 | 17 项、29 条断言通过 |
| JS / Ruby 输出一致性 | 默认、指定网站 DNS、旧版全局 DNS、仅 provider 配置，4 组逐项一致 |
| Mihomo v1.19.33 实际配置检查 | 上述 4 组全部通过 |
| Edge 中实际操作网页 | 默认生成、U2 DNS 方案、原 JS 串接、原 Shell 保留、缺少原文件报错、无效域名清空旧输出／下载均通过 |
| 网页生成的 JavaScript | Node 隔离执行通过，包含原脚本保留检查 |

覆盖重复应用、移除旧域名、DNS关闭后的恢复、无 DNS 配置、独立直连 DNS、provider 来源、组名冲突、非法域名、原脚本串接、YAML锚点和管理段替换。

FlClash v0.9.2 按官方源码核对：脚本采用 main(config)，保存后还需在当前配置中选择／绑定；配置生成过程中其他 DNS 覆写可能覆盖脚本字段。参考：[脚本编辑器](https://github.com/chen08209/FlClash/blob/v0.9.2/lib/views/profiles/extend/script.dart)、[配置任务](https://github.com/chen08209/FlClash/blob/v0.9.2/lib/common/task.dart)、[脚本执行器](https://github.com/chen08209/FlClash/blob/v0.9.2/plugins/rust_api/rust/src/api/script.rs)。

这些验证不等于已在用户单位电脑安装最新版 FlClash 验收，也不保证所有客户端、旧核心或网络环境都兼容。需要 DNS 高级字段时，建议先更新核心并检查实际运行配置。基础 OpenClash 分流方案曾在 0.47.055 / alpha-g0d4e57c 的 Redir-Host/TUN 环境使用；v0.2.0 通用生成器没有替换当前家庭路由器的整体配置。

不包含真实订阅、节点、密码、API凭据、站点Cookie、RSS或用户私有网络配置。
