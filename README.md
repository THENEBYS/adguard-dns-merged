# adguard-dns-merged

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

## 工作原理

- `sources.txt`：源地址清单，每行一个，`#` 开头为注释。
- `merge.sh`：逐源拉取 → 去注释空行 → **整行** `sort -u` 去重 → 输出 `merged.txt`。
  - 整行去重保留 `@@` 例外与 `$important` 修饰符语义，AGH 解析器原生支持混合格式（hosts / Adblock / 例外）。
  - 单源失败或行数异常（< 100）自动跳过并告警，绝不让空结果覆盖。
  - 新结果低于旧结果 90% 时拒绝覆盖，防止源异常导致规则清空。
- `.github/workflows/merge.yml`：北京时间每天 03:00 自动跑，产物有变化才 commit+push。

## 切换步骤

1. 确认 `merged.txt` 已生成且行数合理（当前约 25 万行）。
2. curl 实测订阅地址在 AGH 所在网络可达。
3. AGH 删除原有 7 个订阅，只保留这一个合并订阅。
4. **保留 `user_rules` 里的 `@@` 例外不动**（误杀修复的历史积累，优先级高于订阅规则）。
5. 观察 1-2 天查询日志，确认无误杀反弹。

## 维护

加源 / 删源：改 `sources.txt` 后手动触发一次 Action（Actions → Run workflow）即可。
