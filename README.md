# adguard-dns-merged

> ⚠️ **自用声明**：这是本人的个人自用 DNS 过滤订阅，仅供家庭网络 AdGuard Home 使用。不承诺 SLA，不保证规则时效性， url 随时可能调整。欢迎参考做法，不建议直接依赖作为公共服务。

把 AdGuard Home 上多个 DNS 黑名单订阅合并成一个自订阅地址，挂 GitHub Actions 每天凌晨自动更新。

## 订阅地址

在 AGH「过滤器 → DNS 封锁清单 → 添加订阅」里填入：

```
https://raw.githubusercontent.com/THENEBYS/adguard-dns-merged/main/merged.txt
```

若 AGH 拉 GitHub raw 不通，改用镜像前缀：

```
https://gh-proxy.com/https://raw.githubusercontent.com/THENEBYS/adguard-dns-merged/main/merged.txt
```

> 仓库必须**公开**，否则 AGH 匿名拉取拿不到文件。规则列表本身不含隐私。

## 为什么不用 Anti-AD 一家就够了

Anti-AD 确实是目前中文区命中率很高的列表，而且它自身也是「把各大 hosts / adblock 列表合并去重」的聚合器。实测对比：

| 指标 | 数量 |
|---|---|
| Anti-AD 唯一域名 | 96,447 |
| 本合并列表唯一域名 | 298,950 |
| 交集（两者都拦） | 96,447（Anti-AD **100%** 被包含，因为它本就是本列表的源之一） |
| 本列表独有（Anti-AD 未覆盖） | **202,503** |

本列表是 Anti-AD 的**超集**，多出约 20 万个域名（含色情、赌博、博彩等站点，样本如 `007win`、`.gaysexe`、`0-02.net`）。所以合并不是重复造轮子——是在 Anti-AD 之上叠加其余 6 个源的覆盖。

## 工作原理

- `sources.txt`：源地址清单，每行一个，`#` 开头为注释。**加源/删源只需增删一行**，脚本自动兼容，无需改代码。
- `merge.sh`：逐源拉取 → 去注释空行 → **整行** `sort -u` 去重 → 输出 `merged.txt`。
  - 整行去重保留 `@@` 例外与 `$important` 修饰符语义，AGH 解析器原生支持混合格式（hosts / Adblock / 例外）。
  - 单源失败或行数异常（< 100）自动跳过并告警，绝不让空结果覆盖。
  - 新结果低于旧结果 90% 时拒绝覆盖，防止源异常导致规则清空。
  - 大源带 3 次重试 + 90 秒超时（24 万行级源在 30 秒下会传一半就超时）。
- **文件头部统计**：生成时间、源数量、原始规则总数、去注释/去重删除数、最终保留数、压缩率、每源明细，全部写在 `merged.txt` 开头的 `#` 注释行里（AGH 忽略 `#` 行，不影响加载）。
- `.github/workflows/merge.yml`：北京时间每天 03:00 自动跑，产物有变化才 commit+push。

## 切换步骤

1. 确认 `merged.txt` 头部统计合理（当前约 30 万行）。
2. curl 实测订阅地址在 AGH 所在网络可达。
3. AGH 删除原有订阅，只保留这一个合并订阅。
4. **保留 `user_rules` 里的 `@@` 例外不动**（误杀修复的历史积累，优先级高于订阅规则）。
5. 观察 1-2 天查询日志，确认无误杀反弹。

## 数据来源与致谢

本列表合并了以下开源项目，感谢各位作者与维护者的持续付出（排名不分先后）：

| 订阅 | 项目 | 说明 |
|---|---|---|
| AdGuard SDNS Filter | [AdguardTeam/AdGuardSDNSFilter](https://github.com/AdguardTeam/AdGuardSDNSFilter) | AdGuard 官方基础域名过滤 |
| AdAway | [AdAway/adaway.github.io](https://github.com/AdAway/adaway.github.io) | 知名 Android 广告屏蔽 hosts |
| NEODEV | [NEODEV](https://neodev.team/adblocker) | 中文广告过滤列表 |
| 乘风视频过滤 | [xinggsf/Adblock-Plus-Rule](https://github.com/xinggsf/Adblock-Plus-Rule) | 国内视频站广告过滤 |
| anti-AD | [privacy-protection-tools/anti-AD](https://github.com/privacy-protection-tools/anti-AD) | 中文区高命中率广告/隐私过滤 |
| 217heidai | [217heidai/adblockfilters](https://github.com/217heidai/adblockfilters) | 综合 Adblock 规则 |
| 秋风 AWAvenue | [TG-Twilight/AWAvenue-Ads-Rule](https://github.com/TG-Twilight/AWAvenue-Ads-Rule) | 视频站广告过滤规则 |

如这些项目有更新，本列表会在每日定时任务中自动同步。

## 维护

加源 / 删源：改 `sources.txt` 后手动触发一次 Action（Actions → Run workflow）即可。
