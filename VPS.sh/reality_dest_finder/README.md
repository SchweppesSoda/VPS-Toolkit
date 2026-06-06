# REALITY Destination Finder

这个目录保存统一版 REALITY 回落域名查找脚本。

原先的通用版和 DMIT 版脚本内容完全一致。保留两个目录只会增加维护成本，因此合并为一个入口：

```bash
cd VPS.sh/reality_dest_finder
chmod +x reality_dest_finder.sh
./reality_dest_finder.sh
./reality_dest_finder.sh --check <域名>
```

说明文档见 `reality_dest_finder.md`。
