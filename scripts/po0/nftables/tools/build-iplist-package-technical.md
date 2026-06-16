# build-iplist-package 技术文档

本文记录 `build-iplist-package.sh` 和 `build-iplist-package.ps1` 的数据源、构建流程、包格式和失败边界。两个脚本做同一件事：在本地生成给 `nftables-relay-manager.sh` 导入的地区源 IP 白名单离线包。

## 数据源

地区白名单数据来自 `metowolf/iplist` 仓库：

```text
https://github.com/metowolf/iplist
```

构建入口文件固定为：

```text
https://raw.githubusercontent.com/metowolf/iplist/refs/heads/master/docs/cncity.md
```

`cncity.md` 是地区索引文档。脚本只使用其中指向 `data/cncity/*.txt` 的链接；`data/country/*` 或其它目录的链接会被忽略。这样生成的包只覆盖国内省市级地区白名单，和管理器菜单里的“地区白名单”语义保持一致。

## 输出包格式

默认输出：

```text
~/Desktop/iplist.tar.gz
```

包内目录结构：

```text
docs/cncity.md
data/cncity/*.txt
```

管理器导入后会在 VPS 上生成：

```text
/etc/nftables.d/po0-iplist/docs/cncity.md
/etc/nftables.d/po0-iplist/data/cncity/*.txt
/etc/nftables.d/po0-iplist/manifest.tsv
```

`manifest.tsv` 不由构建脚本写入，而是在 `nftables-relay-manager.sh` 导入包时根据 `docs/cncity.md` 重新解析生成。这样可以在导入阶段校验包内索引和实际数据文件是否一致。

## Bash 实现流程

`build-iplist-package.sh` 的流程：

```text
1. 读取输出路径：第 1 个参数，默认 ~/Desktop/iplist.tar.gz。
2. 读取并发数：优先 IPLIST_JOBS，其次第 2 个参数，默认 8。
3. 创建临时目录 po0-iplist.*，并注册 EXIT 清理。
4. 下载 docs/cncity.md。
5. 从文档中提取所有 http/https 且以 .txt 结尾的 URL。
6. 用 relative_data_path() 只保留 data/cncity/*.txt。
7. 把支持的下载项写入 NUL 分隔队列文件。
8. 用 xargs -0 -n 4 -P 并发下载地区数据文件。
9. 用 tar -czf 打包 docs 和 data 目录。
10. 删除临时目录。
```

路径过滤逻辑：

```text
*/iplist/data/cncity/*.txt  -> data/cncity/<file>
*/data/cncity/*.txt         -> data/cncity/<file>
其它 URL                      -> 跳过
```

下载工具优先级：

```text
curl -fL --retry 3 --connect-timeout 10 --max-time 60
wget -q
```

如果 `curl` 和 `wget` 都不可用，脚本会失败退出。

## PowerShell 实现流程

`build-iplist-package.ps1` 面向 Windows PowerShell / PowerShell 7，行为和 Bash 版本保持一致：

```text
1. 读取 -OutFile，默认当前用户 Desktop/iplist.tar.gz。
2. 读取 -ThrottleLimit，默认 8，必须大于 0。
3. 创建临时目录 po0-iplist-*。
4. 用 Invoke-WebRequest 下载 docs/cncity.md。
5. 用正则提取 .txt URL。
6. 用 Get-RelativeDataPath 只保留 data/cncity/*.txt。
7. 用 Start-Job 按 -ThrottleLimit 并发下载。
8. 等待所有 Job 完成，收集失败信息。
9. 如已有输出文件，先删除旧文件。
10. 在临时目录中调用 tar -czf 打包 docs 和 data。
11. finally 中递归删除临时目录。
```

PowerShell 版本依赖系统可用的 `tar` 命令。Windows 10/11 通常内置 BSD tar；如果缺失，需要先安装 tar 或使用 Bash 版本。

## 管理器导入逻辑

生成包上传到 VPS 后，通过：

```text
菜单路径：系统维护 -> 管理源 IP 白名单
6) 导入 / 刷新 iplist 离线包
```

导入函数 `import_iplist_package()` 会：

```text
1. 校验包文件存在。
2. 校验系统有 tar。
3. 解压 .tar.gz、.tgz 或 .tar 到临时目录。
4. 要求包根目录存在 docs/cncity.md。
5. 调用 build_iplist_manifest_for_dir() 生成 manifest.tsv。
6. 校验 manifest 里的每个 data/cncity/*.txt 都存在。
7. 用新目录原子替换 /etc/nftables.d/po0-iplist。
8. 如果替换失败，尽量恢复旧目录。
```

`build_iplist_manifest_for_dir()` 从 `cncity.md` 的表格列中读取地区名称和数据 URL，生成：

```text
id<TAB>地区名称<TAB>相对路径<TAB>原始 URL
```

其中 `id` 来自数据文件名去掉 `.txt` 后的值，只保留 `A-Za-z0-9._-`，其它字符替换为 `_`。地区选择菜单实际保存的就是这些 `id`。

## 安全边界

构建脚本只下载并打包数据，不修改 nftables，也不接触 VPS 配置。真正影响放行范围的是管理器导入后再执行的白名单重建流程：

```text
build_src_allowlist_cache()
write_nft_allowlist_set()
nft -c -f 预检
reload_managed_rules 或 apply_full_config
```

因此，更新离线包后仍需要在 VPS 端导入并重新应用白名单，新的地区 CIDR 才会进入 nft set。
