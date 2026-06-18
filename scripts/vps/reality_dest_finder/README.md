# REALITY Destination Finder

这个目录保存统一版 REALITY 回落域名查找脚本。

原先的通用版和 DMIT 版脚本内容完全一致。保留两个目录只会增加维护成本，因此合并为一个入口：

```bash
cd scripts/vps/reality_dest_finder
chmod +x reality_dest_finder.sh
./reality_dest_finder.sh
./reality_dest_finder.sh --check <域名>
```

依赖安装：

```bash
apt update && apt install -y nmap jq dnsutils openssl curl bc
```

常用检查：

```bash
cat ~/reality_scan/results_*.txt
cat ~/reality_scan/all_filtered.txt
./reality_dest_finder.sh --check <域名>
```

清理旧扫描数据：

```bash
rm -rf ~/reality_scan
```
