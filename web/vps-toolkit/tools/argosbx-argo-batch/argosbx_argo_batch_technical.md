# Argosbx Argo 批量替换器技术文档

对应文件：`web/vps-toolkit/tools/argosbx-argo-batch/argosbx_argo_batch.html`

## 1. 定位

`argosbx_argo_batch.html` 是一个面向 Argosbx Argo VLESS 节点模板的批量替换工具。它把用户提供的 443/TLS 模板、80/明文模板，与 BestCF/Cloudflare 优选主机清单和端口集合做组合，生成大量新的 `vless://` 节点。

页面是零构建静态 HTML，CSS、DOM、JavaScript 全部内联，无后端依赖。除在线拉取 BestCF 清单外，其他处理都在浏览器本地完成。

## 2. 核心功能

- 输入 443/TLS VLESS WS Argo 模板。
- 输入 80/明文 VLESS WS Argo 模板。
- 自动清洗模板输入，只保留第一条 `vless://`。
- 从 DustinWin/BestCF 拉取优选域名或 IP 清单。
- 支持 `.txt` 文件上传作为清单来源。
- 支持手动粘贴主机清单。
- 支持 IPv4、IPv6、域名过滤。
- 支持 443 系和 80 系 Cloudflare 常用端口批量选择。
- 支持额外自定义端口。
- 支持全选、全清、反选、随机、预设端口。
- 批量生成节点并复制或下载。

## 3. 页面设计

页面采用深色终端风格，功能路径较短：

1. 粘贴或清洗 443 模板。
2. 粘贴或清洗 80 模板。
3. 拉取、上传或粘贴主机清单。
4. 选择主机过滤模式。
5. 选择 443 和 80 端口。
6. 设置节点名前缀。
7. Generate、Copy 或 Download。

与通用节点管理器不同，该页面不做协议分析、分组、互转和复杂校验，重点是快速生成笛卡尔积节点。

## 4. 输入输出模型

### 4.1 输入

输入由四部分构成：

- `tpl443`：443/TLS 模板。
- `tpl80`：80/明文模板。
- `hosts`：主机清单，一行一个。
- `ports443` / `ports80`：隐藏 input，保存当前选中的端口。

模板预期格式：

```text
vless://uuid@host:port?query#name
```

主机清单支持：

- 域名。
- IPv4。
- 裸 IPv6。
- `[IPv6]`。
- `[IPv6]:port`。
- `host:port`。
- 行尾 `#` 注释。

### 4.2 输出

输出是多行文本：

```text
# ===== CF-TLS (N hosts × M ports = K nodes) =====
vless://...

# ===== CF-HTTP (N hosts × M ports = K nodes) =====
vless://...
```

每条节点只替换模板中的：

- `@host:port`
- 末尾 `#name`

其他参数保持模板原样，包括 UUID、encryption、flow、WS host、path、TLS、SNI 等。

## 5. 端口选择系统

端口选择由 `PORT_PRESETS` 和 `portState` 管理。

```js
const PORT_PRESETS = {
  p443: {
    base: [443, 2053, 2083, 2087, 2096, 8443],
    default: [443, 2053, 2083, 2087, 2096, 8443]
  },
  p80: {
    base: [80, 8080, 8880, 2052, 2082, 2086, 2095],
    default: [80, 8080, 8880, 2052, 2082, 2086, 2095]
  }
};
```

关键函数：

- `getExtraPorts(group)`：解析用户输入的额外端口，过滤非法端口。
- `getGridPorts(group)`：合并基础端口和额外端口，去重排序。
- `rebuildPortGrid(group)`：根据当前端口集合重建 UI。
- `togglePort(group, port)`：切换单个端口。
- `portAction(group, action, presetVal)`：执行全选、全清、反选、随机、预设。
- `syncPortInput(group)`：把 `Set` 同步到隐藏 input，并更新选中计数。

隐藏 input 的作用是让后续 `generate()` 仍可通过 `parsePorts()` 读取端口，避免生成逻辑直接依赖 UI DOM 结构。

## 6. 模板清洗逻辑

`cleanTemplate(textareaId)` 用于处理混杂粘贴：

1. 读取 textarea 原始内容。
2. 用正则匹配所有 `vless://` 片段。
3. 如果未找到，显示错误。
4. 如果找到多条，只保留第一条。
5. 写回 textarea。
6. 在对应状态区显示清洗结果。

当前清洗只支持 `vless://`，这是符合工具定位的：该页面是 VLESS Argo 模板批量替换器，不是通用节点清洗器。

## 7. BestCF 清单拉取

在线拉取由 `fetchList()` 完成。

### 7.1 源优先级

`SOURCES` 按顺序尝试：

1. GitHub raw。
2. jsDelivr CDN。
3. `corsproxy.io`。
4. `cors.isomorphic-git.org`。
5. `api.codetabs.com`。
6. `api.allorigins.win`。
7. `thingproxy.freeboard.io`。

这样设计是为了提高浏览器端跨域拉取成功率。

### 7.2 超时控制

`fetchWithTimeout(url, ms = 20000)` 使用 `AbortController` 实现 20 秒超时，避免网络不可用时页面长时间等待。

### 7.3 响应校验

`looksLikeHostList(text)` 校验返回内容：

- 空响应判失败。
- HTML 页面判失败，通常是错误页。
- JSON error 判失败。
- 去掉注释和空行后必须有有效内容。
- 前 20 行中至少有一行看起来像域名或 IPv4。

全部源失败后，页面提示用户上传 `.txt` 或手动复制粘贴。

## 8. 主机解析与过滤

`parseHosts(str)` 处理主机清单：

- 跳过空行。
- 跳过整行 `#` 或 `//` 注释。
- 剥离行尾 `#` 注释。
- `[IPv6]` 和 `[IPv6]:port` 会提取 IPv6 地址。
- 裸 IPv6 直接作为 host。
- IPv4、域名、`host:port` 会提取 host。

生成前根据 `hostFilter` 执行过滤：

- `all`：全部主机。
- `v4only`：IPv4 + 域名，排除 IPv6。
- `v6only`：仅 IPv6。
- `domainonly`：仅包含字母且不是 IPv6 的域名。

IPv6 判断规则是：包含至少两个冒号，且不包含点号。

## 9. 节点重写逻辑

核心函数：

```js
function rewrite(template, newHost, newPort, newName)
```

处理步骤：

1. `formatHostForUrl(newHost)` 格式化 host。
2. 使用正则替换模板中的 `@host:port`。
3. 替换最后一个 `#name`。
4. 如果原模板没有 `#name`，则追加。
5. 使用 `encodeURIComponent(newName)` 编码节点名。

入口替换正则：

```js
/@(?:\[[^\]]+\]|[^:?\s\/]+):\d+/
```

它兼容：

- `@domain:443`
- `@1.2.3.4:443`
- `@[2606:4700::1]:443`

这个函数有意只替换入口地址和显示名，不修改 query 参数。这样可以最大限度保留原 Argo 模板参数。

## 10. 生成流程

`generate()` 是主流程：

1. 读取 `tpl443`、`tpl80`。
2. 调用 `parseHosts()` 解析主机。
3. 调用 `parsePorts()` 读取 443 和 80 端口。
4. 读取节点名前缀 `prefix443`、`prefix80`。
5. 根据 `hostFilter` 过滤主机。
6. 校验过滤后主机不能为空。
7. 校验至少填写一个模板。
8. 对 443 模板执行 `hosts × p443` 组合。
9. 对 80 模板执行 `hosts × p80` 组合。
10. 写入 `output`。
11. 显示生成数量统计。

节点命名格式：

```text
{prefix}-{host}-{port}
```

IPv6 节点会插入 `-v6`：

```text
{prefix}-v6-{host-with-colon-replaced}-{port}
```

`cleanHostForName()` 会去掉 IPv6 方括号，并把冒号替换为短横，避免节点名里出现不易读的编码结果。

## 11. 复制与下载

- `copyOut()`：读取 `output.textContent`，调用 `navigator.clipboard.writeText()`。
- `downloadOut()`：构造 `Blob`，生成临时 object URL，下载文件名为 `argosbx-argo-batch-{timestamp}.txt`。

这两个函数都只处理当前输出区内容，不重新生成。

## 12. Demo 数据

`loadDemo()` 会填入：

- 一个 443 VLESS WS TLS Argo 示例。
- 一个 80 VLESS WS Argo 示例。
- 几个 Cloudflare 相关域名。

Demo 中 encryption 是占位内容，页面会提示用户替换成真实参数。

## 13. 已知限制

- 只支持 VLESS Argo 模板，不适合其他协议。
- 模板必须包含标准 `@host:port` 结构，否则替换可能失败。
- 工具不会验证 UUID、encryption、flow、WS host、path、SNI 是否正确。
- 在线拉取依赖外部服务和浏览器 CORS，失败时需要上传或手动粘贴。
- 节点名始终 URL 编码，和 `proxy_node_manager.html` 默认不编码的策略不同。
- 主机清单中的裸 IPv6 加端口不可靠，IPv6 带端口应使用 `[IPv6]:port`。
- `parsePorts()` 返回字符串端口，当前生成逻辑可正常使用；若后续做数值比较，应显式转数字。

## 14. 维护建议

- 新增清单文件：修改 `releaseFile` 下拉选项即可。
- 新增拉取源：追加 `SOURCES`，并保证返回纯文本清单。
- 新增端口预设：修改 `PORT_PRESETS` 和对应 UI chip。
- 新增主机过滤模式：同时修改 `hostFilter` 下拉和 `generate()` 的过滤分支。
- 若要支持其他协议，应新增独立模板区和重写函数，不建议把当前 VLESS 正则直接泛化到所有协议。
- 建议补充“替换失败检测”：如果 `rewrite()` 后入口仍和模板一致，应提示用户模板格式异常。

## 15. 人工测试清单

- 模板输入混有标题、emoji、空行时，清洗后只保留第一条 `vless://`。
- 只填 443 模板时可生成 443 节点。
- 只填 80 模板时可生成 80 节点。
- 同时填写两个模板时，输出包含两个分组。
- GitHub raw 或 CDN 拉取失败时能继续尝试下一个源。
- 上传 `.txt` 后主机数量正确。
- `host:port` 输入能剥离端口，只使用 host。
- `[IPv6]:port` 输入能提取 IPv6 host。
- IPv6 输出入口使用 `[IPv6]:port`。
- IPv6 节点名里的冒号被替换为短横。
- 全选、全清、反选、随机、预设端口后隐藏 input 和计数同步。
- Copy 和 Download 使用当前输出，不触发重新生成。

