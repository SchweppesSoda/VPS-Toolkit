# 安装依赖
apt update && apt install -y nmap jq dnsutils openssl curl bc

# 清理旧数据
rm -rf ~/reality_scan

# 赋权运行（放在root目录）
chmod +x reality_dest_finder.sh
./reality_dest_finder.sh

# 看结果
cat ~/reality_scan/results_*.txt

# 看过滤详情
cat ~/reality_scan/all_filtered.txt

# 深度检测
./reality_dest_finder.sh --check <域名>