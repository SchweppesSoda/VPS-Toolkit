# Proxy 节点管理器技术文档

对应文件：

- `web/vps-toolkit/tools/proxy-node-manager/proxy_node_manager.html`
- `web/vps-toolkit/tools/proxy-node-manager/proxy_node_manager_themes.css`
- `web/vps-toolkit/tools/proxy-node-manager/proxy_node_manager.css`
- `web/vps-toolkit/tools/proxy-node-manager/proxy_node_qr.js`
- `web/vps-toolkit/tools/proxy-node-manager/proxy_node_manager.js`

## 1. 定位

`proxy_node_manager.html` 是一个本地浏览器运行的代理节点清洗、解析、分组、命名和输出转换工具。它面向脚本输出、URL/URI 节点列表、Base64 订阅、Clash `proxies:` 片段等混杂输入，目标是把不可维护的原始节点文本整理为可编辑、可分组、可复制和可下载的标准输出。

页面是零构建静态单页工具，无后端依赖。HTML 保留页面结构，主题变量、基础样式和 JavaScript 拆分为同目录资源文件，便于 GitHub Pages 直接发布和日常维护。

## 2. 核心功能

- 清洗混杂文本，提取代理节点。
- 支持 URL/URI 分享链接和 Clash proxy 节点。
- 支持 Base64 URI 订阅自动识别和解码。
- 支持删除重复节点，重复判断忽略 `#` 后的旧节点名。
- 支持协议识别和协议过滤。
- 支持按 VPS/主机特征自动分组。
- 支持国家/地区 emoji 自动识别和手动覆盖。
- 支持命名模板、清理词表、手动改名、分组改名。
- 支持生成转发副本，替换节点入口 host/port。
- 支持输出为原格式、URL/URI 列表、Clash proxies YAML、Base64 URI 订阅。
- 支持节点 URL/URI 链接在本地浏览器生成二维码，可从手动输入、底部当前输出第一条或节点表格单条链接载入。
- 支持复制、下载、解析详情、输出详情和内置自测。

## 3. 页面设计

页面采用工作台布局：

- 顶部状态区：显示节点数、VPS 数、协议数、清理行数。
- 左侧输入区：粘贴原始节点、脚本输出或 Clash 片段。
- 右侧设置区：通过“命名 / 转发 / 输出”标签页组织 VPS 前缀命名、协议过滤、转发、Clash 输出属性、去重等选项。
- 中部结果区：清洗出结果后，以“VPS 前缀与节点分组”标题展示节点表格；无结果时不显示该标题。
- 底部输出区：以“转发与最终输出”标题组织输出内容、转发输出组合和输出格式。
- 节点二维码浮窗：通过右侧悬浮入口、底部输出按钮或节点表格行按钮打开，粘贴或载入一条 URL/URI 节点链接后生成二维码并下载 PNG。

主题通过 CSS 变量实现，`body[data-theme]` 切换不同皮肤变量；当前主题写入 `localStorage`，键名为 `proxy-node-manager-theme`。主题按钮按暗色和亮色分组展示，暗色包括暗黑、石墨、深海、Nord 和 Dracula，亮色保留明亮和 Solarized。

## 4. 状态模型

脚本用单个 `state` 对象保存应用状态：

- `allNodes`：完整解析节点集合。
- `nodes`：当前协议过滤后的节点集合。
- `groups`：VPS 分组集合。
- `activeProtocols`：启用中的协议集合。
- `groupNames`：用户修改过的分组名称。
- `groupOrder`：用户调整后的分组顺序。
- `ignoredLines`：非节点行预览。
- `parseIssues`：解析详情，包含清理、跳过和错误。
- `expandedDetails`：已展开详情的节点 ID。
- `outputContent`：输出内容模式，`renamed` 或 `clean`。
- `forwardOutputMode`：转发输出组合，`both`、`forward-only` 或 `original-only`。
- `outputFormat`：输出格式，`auto`、`uri`、`clash`、`base64-uri`。
- `clashProxyHeader`：输入中的 Clash `proxies:` 头信息。
- `removedLines`、`duplicateCount`、`invalidCount`：统计指标。

整体数据流是：原始输入 -> 提取候选项 -> 解析节点 -> 协议过滤 -> 分组 -> 命名 -> 输出。

## 5. 模块边界

代码中定义了三个门面对象：

```js
const NodeParser = {
  extract: extractLinks,
  parse: parseShareLink,
  parseClashProxy: parseClashProxyEntry
};

const NodeProcessor = {
  detectProtocol,
  detectCountryFlag,
  inferVpsName,
  makeSuggestedName,
  makeForwardName,
  formatProtocolForName
};

const NodeProducer = {
  formatLines: formatOutputLines,
  buildRecords: buildOutputRecords,
  buildRenamedLines: buildRenamedOutputLines,
  produce: produceOutputResult,
  render: renderProducedOutput,
  rewriteName,
  rewriteEndpoint
};
```

维护时建议继续按这三个边界扩展：

- `NodeParser`：只负责文本提取和协议解析。
- `NodeProcessor`：只负责协议识别、国家识别、VPS 推断和命名。
- `NodeProducer`：只负责改写节点和输出目标格式。

二维码编码器独立在 `proxy_node_qr.js`，通过 `window.ProxyNodeQr.encode()` 和 `window.ProxyNodeQr.drawToCanvas()` 暴露能力。主脚本只负责读取节点文本、选择第一条候选、复制/下载和页面状态提示；二维码算法不参与节点解析、命名或批量输出。

## 6. 解析流程

用户点击“清洗并分析”后执行 `analyze()`：

1. 读取 `rawInput`。
2. 调用 `NodeParser.extract(raw)` 提取候选节点。
3. 根据 `dropDuplicate` 设置去重。
4. 对候选项逐条调用 `NodeParser.parse()`。
5. 对解析失败项写入 `state.parseIssues`。
6. 写入 `state.allNodes`。
7. 重置协议过滤。
8. 构建分组。
9. 生成推荐名。
10. 渲染分组、输出和统计信息。

`extractLinks()` 负责宽容提取：

- 移除 ANSI 控制字符。
- 尝试把整体输入识别为 Base64 URI 订阅。
- 逐行扫描普通分享链接协议头。
- 识别并收集 Clash `proxies:` 下的 JSON/YAML proxy。
- 支持疑似被换行截断的链接续行。
- 将非节点行记录为 info 级解析详情。

## 7. 支持的输入格式

### 7.1 URL/URI 分享链接

协议白名单由 `SHARE_SCHEMES` 定义，包含：

- `vless`
- `vmess`
- `ss`
- `ssr`
- `trojan`
- `hysteria2` / `hy2`
- `tuic`
- `anytls`
- `socks` / `socks5`
- `http`
- `hysteria`
- `snell`
- `wireguard`
- `ssh`
- `mieru`

### 7.2 Clash proxy

支持两类常见写法：

```yaml
proxies:
  - {"name":"A","type":"ss","server":"1.2.3.4","port":443}
```

```yaml
proxies:
  - name: A
    type: vless
    server: example.com
    port: 443
    uuid: ...
    network: ws
```

YAML parser 是轻量实现，只覆盖 Clash proxy 常见 map、list、inline object、inline array，不是完整 YAML 规范解析器。

## 8. 节点对象

普通 URI 和 Clash proxy 都会归一为标准节点对象：

```js
{
  id,
  valid,
  raw,
  sourceFormat,
  clashMeta,
  scheme,
  rawName,
  host,
  port,
  user,
  method,
  query,
  extra,
  protocolLabel,
  protocolCode,
  detectedFlag,
  vpsCandidate,
  groupId,
  customName,
  suggestedName,
  forwardSelected,
  forwardHost,
  forwardPort,
  forwardName,
  forwardManual,
  manual
}
```

关键字段说明：

- `raw`：原始节点文本。
- `sourceFormat`：来源格式，Clash 节点会标记为 `clash`。
- `scheme`：归一后的协议。
- `rawName`：原始节点名。
- `host` / `port`：入口地址。
- `query`：URL 参数或从 Clash 字段映射出的参数。
- `protocolLabel`：展示用协议名。
- `protocolCode`：命名用协议短码。
- `vpsCandidate`：分组候选名。
- `customName`：最终输出名，可由用户编辑。
- `suggestedName`：系统推荐名。

## 9. 协议解析策略

- `vmess`：Base64 解码 JSON，读取 `ps`、`add`、`port`、`id`、`net`、`tls`、`host`、`path`、`aid`、`scy`。
- `ss`：兼容 `method:password@host:port` 和 Base64 userinfo 两种写法。
- 其他 URI：按通用 `user@host:port?query#name` 或 `scheme://host:port?query#name` 解析。
- Clash JSON/YAML：读取 `name`、`type`、`server`、`port` 等字段，并把 Clash 参数映射进标准节点对象。

解析后会调用 `validateParsedNode()` 做基础校验：

- 协议必须被支持。
- VMess 必须能解码出 host 和 port。
- 所有节点必须具备 host 和 port。

## 10. 协议识别

`detectProtocol()` 根据 `scheme`、`type`、`security`、`flow`、`encryption` 等信息生成协议描述。

示例：

- VLESS + WS + TLS -> `VLESS WS TLS`
- VLESS + Reality + Vision + 非 none encryption -> 带 `Reality`、`Vision`、`ENC`
- Shadowsocks-2022 -> `Shadowsocks-2022`
- Hysteria2 -> `HY2`
- WireGuard -> `WG`

`protocolLabel` 用于展示，`protocolCode` 用于命名和过滤。

## 11. VPS 分组和命名

### 11.1 VPS 推断

`inferVpsName()` 的顺序：

1. 读取并规范化原节点名。
2. 去除国家 emoji。
3. 删除常见协议前缀。
4. 删除协议后缀。
5. 应用用户配置的“节点名清理词表”。
6. 如果结果仍像纯协议名，回退到 host。
7. 最后回退到 `VPS-N`。

### 11.2 分组

`buildGroups()` 优先使用 `vpsCandidate` 作为分组 key，缺失时回退到：

```text
host|user|port
```

分组顺序由 `state.groupOrder` 保留，用户上移/下移后会影响最终输出顺序。

### 11.3 命名模板

默认模板：

```text
{国家} {VPS}_{协议}
```

支持占位符：

- `{国家}` / `{flag}`
- `{VPS}` / `{vps}`
- `{协议}` / `{proto}`

转发名模板额外支持：

- `{原名}` / `{name}`
- `{转发入口}` / `{host}`
- `{转发端口}` / `{port}`

## 12. 转发节点替换

转发功能默认关闭。开启后，只有在“重命名节点”输出模式下才会添加转发副本；“清洗节点”模式始终输出未改名、未转发的清洗结果。

转发路径模式默认是“每个节点单独路径”，更适合每条节点指向不同转发入口的场景。统一入口和单条节点入口都支持输入 `host:port`、`https://host:port/path` 或 `[IPv6]:port`，脚本会自动拆出 host 和 port 并回填端口框。

转发输出组合由 `forwardOutputMode` 控制：

- `both`：输出原节点记录和转发节点记录，转发副本插在原节点下一行。
- `forward-only`：只输出成功生成的转发节点记录；未选择、不可转发或入口无效的节点不会回退输出原节点。
- `original-only`：只输出原节点记录，即使已配置转发也不生成转发副本。

流程：

1. `buildOutputRecords()` 根据 `outputContent` 判断是否允许生成转发记录。
2. 根据 `forwardOutputMode` 决定是否写入原节点记录。
3. 若节点勾选转发，读取 `getForwardConfig()`。
4. `rewriteEndpoint()` 替换入口 host/port。
5. `rewriteName()` 写入转发节点名。
6. 根据输出组合写入转发记录。

支持重写：

- 普通 `@host:port` URI。
- 直连入口 `scheme://host:port` URI。
- Shadowsocks 明文或 Base64 userinfo。
- VMess Base64 JSON。
- Clash proxy 的 `server` 和 `port`。

IPv6 输出时会自动使用 `[IPv6]`。

## 13. 输出逻辑

输出由 `produceOutputResult(nodes, records, format)` 控制：

- `auto`：保持当前记录 raw 文本。
- `uri`：输出 URL/URI 列表，Clash proxy 会尽量转换为 URI。
- `clash`：输出 `proxies:`，可选单行 JSON proxy 或多行 YAML proxy。
- `base64-uri`：先生成 URI 列表，再 Base64 编码。

Clash 输出由 `nodeToClashProxy()` 转换，已覆盖：

- `ss`
- `vless`
- `vmess`
- `http`
- `socks/socks5`
- `trojan`
- `hysteria2/hy2`
- `hysteria`
- `tuic`
- `snell`
- `wireguard`
- `ssh`
- `mieru`

Clash proxy 反向转 URI 目前覆盖常见类型。不支持的类型会写入输出警告。

## 14. 节点二维码

节点二维码功能不依赖后端和第三方二维码 API，避免把节点密钥、密码或订阅信息发送到页面外。

入口：

- 手动粘贴单条 URL/URI 节点链接。
- 点击“输出第一条节点二维码”，从底部当前输出文本中提取第一条 URL/URI 节点链接；如果底部输出是 Clash YAML，需要先切换到 URL/URI 节点列表或 Base64 URL/URI 订阅。
- 点击节点表格“二维码”，把该行 URL/URI 原始链接载入二维码浮窗；Clash proxy 块不是 URL/URI 链接，按钮会禁用。

生成逻辑：

1. `getFirstQrCandidate()` 复用 `NodeParser.extract()`，多行内容优先取第一条 URL/URI 节点链接。
2. `generateSingleNodeQr()` 调用 `ProxyNodeQr.encode()`，生成 QR Code 矩阵。
3. `ProxyNodeQr.drawToCanvas()` 将矩阵画入 Canvas。
4. `downloadSingleNodeQrPng()` 直接从 Canvas 导出 PNG。

`proxy_node_qr.js` 使用 QR Code byte mode、纠错等级 L、version 1-40 自动选型。超出 version 40-L 容量时会提示链接过长。

## 15. 自测

页面内置 `runSelfTests()`，覆盖：

- URI 列表解析。
- 脚本输出混杂文本解析。
- Clash JSON proxy 解析。
- Clash YAML proxy 解析。
- Base64 URI 订阅。
- Clash 与 URI 输出切换。
- 转发输出组合切换。
- 不支持协议时的 warning。
- 重复节点、坏节点、清理行统计。
- 节点二维码生成和多行取第一条候选。

修改解析、命名、输出或二维码逻辑后，应先运行页面内置自测。

## 16. 已知限制

- YAML parser 不是完整 YAML parser，不支持 anchor、merge key、多文档等复杂语法。
- `auto` 输出中，原始 Clash YAML 块经过改名或转发重写后可能变为 JSON proxy 行。
- URI 与 Clash 互转可能丢失客户端私有字段或非标准参数。
- Base64 订阅识别只处理整体输入像 Base64 的场景。
- 去重忽略 `#name`，两个仅名称不同的节点会被视作重复。
- 默认不 URL 编码节点名，以兼容更多客户端；需要严格 URI 编码时要手动开启。
- 节点二维码使用 byte mode 和 L 级纠错，主要面向代理节点链接；极长链接超过 QR Code version 40-L 容量时不能生成。

## 17. 维护建议

- 新协议：同时检查 `SHARE_SCHEMES`、解析函数、`detectProtocol()`、`nodeToClashProxy()`、`clashProxyToUri()`。
- 新命名规则：优先放入 `NodeProcessor` 相关函数。
- 新输出格式：优先扩展 `produceOutputResult()`。
- 新解析提示：写入 `parseIssues`，复用现有详情面板。
- 涉及格式转换的修改必须补充或更新 `runSelfTests()`。
- 二维码逻辑保持在 `proxy_node_qr.js`，不要改成远程二维码 API。

## 18. 人工测试清单

- 普通 URI 多协议列表能解析、去重、命名、输出。
- 混杂脚本输出中的节点能被提取，非节点行进入解析详情。
- Base64 URI 订阅能自动解码。
- Clash JSON proxy 和 YAML proxy 都能解析并输出。
- 协议过滤后节点数量、分组数量、输出内容同步变化。
- 手动改名后，保留手动命名开启时刷新推荐名不会覆盖用户输入。
- 转发模式下，普通 URI、SS、VMess、Clash proxy 的 host/port 替换符合预期。
- Clash 输出中 `udp`、`skip-cert-verify`、`client-fingerprint`、`servername/sni` 批量属性生效。
- 节点二维码浮窗能手动生成、从底部当前输出第一条 URL/URI 节点链接生成、从节点表格单条 URL/URI 链接生成，并能下载 PNG。

