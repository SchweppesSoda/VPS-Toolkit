const $ = id => document.getElementById(id);

const SHARE_SCHEMES = [
  "vless",
  "vmess",
  "ss",
  "ssr",
  "trojan",
  "hysteria2",
  "hy2",
  "tuic",
  "anytls",
  "socks",
  "socks5",
  "http",
  "hysteria",
  "snell",
  "wireguard",
  "ssh",
  "mieru"
];
const SHARE_SCHEME_RE = new RegExp("\\b(" + SHARE_SCHEMES.join("|") + "):\\/\\/", "ig");
const STRIP_NAME_PATTERNS = [
  /^vless[-_ ]?xhttp[-_ ]?reality[-_ ]?(?:vision[-_ ]?)?enc[-_ ]*/i,
  /^vl[-_ ]?xhttp[-_ ]?reality[-_ ]?(?:vision[-_ ]?)?enc[-_ ]*/i,
  /^vless[-_ ]?tcp[-_ ]?reality[-_ ]?vision[-_ ]*/i,
  /^vl[-_ ]?reality[-_ ]?vision[-_ ]*/i,
  /^vless[-_ ]?xhttp[-_ ]?(?:vision[-_ ]?)?enc[-_ ]*/i,
  /^vl[-_ ]?xhttp[-_ ]?(?:vision[-_ ]?)?enc[-_ ]*/i,
  /^vless[-_ ]?ws[-_ ]?(?:vision[-_ ]?)?enc[-_ ]*/i,
  /^vl[-_ ]?ws[-_ ]?(?:vision[-_ ]?)?enc[-_ ]*/i,
  /^vless[-_ ]?ws[-_ ]*/i,
  /^vl[-_ ]?ws[-_ ]*/i,
  /^shadowsocks[-_ ]?2022[-_ ]*/i,
  /^ss[-_ ]?2022[-_ ]*/i,
  /^any[-_ ]?reality[-_ ]*/i,
  /^anytls[-_ ]*/i,
  /^hysteria2[-_ ]*/i,
  /^hy2[-_ ]*/i,
  /^tuic[-_ ]*/i,
  /^vmess[-_ ]?ws[-_ ]*/i,
  /^vmess[-_ ]*/i,
  /^socks5?[-_ ]*/i,
  /^trojan[-_ ]*/i,
  /^http[-_ ]*/i,
  /^hysteria[-_ ]*/i,
  /^snell[-_ ]*/i,
  /^wireguard[-_ ]*/i,
  /^wg[-_ ]*/i,
  /^ssh[-_ ]*/i,
  /^mieru[-_ ]*/i
];
const PROTOCOL_SUFFIX_WORDS = new Set([
  "VLESS",
  "VL",
  "XHTTP",
  "TCP",
  "WS",
  "RAW",
  "REALITY",
  "VISION",
  "TLS",
  "XTLS",
  "ENC",
  "SHADOWSOCKS",
  "SS",
  "SS2022",
  "ANYTLS",
  "HYSTERIA2",
  "HY2",
  "TUIC",
  "VMESS",
  "SOCKS5",
  "SOCKS",
  "TROJAN",
  "HTTP",
  "HYSTERIA",
  "SNELL",
  "WIREGUARD",
  "WG",
  "SSH",
  "MIERU"
]);
const COUNTRY_FLAG_BY_CODE = {
  HK: "🇭🇰",
  JP: "🇯🇵",
  SG: "🇸🇬",
  US: "🇺🇸",
  TW: "🇹🇼",
  KR: "🇰🇷",
  UK: "🇬🇧",
  GB: "🇬🇧",
  DE: "🇩🇪",
  NL: "🇳🇱",
  FR: "🇫🇷",
  CA: "🇨🇦",
  AU: "🇦🇺",
  CN: "🇨🇳",
  MO: "🇲🇴",
  TH: "🇹🇭",
  VN: "🇻🇳",
  ID: "🇮🇩",
  MY: "🇲🇾",
  PH: "🇵🇭",
  IN: "🇮🇳",
  TR: "🇹🇷",
  RU: "🇷🇺"
};

const SAMPLE = [
  "💣【 Vless-xhttp-reality-enc 】支持ENC加密，节点信息如下：",
  "vless://00000000-0000-4000-8000-000000000000@198.51.100.10:2083?encryption=mlkem768x25519plus.native.0rtt.demo&flow=xtls-rprx-vision&security=reality&sni=example.com&fp=chrome&pbk=PUBLIC_KEY_PLACEHOLDER&sid=abcd1234&type=xhttp&path=00000000-0000-4000-8000-000000000000-xh&mode=auto#vl-xhttp-reality-enc-demo.example.com",
  "",
  "💣【 Vless-tcp-reality-vision 】节点信息如下：",
  "vless://00000000-0000-4000-8000-000000000000@198.51.100.10:8443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=example.com&fp=chrome&pbk=PUBLIC_KEY_PLACEHOLDER&sid=abcd1234&type=tcp&headerType=none#vl-reality-vision-demo.example.com",
  "",
  "💣【 Shadowsocks-2022 】节点信息如下：",
  "ss://2022-blake3-aes-128-gcm:example-password@198.51.100.10:9443#Shadowsocks-2022-demo.example.com",
  "",
  "💣【 AnyTLS 】节点信息如下：",
  "anytls://00000000-0000-4000-8000-000000000000@198.51.100.10:2096?insecure=1&allowInsecure=1#anytls-demo.example.com",
  "",
  "💣【 Hysteria2 】节点信息如下：",
  "hysteria2://00000000-0000-4000-8000-000000000000@198.51.100.10:443 10000:11000 22000:23000?security=tls&alpn=h3&insecure=1&allowInsecure=1&sni=example.com#hy2-demo.example.com"
].join("\n");

const state = {
  allNodes: [],
  nodes: [],
  groups: [],
  activeProtocols: new Set(),
  groupNames: {},
  groupOrder: [],
  ignoredLines: [],
  parseIssues: [],
  expandedDetails: new Set(),
  outputContent: "renamed",
  forwardOutputMode: "both",
  outputFormat: "auto",
  clashProxyHeader: "",
  singleNodeQrText: "",
  removedLines: 0,
  duplicateCount: 0,
  invalidCount: 0
};

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

const THEME_CHOICES = new Set(["dark", "graphite", "deepsea", "nord", "dracula", "light", "solarized"]);

initTheme();

document.querySelectorAll("[data-theme-choice]").forEach(button => {
  button.addEventListener("click", () => setTheme(button.dataset.themeChoice));
});
$("parseBtn").addEventListener("click", analyze);
$("demoBtn").addEventListener("click", () => {
  $("rawInput").value = SAMPLE;
  analyze();
});
$("clearBtn").addEventListener("click", () => {
  $("rawInput").value = "";
  state.allNodes = [];
  state.nodes = [];
  state.groups = [];
  state.activeProtocols = new Set();
  state.groupNames = {};
  state.groupOrder = [];
  state.ignoredLines = [];
  state.parseIssues = [];
  state.expandedDetails = new Set();
  state.clashProxyHeader = "";
  state.removedLines = 0;
  state.duplicateCount = 0;
  state.invalidCount = 0;
  renderAll("等待输入。", "warn");
});
$("refreshNameBtn").addEventListener("click", () => refreshSuggestedNames(false));
$("applyAllBtn").addEventListener("click", () => refreshSuggestedNames(true));
$("protocolAllBtn").addEventListener("click", () => setAllProtocols(true));
$("protocolNoneBtn").addEventListener("click", () => setAllProtocols(false));
$("forwardEnabled").addEventListener("change", () => {
  renderGroups();
  renderOutput();
});
$("forwardMode").addEventListener("change", () => {
  refreshForwardNames(false, { silent: true });
  renderGroups();
  renderOutput();
});
$("forwardHost").addEventListener("input", () => {
  applyForwardEndpointInput($("forwardHost"), $("forwardPort"));
  refreshForwardNames(false, { silent: true });
});
$("forwardPort").addEventListener("input", () => refreshForwardNames(false, { silent: true }));
$("forwardNameTemplate").addEventListener("input", () => refreshForwardNames(false));
$("forwardAllBtn").addEventListener("click", () => setAllForwardSelected(true));
$("forwardNoneBtn").addEventListener("click", () => setAllForwardSelected(false));
$("forwardRefreshNameBtn").addEventListener("click", () => refreshForwardNames(true));
$("forwardOutputMode").addEventListener("change", () => {
  state.forwardOutputMode = $("forwardOutputMode").value;
  if (state.forwardOutputMode === "forward-only") {
    $("forwardEnabled").checked = true;
  }
  renderOutput();
});
["clashUdp", "clashSkipCert", "clashFingerprint", "clashServername", "clashStyle"].forEach(id => {
  $(id).addEventListener("input", renderOutput);
  $(id).addEventListener("change", renderOutput);
});
$("countrySelect").addEventListener("change", () => {
  clearCountrySelectSummary();
  refreshSuggestedNames(false);
});
$("countryEmoji").addEventListener("input", () => refreshSuggestedNames(false));
$("autoDetectCountry").addEventListener("change", () => refreshSuggestedNames(false));
$("nameCleanWords").addEventListener("input", () => refreshSuggestedNames(false));
$("nameTemplate").addEventListener("input", () => refreshSuggestedNames(false));
document.querySelectorAll("[data-name-template]").forEach(button => {
  button.addEventListener("click", () => {
    $("nameTemplate").value = button.dataset.nameTemplate;
    refreshSuggestedNames(false);
  });
});
document.querySelectorAll("[data-forward-template]").forEach(button => {
  button.addEventListener("click", () => {
    $("forwardNameTemplate").value = button.dataset.forwardTemplate;
    refreshForwardNames(false);
  });
});
document.querySelectorAll("[data-settings-tab]").forEach(button => {
  button.addEventListener("click", () => {
    const target = button.dataset.settingsTab;
    document.querySelectorAll("[data-settings-tab]").forEach(tab => {
      const active = tab.dataset.settingsTab === target;
      tab.classList.toggle("active", active);
      tab.setAttribute("aria-selected", active ? "true" : "false");
    });
    document.querySelectorAll("[data-settings-panel]").forEach(panel => {
      panel.hidden = panel.dataset.settingsPanel !== target;
    });
  });
});
$("copyBtn").addEventListener("click", copyOutput);
$("downloadBtn").addEventListener("click", downloadOutput);
$("selfTestBtn").addEventListener("click", runSelfTests);
$("qrOpenBtn").addEventListener("click", () => openSingleNodeQrDialog({ focusInput: false }));
$("qrCloseBtn").addEventListener("click", closeSingleNodeQrDialog);
$("qrGenerateBtn").addEventListener("click", () => generateSingleNodeQr());
$("qrClearBtn").addEventListener("click", () => clearSingleNodeQr());
$("qrCopyLinkBtn").addEventListener("click", copySingleNodeQrLink);
$("qrDownloadBtn").addEventListener("click", downloadSingleNodeQrPng);
$("singleNodeInput").addEventListener("input", () => {
  state.singleNodeQrText = "";
  $("singleNodeQrPreview").classList.remove("has-qr");
  $("singleNodeQrMeta").textContent = "已修改，尚未重新生成";
  setQrMessage("点击“生成二维码”更新预览。", "warn");
});
$("singleNodeQrDialog").addEventListener("click", event => {
  if (event.target === $("singleNodeQrDialog")) {
    closeSingleNodeQrDialog();
  }
});
document.addEventListener("keydown", event => {
  if (event.key === "Escape" && !$("singleNodeQrDialog").hidden) {
    closeSingleNodeQrDialog();
  }
});
$("outputFormat").addEventListener("change", () => {
  state.outputFormat = $("outputFormat").value;
  renderOutput();
});
document.querySelectorAll("[data-output-content]").forEach(btn => {
  btn.addEventListener("click", () => {
    state.outputContent = btn.dataset.outputContent;
    document.querySelectorAll("[data-output-content]").forEach(b => b.classList.toggle("active", b === btn));
    updateForwardOutputAvailability();
    renderOutput();
  });
});

function updateForwardOutputAvailability() {
  const select = $("forwardOutputMode");
  select.disabled = state.outputContent === "clean";
  select.title = select.disabled ? "清洗节点模式不生成转发副本" : "";
}

function initTheme() {
  setTheme(readStoredTheme(), { persist: false });
}

function readStoredTheme() {
  try {
    const stored = localStorage.getItem("proxy-node-manager-theme");
    return THEME_CHOICES.has(stored) ? stored : "dark";
  } catch (err) {
    return "dark";
  }
}

function setTheme(theme, opts = {}) {
  const next = THEME_CHOICES.has(theme) ? theme : "dark";
  if (document.body) {
    document.body.dataset.theme = next;
  }
  document.querySelectorAll("[data-theme-choice]").forEach(button => {
    const active = button.dataset.themeChoice === next;
    button.classList.toggle("active", active);
    button.setAttribute("aria-pressed", active ? "true" : "false");
  });
  if (opts.persist === false) return;
  try {
    localStorage.setItem("proxy-node-manager-theme", next);
  } catch (err) {
    // 主题选择失败不影响工具本身。
  }
}

function analyze() {
  const raw = $("rawInput").value;
  const extracted = NodeParser.extract(raw);
  state.removedLines = extracted.removedLines;
  state.ignoredLines = extracted.ignoredLines;
  state.parseIssues = [...(extracted.issues || [])];
  state.clashProxyHeader = extracted.clashProxyHeader || "";

  let rawItems = extracted.items || extracted.links.map((raw, index) => ({ raw, lineStart: index + 1, lineEnd: index + 1, source: "unknown" }));
  let duplicateCount = 0;
  if ($("dropDuplicate").checked) {
    const deduped = [];
    const seen = new Set();
    for (const item of rawItems) {
      const key = item.raw.replace(/#.*$/, "");
      if (seen.has(key)) {
        duplicateCount++;
        state.parseIssues.push({
          level: "skip",
          lineStart: item.lineStart,
          lineEnd: item.lineEnd,
          reason: "重复节点",
          text: item.raw
        });
        continue;
      }
      seen.add(key);
      deduped.push(item);
    }
    rawItems = deduped;
  }
  state.duplicateCount = duplicateCount;

  const nodes = [];
  let invalidCount = 0;
  rawItems.forEach((item, index) => {
    const parsed = NodeParser.parse(item.raw, index);
    if (!parsed.valid) {
      invalidCount++;
      state.parseIssues.push({
        level: "error",
        lineStart: item.lineStart,
        lineEnd: item.lineEnd,
        reason: parsed.error || "节点解析失败",
        text: item.raw
      });
      return;
    }
    parsed.lineStart = item.lineStart;
    parsed.lineEnd = item.lineEnd;
    parsed.source = item.source;
    nodes.push(parsed);
  });
  state.invalidCount = invalidCount;
  state.allNodes = nodes;
  state.groupNames = {};
  state.groupOrder = [];
  state.expandedDetails = new Set();
  resetProtocolFilter(nodes);
  applyProtocolFilter({ forceApply: true, silent: true });

  if (!nodes.length) {
    renderAll("没有找到可识别的节点链接。", "err");
    return;
  }

  const issueErrorCount = state.parseIssues.filter(item => item.level === "error").length;
  const msg = [
    "已清洗 " + nodes.length + " 条节点",
    "识别 " + state.groups.length + " 个 VPS",
    duplicateCount ? "删除重复 " + duplicateCount + " 条" : "",
    issueErrorCount ? "解析错误 " + issueErrorCount + " 条" : ""
  ].filter(Boolean).join("；") + "。";
  renderAll(msg, issueErrorCount ? "warn" : "ok");
}

function extractLinks(raw) {
  const originalText = stripAnsi(raw || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  const decodedInput = decodeBase64Subscription(originalText);
  const text = decodedInput ? decodedInput.text : originalText;
  const lines = text.split("\n");
  const items = [];
  const ignoredLines = [];
  const issues = [];
  if (decodedInput) {
    issues.push({
      level: "info",
      lineStart: 1,
      lineEnd: Math.max(1, originalText.split("\n").length),
      reason: "识别为 Base64 URL/URI 订阅，已解码后解析",
      text: "解码后 " + text.split("\n").filter(line => line.trim()).length + " 行"
    });
  }
  let removedLines = 0;
  let current = "";
  let currentStartLine = 0;
  let clashProxyHeader = "";
  let inClashProxies = false;
  let clashHeaderIndent = -1;

  const pushCurrent = () => {
    if (!current) return;
    pushItem(items, cleanLink(current), currentStartLine, lineEndFromCurrent(currentStartLine, current), "uri");
    current = "";
    currentStartLine = 0;
  };

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    const line = lines[lineIndex];
    const lineNumber = lineIndex + 1;
    const trimmed = line.trim();
    if (!trimmed) {
      pushCurrent();
      removedLines++;
      continue;
    }

    const clashHeaderMatch = line.match(/^(\s*)proxies\s*:\s*$/i);
    if (clashHeaderMatch) {
      pushCurrent();
      clashProxyHeader = clashHeaderMatch[1] + "proxies:";
      clashHeaderIndent = clashHeaderMatch[1].length;
      inClashProxies = true;
      removedLines++;
      continue;
    }

    if (inClashProxies && getIndent(line) <= clashHeaderIndent && !trimmed.startsWith("-")) {
      inClashProxies = false;
    }

    if (inClashProxies) {
      const block = collectClashYamlProxyBlock(lines, lineIndex, clashHeaderIndent);
      if (block && parseClashProxyEntry(block.raw)) {
        pushCurrent();
        pushItem(items, block.raw, lineNumber, block.endIndex + 1, "clash-yaml");
        lineIndex = block.endIndex;
        continue;
      }
      if (/^\s*-\s+/.test(line) && block) {
        issues.push({
          level: "error",
          lineStart: lineNumber,
          lineEnd: block.endIndex + 1,
          reason: "Clash YAML 节点缺少 name/type/server/port 或格式不完整",
          text: block.raw
        });
        removedLines += block.endIndex - lineIndex + 1;
        lineIndex = block.endIndex;
        continue;
      }
    }

    if (parseClashProxyEntry(line)) {
      pushCurrent();
      pushItem(items, line.trimEnd(), lineNumber, lineNumber, "clash-json");
      continue;
    }

    const found = findShareStarts(trimmed);
    if (found.length) {
      pushCurrent();
      if (found.length === 1) {
        current = trimmed.slice(found[0].index).trim();
        currentStartLine = lineNumber;
      } else {
        found.forEach((item, i) => {
          const next = found[i + 1];
          pushItem(items, cleanLink(trimmed.slice(item.index, next ? next.index : trimmed.length)), lineNumber, lineNumber, "uri");
        });
      }
      continue;
    }

    if (current && isLikelyLinkContinuation(current, trimmed)) {
      current += trimmed;
      continue;
    }

    pushCurrent();
    ignoredLines.push(formatIssueLine(lineNumber, "非节点行", trimmed));
    issues.push({
      level: "info",
      lineStart: lineNumber,
      lineEnd: lineNumber,
      reason: "非节点行",
      text: trimmed
    });
    removedLines++;
  }

  pushCurrent();

  const filteredItems = items.filter(item => {
    const keep = SHARE_SCHEMES.some(s => item.raw.toLowerCase().startsWith(s + "://")) || Boolean(parseClashProxyEntry(item.raw));
    if (!keep) {
      issues.push({
        level: "error",
        lineStart: item.lineStart,
        lineEnd: item.lineEnd,
        reason: "候选节点格式不支持",
        text: item.raw
      });
    }
    return keep;
  });

  return {
    items: filteredItems,
    links: filteredItems.map(item => item.raw),
    clashProxyHeader,
    removedLines,
    ignoredLines,
    issues
  };
}

function pushItem(items, raw, lineStart, lineEnd, source) {
  if (!raw) return;
  items.push({
    raw,
    lineStart,
    lineEnd,
    source
  });
}

function lineEndFromCurrent(lineStart, current) {
  return lineStart + (String(current || "").match(/\n/g) || []).length;
}

function formatIssueLine(lineStart, reason, text, lineEnd = lineStart) {
  return describeLineRange(lineStart, lineEnd) + "：" + reason + " | " + text;
}

function collectClashYamlProxyBlock(lines, startIndex, headerIndent) {
  const firstLine = lines[startIndex] || "";
  const firstMatch = firstLine.match(/^(\s*)-\s+(.+?)\s*$/);
  if (!firstMatch || firstMatch[2].trim().startsWith("{")) return null;

  const itemIndent = firstMatch[1].length;
  const blockLines = [firstLine.trimEnd()];
  let endIndex = startIndex;

  for (let index = startIndex + 1; index < lines.length; index++) {
    const line = lines[index];
    const trimmed = line.trim();
    if (!trimmed) {
      blockLines.push(line.trimEnd());
      endIndex = index;
      continue;
    }

    const indent = getIndent(line);
    if (indent <= headerIndent && !trimmed.startsWith("-")) break;
    if (indent <= itemIndent && /^-\s+/.test(line.slice(indent))) break;
    if (indent <= itemIndent) break;

    blockLines.push(line.trimEnd());
    endIndex = index;
  }

  return {
    raw: blockLines.join("\n"),
    endIndex
  };
}

function getIndent(line) {
  return (String(line || "").match(/^\s*/) || [""])[0].length;
}

function findShareStarts(line) {
  SHARE_SCHEME_RE.lastIndex = 0;
  const found = [];
  let match;
  while ((match = SHARE_SCHEME_RE.exec(line)) !== null) {
    found.push({ scheme: match[1].toLowerCase(), index: match.index });
  }
  return found;
}

function cleanLink(link) {
  return (link || "")
    .trim()
    .replace(/[，,。；;]+$/g, "")
    .replace(/\s+#/g, "#");
}

function looksLikeHeading(line) {
  return /节点信息如下|支持ENC加密|^[-=]{3,}$|^💣|^【.*】/.test(line);
}

function isLikelyLinkContinuation(current, line) {
  const trimmed = line.trim();
  if (!trimmed || looksLikeHeading(trimmed)) return false;
  if (current.includes("#")) return false;
  if (/^(?:vlpt|xhpt|vwpt|hypt|hyjpt|sspt|uuid|reym|argo|agn|agk)=/i.test(trimmed)) return false;
  if (/\bbash\s+<\(|\bcurl\b|cloudflared(?:\.exe)?\b|https?:\/\//i.test(trimmed)) return false;
  if (/^[-=]{3,}$/.test(trimmed)) return false;

  const schemeMatch = current.match(/^([a-z0-9+.-]+):\/\//i);
  const scheme = schemeMatch ? schemeMatch[1].toLowerCase() : "";
  if (/\s/.test(trimmed) && scheme !== "hysteria2" && scheme !== "hy2") return false;

  return /^[A-Za-z0-9._~:/?#[\]@!$&'()*+,;=%-]+(?:\s+\d+:\d+)*$/.test(trimmed);
}

function stripAnsi(str) {
  return str.replace(/\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])/g, "");
}

function decodeBase64Subscription(text) {
  const compact = String(text || "").trim().replace(/\s+/g, "");
  if (!compact || compact.length < 24) return null;
  if (!/^[A-Za-z0-9+/_=-]+$/.test(compact)) return null;

  const decoded = decodeBase64(compact).replace(/\r\n/g, "\n").replace(/\r/g, "\n").trim();
  if (!decoded || decoded === compact) return null;
  if (!containsShareLink(decoded)) return null;

  return { text: decoded };
}

function containsShareLink(text) {
  SHARE_SCHEME_RE.lastIndex = 0;
  return SHARE_SCHEME_RE.test(text);
}

function parseShareLink(raw, index) {
  const link = raw.trim();
  const clashProxy = parseClashProxyEntry(raw);
  if (clashProxy) {
    return parseClashProxyNode(raw.trimEnd(), index, clashProxy);
  }

  const schemeMatch = link.match(/^([a-z0-9+.-]+):\/\//i);
  if (!schemeMatch) {
    return { valid: false, raw: link, error: "不是支持的 URL/URI 或 Clash proxy 节点" };
  }

  const scheme = schemeMatch[1].toLowerCase();
  const withoutScheme = link.slice(schemeMatch[0].length);
  const split = splitFragment(withoutScheme);
  const rawName = decodeSafe(split.fragment || "");
  const body = split.body;

  const baseNode = {
    id: "node-" + index,
    valid: true,
    raw: link,
    scheme,
    rawName,
    host: "",
    port: "",
    user: "",
    method: "",
    query: {},
    extra: {},
    protocolLabel: "",
    protocolCode: "",
    detectedFlag: "",
    vpsCandidate: "",
    groupId: "",
    customName: "",
    suggestedName: "",
    forwardSelected: false,
    forwardHost: "",
    forwardPort: "",
    forwardName: "",
    forwardManual: false,
    manual: false
  };

  if (scheme === "vmess") {
    parseVmess(baseNode, body);
  } else if (scheme === "ss") {
    parseShadowsocks(baseNode, body);
  } else {
    parseGenericShare(baseNode, body);
  }

  NodeProcessor.detectProtocol(baseNode);
  const validationError = validateParsedNode(baseNode);
  if (validationError) {
    return { ...baseNode, valid: false, error: validationError };
  }
  baseNode.detectedFlag = NodeProcessor.detectCountryFlag(baseNode.rawName);
  baseNode.vpsCandidate = NodeProcessor.inferVpsName(baseNode);
  return baseNode;
}

function validateParsedNode(node) {
  if (node.sourceFormat !== "clash" && !SHARE_SCHEMES.includes(node.scheme)) return "不支持的协议：" + node.scheme;
  if (node.extra && node.extra.decodeError) return node.extra.decodeError;
  if (node.scheme === "vmess" && (!node.host || !node.port)) return "VMess 缺少 add/port";
  if (!node.host) return "缺少 server/host";
  if (!node.port) return "缺少 port";
  return "";
}

function parseClashProxyEntry(raw) {
  return parseClashProxyLine(raw) || parseClashProxyYamlBlock(raw);
}

function parseClashProxyLine(line) {
  const raw = String(line || "").trimEnd();
  const match = raw.match(/^(\s*)(-\s*)?(\{.*\})(,)?\s*$/);
  if (!match) return null;

  try {
    const proxy = JSON.parse(match[3]);
    if (!proxy || typeof proxy !== "object") return null;
    if (!proxy.name || !proxy.type || !proxy.server || proxy.port === undefined) return null;
    return {
      prefix: (match[1] || "") + (match[2] || ""),
      indent: match[1] || "",
      dash: match[2] || "",
      body: match[3],
      suffix: match[4] || "",
      proxy
    };
  } catch (err) {
    return null;
  }
}

function parseClashProxyYamlBlock(raw) {
  const text = String(raw || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n").trimEnd();
  const lines = text.split("\n");
  const first = lines[0] || "";
  const firstMatch = first.match(/^(\s*)-\s+(.+?)\s*$/);
  if (!firstMatch || firstMatch[2].trim().startsWith("{")) return null;

  const itemIndent = firstMatch[1].length;
  const fieldIndent = itemIndent + 2;
  const mapLines = [" ".repeat(fieldIndent) + firstMatch[2].trim(), ...lines.slice(1)];
  const parsed = parseYamlMap(mapLines, 0, fieldIndent);
  const proxy = parsed.value;
  if (!proxy || typeof proxy !== "object") return null;
  if (!proxy.name || !proxy.type || !proxy.server || proxy.port === undefined) return null;

  return {
    format: "yaml-block",
    prefix: firstMatch[1] + "- ",
    indent: firstMatch[1],
    dash: "- ",
    body: text,
    suffix: "",
    proxy
  };
}

function parseYamlMap(lines, startIndex, indent) {
  const output = {};
  let index = startIndex;

  while (index < lines.length) {
    const line = lines[index];
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      index++;
      continue;
    }

    const currentIndent = getIndent(line);
    if (currentIndent < indent) break;
    if (currentIndent > indent) {
      index++;
      continue;
    }

    const pair = splitYamlPair(trimmed);
    if (!pair) break;

    if (pair.value === "") {
      const next = findNextYamlContent(lines, index + 1);
      if (next === -1 || getIndent(lines[next]) <= currentIndent) {
        output[pair.key] = {};
        index++;
        continue;
      }
      if (lines[next].trim().startsWith("- ")) {
        const parsedList = parseYamlList(lines, next, getIndent(lines[next]));
        output[pair.key] = parsedList.value;
        index = parsedList.nextIndex;
      } else {
        const parsedMap = parseYamlMap(lines, next, getIndent(lines[next]));
        output[pair.key] = parsedMap.value;
        index = parsedMap.nextIndex;
      }
    } else {
      output[pair.key] = parseYamlScalar(pair.value);
      index++;
    }
  }

  return { value: output, nextIndex: index };
}

function parseYamlList(lines, startIndex, indent) {
  const output = [];
  let index = startIndex;

  while (index < lines.length) {
    const line = lines[index];
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      index++;
      continue;
    }
    const currentIndent = getIndent(line);
    if (currentIndent < indent) break;
    if (currentIndent > indent) {
      index++;
      continue;
    }
    const itemMatch = trimmed.match(/^-\s*(.*)$/);
    if (!itemMatch) break;

    const value = itemMatch[1].trim();
    if (!value) {
      const next = findNextYamlContent(lines, index + 1);
      if (next === -1 || getIndent(lines[next]) <= currentIndent) {
        output.push(null);
        index++;
      } else {
        const parsedMap = parseYamlMap(lines, next, getIndent(lines[next]));
        output.push(parsedMap.value);
        index = parsedMap.nextIndex;
      }
    } else if (splitYamlPair(value)) {
      const nestedLine = " ".repeat(currentIndent + 2) + value;
      const parsedMap = parseYamlMap([nestedLine, ...lines.slice(index + 1)], 0, currentIndent + 2);
      output.push(parsedMap.value);
      index += Math.max(1, parsedMap.nextIndex);
    } else {
      output.push(parseYamlScalar(value));
      index++;
    }
  }

  return { value: output, nextIndex: index };
}

function findNextYamlContent(lines, startIndex) {
  for (let index = startIndex; index < lines.length; index++) {
    const trimmed = lines[index].trim();
    if (trimmed && !trimmed.startsWith("#")) return index;
  }
  return -1;
}

function splitYamlPair(text) {
  let quote = "";
  for (let index = 0; index < text.length; index++) {
    const char = text[index];
    if (quote) {
      if (char === quote && text[index - 1] !== "\\") quote = "";
      continue;
    }
    if (char === "\"" || char === "'") {
      quote = char;
      continue;
    }
    if (char === ":") {
      return {
        key: text.slice(0, index).trim(),
        value: text.slice(index + 1).trim()
      };
    }
  }
  return null;
}

function parseYamlScalar(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  if (raw === "true") return true;
  if (raw === "false") return false;
  if (raw === "null") return null;
  if (/^-?\d+(?:\.\d+)?$/.test(raw)) return Number(raw);
  if ((raw.startsWith("\"") && raw.endsWith("\"")) || (raw.startsWith("'") && raw.endsWith("'"))) {
    return unquoteYamlString(raw);
  }
  if ((raw.startsWith("[") && raw.endsWith("]")) || (raw.startsWith("{") && raw.endsWith("}"))) {
    const parsed = parseYamlInlineCollection(raw);
    if (parsed !== undefined) return parsed;
  }
  return raw.replace(/\s+#.*$/, "").trim();
}

function unquoteYamlString(value) {
  if (value.startsWith("\"")) {
    try {
      return JSON.parse(value);
    } catch (err) {
      return value.slice(1, -1);
    }
  }
  return value.slice(1, -1).replace(/''/g, "'");
}

function parseYamlInlineCollection(value) {
  try {
    return JSON.parse(value);
  } catch (err) {
    if (value.startsWith("[") && value.endsWith("]")) {
      return splitYamlInline(value.slice(1, -1)).map(parseYamlScalar);
    }
    if (value.startsWith("{") && value.endsWith("}")) {
      const output = {};
      splitYamlInline(value.slice(1, -1)).forEach(item => {
        const pair = splitYamlPair(item.trim());
        if (pair) output[pair.key] = parseYamlScalar(pair.value);
      });
      return output;
    }
  }
  return undefined;
}

function splitYamlInline(value) {
  const parts = [];
  let current = "";
  let quote = "";
  let depth = 0;
  for (let index = 0; index < value.length; index++) {
    const char = value[index];
    if (quote) {
      current += char;
      if (char === quote && value[index - 1] !== "\\") quote = "";
      continue;
    }
    if (char === "\"" || char === "'") {
      quote = char;
      current += char;
      continue;
    }
    if (char === "[" || char === "{") depth++;
    if (char === "]" || char === "}") depth--;
    if (char === "," && depth === 0) {
      parts.push(current.trim());
      current = "";
      continue;
    }
    current += char;
  }
  if (current.trim()) parts.push(current.trim());
  return parts;
}

function parseClashProxyNode(raw, index, parsed) {
  const proxy = parsed.proxy;
  const scheme = normalizeClashProxyType(proxy.type);
  const baseNode = {
    id: "node-" + index,
    valid: true,
    raw,
    sourceFormat: "clash",
    clashMeta: parsed,
    scheme,
    rawName: decodeSafe(String(proxy.name || "")),
    host: String(proxy.server || ""),
    port: String(proxy.port || ""),
    user: String(proxy.username || proxy.uuid || ""),
    method: String(proxy.cipher || ""),
    query: clashProxyQuery(proxy),
    extra: {},
    protocolLabel: "",
    protocolCode: "",
    detectedFlag: "",
    vpsCandidate: "",
    groupId: "",
    customName: "",
    suggestedName: "",
    forwardSelected: false,
    forwardHost: "",
    forwardPort: "",
    forwardName: "",
    forwardManual: false,
    manual: false
  };

  NodeProcessor.detectProtocol(baseNode);
  const validationError = validateParsedNode(baseNode);
  if (validationError) {
    return { ...baseNode, valid: false, error: validationError };
  }
  baseNode.detectedFlag = NodeProcessor.detectCountryFlag(baseNode.rawName);
  baseNode.vpsCandidate = NodeProcessor.inferVpsName(baseNode);
  return baseNode;
}

function normalizeClashProxyType(type) {
  const clean = String(type || "").toLowerCase();
  if (clean === "hysteria2" || clean === "hy2") return "hysteria2";
  if (clean === "socks5") return "socks";
  return clean;
}

function clashProxyQuery(proxy) {
  const query = {};
  if (proxy.network) query.type = String(proxy.network);
  if (proxy.flow) query.flow = String(proxy.flow);
  if (proxy.encryption) query.encryption = String(proxy.encryption);
  if (proxy.password) query.password = String(proxy.password);
  if (proxy.tls === true) query.security = "tls";
  if (proxy["reality-opts"]) query.security = "reality";
  if (proxy.servername) query.sni = String(proxy.servername);
  if (proxy.sni) query.sni = String(proxy.sni);
  if (proxy["client-fingerprint"]) query.fp = String(proxy["client-fingerprint"]);
  return query;
}

function splitFragment(text) {
  const idx = text.indexOf("#");
  if (idx === -1) {
    return { body: text, fragment: "" };
  }
  return {
    body: text.slice(0, idx),
    fragment: text.slice(idx + 1)
  };
}

function parseGenericShare(node, body) {
  const querySplit = splitQuery(body);
  node.query = parseQuery(querySplit.query);
  const beforeQuery = querySplit.body.trim();
  const endpoint = beforeQuery.split(/\s+/)[0].replace(/\/+$/, "");
  node.extra.beforeQueryTail = beforeQuery.slice(endpoint.length).trim();
  parseUserHostPort(node, endpoint);
}

function parseShadowsocks(node, body) {
  const querySplit = splitQuery(body);
  node.query = parseQuery(querySplit.query);
  let endpoint = querySplit.body.trim();
  if (endpoint.includes("@")) {
    const at = endpoint.lastIndexOf("@");
    const userInfo = endpoint.slice(0, at);
    endpoint = endpoint.slice(at + 1);
    const parsedUser = parseSsUserInfo(userInfo);
    node.method = parsedUser.method;
    node.user = parsedUser.password;
    parseHostPort(node, endpoint);
    return;
  }

  const decoded = decodeBase64(endpoint);
  if (decoded && decoded.includes("@")) {
    const at = decoded.lastIndexOf("@");
    const userInfo = decoded.slice(0, at);
    endpoint = decoded.slice(at + 1);
    const parsedUser = parseSsUserInfo(userInfo);
    node.method = parsedUser.method;
    node.user = parsedUser.password;
    parseHostPort(node, endpoint);
    return;
  }
  node.extra.decodeError = "SS base64 decode failed";
}

function parseVmess(node, body) {
  const decoded = decodeBase64(body);
  if (!decoded) {
    node.extra.decodeError = "VMess base64 decode failed";
    return;
  }
  try {
    const data = JSON.parse(decoded);
    node.rawName = node.rawName || data.ps || "";
    node.host = data.add || "";
    node.port = String(data.port || "");
    node.user = data.id || "";
    node.query = {
      type: data.net || "",
      security: data.tls || "",
      host: data.host || "",
      path: data.path || "",
      aid: data.aid || "",
      cipher: data.scy || ""
    };
  } catch (err) {
    node.extra.decodeError = "VMess JSON parse failed";
  }
}

function splitQuery(text) {
  const idx = text.indexOf("?");
  if (idx === -1) {
    return { body: text, query: "" };
  }
  return {
    body: text.slice(0, idx),
    query: text.slice(idx + 1)
  };
}

function parseQuery(query) {
  const out = {};
  if (!query) return out;
  query.split("&").forEach(pair => {
    if (!pair) return;
    const eq = pair.indexOf("=");
    const key = eq === -1 ? pair : pair.slice(0, eq);
    const val = eq === -1 ? "" : pair.slice(eq + 1);
    out[decodeSafe(key).toLowerCase()] = decodeSafe(val);
  });
  return out;
}

function parseUserHostPort(node, endpoint) {
  const at = endpoint.lastIndexOf("@");
  if (at !== -1) {
    node.user = decodeSafe(endpoint.slice(0, at));
    parseHostPort(node, endpoint.slice(at + 1));
  } else {
    parseHostPort(node, endpoint);
  }
}

function parseHostPort(node, hostPort) {
  const cleaned = hostPort.trim().replace(/\/+$/, "");
  if (!cleaned) return;

  if (cleaned.startsWith("[")) {
    const end = cleaned.indexOf("]");
    if (end !== -1) {
      node.host = cleaned.slice(1, end);
      const rest = cleaned.slice(end + 1);
      const portMatch = rest.match(/^:(\d+)/);
      node.port = portMatch ? portMatch[1] : "";
      return;
    }
  }

  const portMatch = cleaned.match(/^(.*):(\d+)$/);
  if (portMatch) {
    node.host = portMatch[1];
    node.port = portMatch[2];
  } else {
    node.host = cleaned;
  }
}

function parseSsUserInfo(userInfo) {
  let decoded = decodeBase64(userInfo);
  if (!decoded || !decoded.includes(":")) {
    decoded = decodeSafe(userInfo);
  }
  const colon = decoded.indexOf(":");
  return {
    method: colon === -1 ? decoded : decoded.slice(0, colon),
    password: colon === -1 ? "" : decoded.slice(colon + 1)
  };
}

function detectProtocol(node) {
  const q = node.query || {};
  const type = (q.type || "").toLowerCase();
  const security = (q.security || "").toLowerCase();
  const flow = (q.flow || "").toLowerCase();
  const encryption = (q.encryption || "").toLowerCase();

  if (node.scheme === "vless") {
    const labelParts = ["VLESS"];
    if (type) {
      labelParts.push(type.toUpperCase());
    }
    if (security === "reality") {
      labelParts.push("Reality");
    } else if (security === "tls") {
      labelParts.push("TLS");
    }
    if (flow.includes("vision")) {
      labelParts.push("Vision");
    }
    if (encryption && encryption !== "none") {
      labelParts.push("ENC");
    }
    node.protocolLabel = labelParts.join(" ");
    node.protocolCode = type ? type.toUpperCase() : "VLESS";
    if (encryption && encryption !== "none") {
      node.protocolCode += "-ENC";
    }
    return;
  }

  if (node.scheme === "ss") {
    const is2022 = /2022|blake3/i.test(node.method || node.rawName || "");
    node.protocolLabel = is2022 ? "Shadowsocks-2022" : "Shadowsocks";
    node.protocolCode = "SS";
    return;
  }

  if (node.scheme === "anytls") {
    node.protocolLabel = "AnyTLS";
    node.protocolCode = "AnyTLS";
    return;
  }

  if (node.scheme === "hysteria2" || node.scheme === "hy2") {
    node.protocolLabel = "Hysteria2";
    node.protocolCode = "HY2";
    return;
  }

  if (node.scheme === "tuic") {
    node.protocolLabel = "TUIC";
    node.protocolCode = "TUIC";
    return;
  }

  if (node.scheme === "vmess") {
    const label = type ? "VMess " + type.toUpperCase() : "VMess";
    node.protocolLabel = label;
    node.protocolCode = "VMess";
    return;
  }

  if (node.scheme === "socks" || node.scheme === "socks5") {
    node.protocolLabel = "Socks5";
    node.protocolCode = "Socks";
    return;
  }

  if (node.scheme === "http") {
    node.protocolLabel = "HTTP";
    node.protocolCode = "HTTP";
    return;
  }

  if (node.scheme === "hysteria") {
    node.protocolLabel = "Hysteria";
    node.protocolCode = "HY";
    return;
  }

  if (node.scheme === "snell") {
    node.protocolLabel = "Snell";
    node.protocolCode = "Snell";
    return;
  }

  if (node.scheme === "wireguard") {
    node.protocolLabel = "WireGuard";
    node.protocolCode = "WG";
    return;
  }

  if (node.scheme === "ssh") {
    node.protocolLabel = "SSH";
    node.protocolCode = "SSH";
    return;
  }

  if (node.scheme === "mieru") {
    node.protocolLabel = "Mieru";
    node.protocolCode = "Mieru";
    return;
  }

  if (node.scheme === "trojan") {
    node.protocolLabel = "Trojan";
    node.protocolCode = "Trojan";
    return;
  }

  node.protocolLabel = node.scheme.toUpperCase();
  node.protocolCode = node.scheme.toUpperCase();
}

function inferVpsName(node) {
  const original = cleanNodeNameForVps(normalizeNodeName(node.rawName), node);
  if (original) {
    for (const pattern of STRIP_NAME_PATTERNS) {
      const stripped = cleanNodeNameForVps(original.replace(pattern, "").replace(/^[-_\s|]+/, "").trim(), node);
      if (stripped && stripped !== original && !looksLikeProtocolOnly(stripped)) {
        return stripped;
      }
    }
    if (!looksLikeProtocolOnly(original)) {
      return original;
    }
  }

  if (node.host) {
    return node.host;
  }
  return "VPS-" + (Number(node.id.replace("node-", "")) + 1);
}

function cleanNodeNameForVps(name, node) {
  let out = String(name || "").trim();
  if (!out) return out;

  let changed = true;
  while (changed) {
    const before = out;
    out = stripProtocolSuffix(out, node);
    out = stripCustomNameNoise(out);
    out = stripProtocolSuffix(out, node);
    changed = before !== out;
  }

  return out;
}

function normalizeNodeName(name) {
  return decodeSafe(name || "")
    .replace(/^(?:(?:\uD83C[\uDDE6-\uDDFF]){2}\s*)+/, "")
    .replace(/\+/g, " ")
    .replace(/%20/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function stripProtocolSuffix(name, node) {
  let out = String(name || "").trim();
  if (!out) return out;

  const protocolWords = getProtocolSuffixWords(node);
  let changed = true;
  while (changed) {
    changed = false;
    const tokenMatch = out.match(/(^|[-_\s|]+)([A-Za-z0-9]+)$/);
    if (!tokenMatch) break;

    const token = tokenMatch[2].toUpperCase();
    if (!shouldStripProtocolToken(out, tokenMatch, token, protocolWords)) break;

    const next = out.slice(0, out.length - tokenMatch[0].length).replace(/[-_\s|]+$/, "").trim();
    if (next && next !== out) {
      out = next;
      changed = true;
    }
  }

  return out;
}

function stripCustomNameNoise(name) {
  let out = String(name || "").trim();
  if (!out) return out;

  const cleaners = getCustomNameCleaners();
  if (!cleaners.length) return out;

  let changed = true;
  while (changed) {
    changed = false;
    for (const cleaner of cleaners) {
      const next = out
        .replace(cleaner.prefix, "")
        .replace(cleaner.suffix, "")
        .replace(/^[-_\s|]+|[-_\s|]+$/g, "")
        .trim();
      if (next && next !== out) {
        out = next;
        changed = true;
      }
    }
  }

  return out;
}

function getCustomNameCleaners() {
  const input = $("nameCleanWords").value || "";
  return input
    .split(/[\n,，;；]+/)
    .map(item => item.trim())
    .filter(Boolean)
    .map(makeNameCleanerPattern);
}

function makeNameCleanerPattern(value) {
  const parts = String(value)
    .trim()
    .split(/[-_\s|]+/)
    .filter(Boolean)
    .map(escapeRegExp);
  const body = parts.length ? parts.join("[-_\\s|]+") : escapeRegExp(value);
  return {
    prefix: new RegExp("^(?:" + body + ")(?:[-_\\s|]+|$)", "i"),
    suffix: new RegExp("(?:^|[-_\\s|]+)(?:" + body + ")$", "i")
  };
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function getProtocolSuffixWords(node) {
  const words = new Set(PROTOCOL_SUFFIX_WORDS);
  [
    node.protocolCode,
    node.protocolLabel,
    node.scheme,
    (node.query && node.query.type) || ""
  ].filter(Boolean).forEach(value => {
    String(value).split(/[-_\s|]+/).forEach(part => {
      const word = part.trim().toUpperCase();
      if (word) words.add(word);
    });
  });
  if (node.query && node.query.encryption && node.query.encryption !== "none") {
    words.add("ENC");
  }
  return words;
}

function shouldStripProtocolToken(value, tokenMatch, token, protocolWords) {
  if (protocolWords.has(token)) return true;
  if (token !== "2022") return false;

  const before = value.slice(0, value.length - tokenMatch[0].length).replace(/[-_\s|]+$/, "");
  const previous = before.match(/([A-Za-z0-9]+)$/);
  return Boolean(previous && /^(SS|SHADOWSOCKS)$/i.test(previous[1]));
}

function looksLikeProtocolOnly(value) {
  const v = value.toLowerCase().replace(/[-_\s|]+/g, "");
  return [
    "vless",
    "vl",
    "vlessxhttp",
    "vlessreality",
    "shadowsocks",
    "shadowsocks2022",
    "ss2022",
    "anytls",
    "hy2",
    "hysteria2",
    "tuic",
    "vmess",
    "socks",
    "socks5",
    "http",
    "hysteria",
    "snell",
    "wireguard",
    "wg",
    "ssh",
    "mieru"
  ].includes(v);
}

function getProtocolKey(node) {
  return node.protocolCode || node.protocolLabel || node.scheme.toUpperCase();
}

function resetProtocolFilter(nodes) {
  state.activeProtocols = new Set(nodes.map(getProtocolKey));
  renderProtocolFilter();
}

function setAllProtocols(checked) {
  if (checked) {
    state.activeProtocols = new Set(state.allNodes.map(getProtocolKey));
  } else {
    state.activeProtocols = new Set();
  }
  applyProtocolFilter({ silent: false });
}

function applyProtocolFilter(opts = {}) {
  state.nodes = state.allNodes.filter(node => state.activeProtocols.has(getProtocolKey(node)));
  buildGroups();
  refreshSuggestedNames(Boolean(opts.forceApply), { silent: true });
  renderProtocolFilter();

  if (!opts.silent) {
    const total = state.allNodes.length;
    const shown = state.nodes.length;
    if (!total) {
      setMessage("还没有可过滤的节点。", "warn");
    } else if (!shown) {
      setMessage("当前过滤条件下没有节点。", "warn");
    } else {
      setMessage("协议过滤后保留 " + shown + " / " + total + " 条节点。", "ok");
    }
  }
}

function renderProtocolFilter() {
  const root = $("protocolFilter");
  if (!root) return;
  const counts = {};
  for (const node of state.allNodes) {
    const key = getProtocolKey(node);
    counts[key] = (counts[key] || 0) + 1;
  }
  const protocols = Object.keys(counts).sort((a, b) => a.localeCompare(b));
  if (!protocols.length) {
    root.innerHTML = '<span class="note">清洗后自动生成协议列表。</span>';
    return;
  }

  root.innerHTML = protocols.map(protocol => `
    <label class="protocol-option">
      <input type="checkbox" data-protocol-filter="${escapeAttr(protocol)}" ${state.activeProtocols.has(protocol) ? "checked" : ""}>
      <span>${escapeHtml(protocol)} (${counts[protocol]})</span>
    </label>
  `).join("");

  root.querySelectorAll("[data-protocol-filter]").forEach(input => {
    input.addEventListener("change", () => {
      const protocol = input.dataset.protocolFilter;
      if (input.checked) {
        state.activeProtocols.add(protocol);
      } else {
        state.activeProtocols.delete(protocol);
      }
      applyProtocolFilter({ silent: false });
    });
  });
}

function buildGroups() {
  const map = new Map();
  for (const node of state.nodes) {
    const fallback = [node.host || "unknown", node.user || "", node.port || ""].join("|");
    const key = node.vpsCandidate || fallback;
    if (!map.has(key)) {
      map.set(key, {
        id: "group-" + map.size,
        key,
        name: state.groupNames[key] || node.vpsCandidate || node.host || "VPS-" + (map.size + 1),
        nodes: []
      });
    }
    const group = map.get(key);
    node.groupId = group.id;
    group.nodes.push(node);
  }

  const groups = Array.from(map.values());
  const keys = groups.map(group => group.key);
  if (keys.length) {
    state.groupOrder = state.groupOrder.filter(key => keys.includes(key));
    for (const key of keys) {
      if (!state.groupOrder.includes(key)) {
        state.groupOrder.push(key);
      }
    }
  }

  const orderIndex = new Map(state.groupOrder.map((key, index) => [key, index]));
  state.groups = groups.sort((a, b) => orderIndex.get(a.key) - orderIndex.get(b.key));
}

function getOrderedNodes() {
  return state.groups.flatMap(group => group.nodes);
}

function moveGroup(groupId, direction) {
  const visibleKeys = state.groups.map(group => group.key);
  const group = state.groups.find(item => item.id === groupId);
  if (!group) return;

  const visibleIndex = visibleKeys.indexOf(group.key);
  const targetKey = visibleKeys[visibleIndex + direction];
  if (!targetKey) return;

  const currentIndex = state.groupOrder.indexOf(group.key);
  const targetIndex = state.groupOrder.indexOf(targetKey);
  if (currentIndex === -1 || targetIndex === -1) return;

  [state.groupOrder[currentIndex], state.groupOrder[targetIndex]] = [state.groupOrder[targetIndex], state.groupOrder[currentIndex]];
  buildGroups();
  refreshSuggestedNames(false, { silent: true });
  setMessage("已调整 VPS 顺序，输出会按当前顺序排列。", "ok");
}

function refreshSuggestedNames(forceApply, opts = {}) {
  syncCountrySelectWithDetectedNodes();
  for (const group of state.groups) {
    const protocolTotals = group.nodes.reduce((acc, node) => {
      const key = node.protocolCode || node.protocolLabel || node.scheme.toUpperCase();
      acc[key] = (acc[key] || 0) + 1;
      return acc;
    }, {});
    const protocolSeen = {};
    for (const node of group.nodes) {
      const key = node.protocolCode || node.protocolLabel || node.scheme.toUpperCase();
      protocolSeen[key] = (protocolSeen[key] || 0) + 1;
      node.nameProtocol = NodeProcessor.formatProtocolForName(key, protocolTotals[key] > 1 ? (node.port || protocolSeen[key]) : "");
      node.suggestedName = NodeProcessor.makeSuggestedName(node, group.name);
      if (forceApply || !$("keepManual").checked || !node.manual) {
        node.customName = node.suggestedName;
        node.manual = false;
      }
      if (!node.forwardManual) {
        node.forwardName = NodeProcessor.makeForwardName(node, group.name);
      }
    }
  }
  renderGroups();
  renderOutput();
  updateMetrics();
  if (!opts.silent && state.nodes.length) {
    setMessage(forceApply ? "已全部采用推荐名称。" : "已刷新推荐名称。", "ok");
  }
}

function makeSuggestedName(node, groupName) {
  const flag = getNodeFlag(node);
  const vps = (groupName || node.vpsCandidate || node.host || "VPS").trim();
  const proto = node.nameProtocol || node.protocolCode || node.protocolLabel || node.scheme.toUpperCase();
  const template = $("nameTemplate").value.trim() || "{国家} {VPS}_{协议}";
  return applyNameTemplate(template, {
    flag,
    vps,
    proto
  });
}

function getNodeFlag(node) {
  const manualFlag = $("countryEmoji").value.trim();
  if (manualFlag) return manualFlag;
  if ($("autoDetectCountry").checked && node && node.detectedFlag) return node.detectedFlag;
  if ($("countrySelect").value === "__mixed__") return "🌐";
  return ($("countrySelect").value || "🌐").trim();
}

function syncCountrySelectWithDetectedNodes() {
  const select = $("countrySelect");
  if (!select) return;
  if ($("countryEmoji").value.trim() || !$("autoDetectCountry").checked) {
    clearCountrySelectSummary();
    return;
  }

  const flags = Array.from(new Set(state.nodes.map(node => node.detectedFlag).filter(Boolean)));
  if (flags.length === 1) {
    const flag = flags[0];
    clearCountrySelectSummary();
    if (hasCountryOption(flag)) {
      select.value = flag;
    } else {
      setCountrySelectSummary(flag + " 已识别国家/地区", flag);
      select.value = flag;
    }
    return;
  }

  if (flags.length > 1) {
    setCountrySelectSummary("多个国家/地区（" + flags.join(" ") + "）", "__mixed__");
    select.value = "__mixed__";
    return;
  }

  clearCountrySelectSummary();
}

function hasCountryOption(value) {
  return Array.from($("countrySelect").options).some(option => option.value === value && option.dataset.autoSummary === undefined);
}

function setCountrySelectSummary(label, value) {
  const option = $("countrySelect").querySelector("[data-auto-summary]");
  if (!option) return;
  option.value = value;
  option.textContent = label;
  option.hidden = false;
  option.disabled = false;
}

function clearCountrySelectSummary() {
  const select = $("countrySelect");
  const option = select.querySelector("[data-auto-summary]");
  if (!option) return;
  const summaryValue = option.value;
  option.hidden = true;
  option.disabled = true;
  option.value = "__auto_country_summary__";
  if (select.value === summaryValue) {
    select.value = "🌐";
  }
}

function detectCountryFlag(text) {
  const name = decodeSafe(text || "");
  const emojiMatch = name.match(/(?:\uD83C[\uDDE6-\uDDFF]){2}/);
  if (emojiMatch) return emojiMatch[0];

  const tokens = name.toUpperCase().split(/[^A-Z0-9]+/).filter(Boolean);
  for (const token of tokens) {
    if (COUNTRY_FLAG_BY_CODE[token]) return COUNTRY_FLAG_BY_CODE[token];
  }

  const upperName = name.toUpperCase();
  for (const code of Object.keys(COUNTRY_FLAG_BY_CODE)) {
    const codePattern = new RegExp("(^|[^A-Z])" + code + "([^A-Z]|$)");
    if (codePattern.test(upperName)) return COUNTRY_FLAG_BY_CODE[code];
  }

  return "";
}

function formatProtocolForName(protocol, suffix = "") {
  const separator = getNameSeparator();
  const normalized = String(protocol || "")
    .split(/[-_\s]+/)
    .filter(Boolean)
    .join(separator);
  return suffix ? normalized + separator + suffix : normalized;
}

function getNameSeparator() {
  const template = $("nameTemplate").value || "";
  if (template.includes("_{协议}") || template.includes("_{proto}")) return "_";
  if (template.includes("-{协议}") || template.includes("-{proto}")) return "-";
  return " ";
}

function makeForwardName(node, groupName) {
  const finalName = node.customName || node.suggestedName || node.rawName || node.protocolCode || "节点";
  const template = $("forwardNameTemplate").value.trim() || "{国家} 转发_{VPS}_{协议}";
  const forward = getForwardConfig(node);
  const flag = getNodeFlag(node);
  return applyNameTemplate(template, {
    flag,
    vps: groupName || node.vpsCandidate || node.host || "VPS",
    proto: node.nameProtocol || node.protocolCode || node.protocolLabel || node.scheme.toUpperCase(),
    name: finalName,
    host: forward.host || "",
    port: forward.port || ""
  });
}

function applyNameTemplate(template, parts) {
  return String(template || "")
    .replace(/\{国家\}/g, parts.flag || "")
    .replace(/\{flag\}/g, parts.flag || "")
    .replace(/\{VPS\}/g, parts.vps || "")
    .replace(/\{vps\}/g, parts.vps || "")
    .replace(/\{协议\}/g, parts.proto || "")
    .replace(/\{proto\}/g, parts.proto || "")
    .replace(/\{原名\}/g, parts.name || "")
    .replace(/\{name\}/g, parts.name || "")
    .replace(/\{转发入口\}/g, parts.host || "")
    .replace(/\{host\}/g, parts.host || "")
    .replace(/\{转发端口\}/g, parts.port || "")
    .replace(/\{port\}/g, parts.port || "")
    .replace(/\s+/g, " ")
    .trim();
}

function refreshForwardNames(forceApply, opts = {}) {
  for (const group of state.groups) {
    for (const node of group.nodes) {
      if (forceApply || !node.forwardManual) {
        node.forwardName = NodeProcessor.makeForwardName(node, group.name);
        node.forwardManual = false;
      }
    }
  }
  renderGroups();
  renderOutput();
  if (!opts.silent && state.nodes.length) {
    setMessage(forceApply ? "已全部刷新转发节点名。" : "已按模板刷新未手动修改的转发名。", "ok");
  }
}

function setAllForwardSelected(selected) {
  for (const node of state.allNodes) {
    if (canForwardNode(node)) {
      node.forwardSelected = selected;
    }
  }
  if (selected) {
    $("forwardEnabled").checked = true;
  }
  renderGroups();
  renderOutput();
  if (state.nodes.length) {
    setMessage(selected ? "已勾选全部可转发节点。" : "已取消全部转发节点。", "ok");
  }
}

function renderAll(message, type) {
  renderProtocolFilter();
  renderIgnoredPreview();
  renderGroups();
  renderOutput();
  updateMetrics();
  setMessage(message, type);
}

function renderIgnoredPreview() {
  const details = $("ignoredPreview");
  const pre = $("ignoredLines");
  if (!details || !pre) return;

  const issues = state.parseIssues || [];
  details.hidden = !issues.length;
  if (!issues.length) {
    pre.textContent = "";
    return;
  }

  const limit = 120;
  const shown = issues.slice(0, limit).map(formatParseIssue);
  const summary = details.querySelector("summary");
  if (summary) {
    const errors = issues.filter(item => item.level === "error").length;
    const skipped = issues.filter(item => item.level === "skip").length;
    const info = issues.filter(item => item.level === "info").length;
    summary.textContent = "查看解析详情（错误 " + errors + "，跳过 " + skipped + "，清理 " + info + "）";
  }
  pre.textContent = shown.join("\n") + (issues.length > limit ? "\n... 还有 " + (issues.length - limit) + " 条未显示" : "");
}

function formatParseIssue(issue) {
  const prefix = issue.level === "error" ? "错误" : issue.level === "skip" ? "跳过" : "清理";
  return "[" + prefix + "] " + formatIssueLine(issue.lineStart, issue.reason, compactIssueText(issue.text), issue.lineEnd);
}

function compactIssueText(text) {
  const value = String(text || "").replace(/\s+/g, " ").trim();
  return value.length > 180 ? value.slice(0, 150) + "..." + value.slice(-24) : value;
}

function runSelfTests() {
  const output = $("selfTestOutput");
  const tests = getSelfTests();
  const results = [];

  for (const test of tests) {
    try {
      test.run();
      results.push({ ok: true, name: test.name, detail: test.detail || "通过" });
    } catch (err) {
      results.push({ ok: false, name: test.name, detail: err.message || String(err) });
    }
  }

  const passed = results.filter(item => item.ok).length;
  const failed = results.length - passed;
  output.textContent = [
    "通过：" + passed,
    "失败：" + failed,
    "",
    ...results.map(item => (item.ok ? "[PASS] " : "[FAIL] ") + item.name + "： " + item.detail)
  ].join("\n");
  setMessage(failed ? "自测发现 " + failed + " 个问题。" : "自测通过。", failed ? "err" : "ok");
}

function getSelfTests() {
  return [
    {
      name: "URL/URI 列表",
      run() {
        const result = selfTestParse("ss://aes-128-gcm:pwd@198.51.100.10:9443#US-SS\nvless://00000000-0000-4000-8000-000000000000@198.51.100.10:443?encryption=none&type=ws&security=tls&sni=example.com#US-VL-WS");
        assertSelfTest(result.nodes.length === 2, "应解析 2 条节点，实际 " + result.nodes.length);
        assertSelfTest(result.nodes[0].scheme === "ss" && result.nodes[1].scheme === "vless", "协议识别不正确");
      }
    },
    {
      name: "脚本杂质清洗",
      run() {
        const result = selfTestParse("说明文字\n\n💣【 Shadowsocks-2022 】节点信息如下：\nss://aes-128-gcm:pwd@198.51.100.10:9443#US-SS\n命令输出");
        assertSelfTest(result.nodes.length === 1, "应解析 1 条节点，实际 " + result.nodes.length);
        assertSelfTest(result.issues.some(item => item.reason === "非节点行"), "应记录非节点行");
      }
    },
    {
      name: "Clash 单行 JSON",
      run() {
        const result = selfTestParse('proxies:\n  - {"name":"US PO0-GA-ATT","type":"ss","server":"198.51.100.10","port":40651,"cipher":"aes-128-gcm","password":"p","udp":true}');
        assertSelfTest(result.nodes.length === 1, "应解析 1 条 Clash JSON 节点");
        const output = NodeProducer.render(result.nodes, NodeProducer.buildRecords(result.nodes, "renamed"), "auto");
        assertSelfTest(/^\s*proxies:\n\s*- \{/.test(output), "应输出 proxies YAML");
      }
    },
    {
      name: "Clash 多行 YAML",
      run() {
        const result = selfTestParse("proxies:\n  - name: US PO0-VLESS-WS\n    type: vless\n    server: edge.example.com\n    port: 443\n    uuid: 00000000-0000-4000-8000-000000000000\n    network: ws\n    tls: true\n    ws-opts:\n      path: /ray\n      headers:\n        Host: cdn.example.com");
        assertSelfTest(result.nodes.length === 1, "应解析 1 条 Clash YAML 节点");
        const output = NodeProducer.render(result.nodes, NodeProducer.buildRecords(result.nodes, "renamed"), "clash");
        assertSelfTest(output.includes('"ws-opts":{"path":"/ray","headers":{"Host":"cdn.example.com"}}'), "应保留嵌套 ws-opts");
      }
    },
    {
      name: "Clash 多行 YAML 输出",
      run() {
        const result = selfTestParse('proxies:\n  - {"name":"US PO0-GA-ATT","type":"ss","server":"198.51.100.10","port":40651,"cipher":"aes-128-gcm","password":"p","udp":true}');
        const previous = $("clashStyle").value;
        $("clashStyle").value = "yaml";
        const produced = NodeProducer.produce(result.nodes, NodeProducer.buildRecords(result.nodes, "renamed"), "clash");
        const output = produced.text;
        $("clashStyle").value = previous;
        assertSelfTest(output.includes("\n  - name:"), "应输出多行 YAML");
        assertSelfTest(output.includes("\n    type: ss"), "YAML 应包含 type 字段");
        assertSelfTest(produced.emitted === 1, "多行 YAML 成功数应按节点计数");
      }
    },
    {
      name: "Base64 URL/URI 订阅",
      run() {
        const raw = "ss://aes-128-gcm:pwd@198.51.100.10:9443#US-SS\nvless://u@198.51.100.10:443?encryption=none&type=ws#US-VL";
        const result = selfTestParse(base64Encode(raw));
        assertSelfTest(result.nodes.length === 2, "应解析 Base64 内的 2 条节点");
        assertSelfTest(result.issues.some(item => item.reason.includes("Base64")), "应记录 Base64 解码详情");
      }
    },
    {
      name: "输出格式转换",
      run() {
        const result = selfTestParse("ss://aes-128-gcm:pwd@198.51.100.10:9443#US-SS");
        const clash = NodeProducer.render(result.nodes, NodeProducer.buildRecords(result.nodes, "renamed"), "clash");
        const uri = NodeProducer.render(result.nodes, NodeProducer.buildRecords(result.nodes, "renamed"), "uri");
        assertSelfTest(clash.startsWith("proxies:\n  - {"), "URI 转 Clash 输出失败");
        assertSelfTest(uri.startsWith("ss://"), "URI 输出失败");
      }
    },
    {
      name: "输出详情报告",
      run() {
        const result = selfTestParse('proxies:\n  - {"name":"WG","type":"wireguard","server":"198.51.100.10","port":51820}');
        const produced = NodeProducer.produce(result.nodes, NodeProducer.buildRecords(result.nodes, "renamed"), "uri");
        assertSelfTest(produced.emitted === 0, "不支持 URI 的节点不应输出");
        assertSelfTest(produced.skipped === 1, "应记录 1 条跳过输出");
        assertSelfTest(produced.warnings[0].reason.includes("wireguard"), "应说明不支持的协议");
      }
    },
    {
      name: "直连入口 URI 转发",
      run() {
        const result = selfTestParse([
          "vless://00000000-0000-4000-8000-000000000000@198.51.100.11:443?encryption=none&type=ws&security=tls&sni=example.com#US-VLESS",
          "ssr://198.51.100.30:9448?method=aes-128-gcm&password=pwd#US-SSR"
        ].join("\n"));
        const ssrNode = result.nodes.find(node => node.scheme === "ssr");
        assertSelfTest(result.nodes.length === 2, "应解析 VLESS 和 SSR 两条节点");
        assertSelfTest(Boolean(ssrNode), "应存在 SSR 节点");
        assertSelfTest(canForwardNode(ssrNode), "直连入口 URI 节点应允许转发");
        const forwardedRaw = NodeProducer.rewriteEndpoint(ssrNode, "relay.example.com", "24443");
        assertSelfTest(forwardedRaw.includes("ssr://relay.example.com:24443?"), "直连入口 URI 应替换 host/port");
      }
    },
    {
      name: "协议覆盖增强",
      run() {
        const raw = [
          'proxies:',
          '  - {"name":"HTTP","type":"http","server":"198.51.100.10","port":8080}',
          '  - {"name":"SOCKS","type":"socks5","server":"198.51.100.10","port":1080}',
          '  - {"name":"WG","type":"wireguard","server":"198.51.100.10","port":51820}',
          '  - {"name":"SNELL","type":"snell","server":"198.51.100.10","port":440}',
          '  - {"name":"HY","type":"hysteria","server":"198.51.100.10","port":443}'
        ].join("\n");
        const result = selfTestParse(raw);
        assertSelfTest(result.nodes.length === 5, "应解析 5 条扩展协议节点，实际 " + result.nodes.length);
        const uri = NodeProducer.produce(result.nodes, NodeProducer.buildRecords(result.nodes, "renamed"), "uri");
        assertSelfTest(uri.emitted === 3, "HTTP/SOCKS/Hysteria 应可转 URI");
        assertSelfTest(uri.skipped === 2, "WireGuard/Snell 应报告无法转 URI");
      }
    },
    {
      name: "自定义节点名清理词表",
      run() {
        const previous = $("nameCleanWords").value;
        $("nameCleanWords").value = "RAW_ENC\nTX";
        const result = selfTestParse("vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443?encryption=none&type=raw#🇭🇰 PO0GZ_RFCHK_RAW_ENC");
        $("nameCleanWords").value = previous;
        assertSelfTest(result.nodes.length === 1, "应解析 1 条节点");
        assertSelfTest(result.nodes[0].vpsCandidate === "PO0GZ_RFCHK", "应按自定义词表清理 VPS 前缀，实际 " + result.nodes[0].vpsCandidate);
      }
    },
    {
      name: "Clash 扩展协议字段保留",
      run() {
        const raw = [
          'proxies:',
          '  - {"name":"WG","type":"wireguard","server":"198.51.100.10","port":51820,"private-key":"priv","public-key":"pub","ip":"10.0.0.2","reserved":[1,2,3],"udp":true}',
          '  - {"name":"SN","type":"snell","server":"198.51.100.10","port":440,"psk":"p","version":3,"obfs-opts":{"mode":"tls","host":"example.com"}}',
          '  - {"name":"TU","type":"tuic","server":"198.51.100.10","port":443,"uuid":"u","password":"p","congestion-controller":"bbr","alpn":["h3"]}',
          '  - {"name":"HY2","type":"hysteria2","server":"198.51.100.10","port":443,"password":"p","sni":"example.com","ports":"443 8443:8444"}'
        ].join("\n");
        const result = selfTestParse(raw);
        const output = NodeProducer.render(result.nodes, NodeProducer.buildRecords(result.nodes, "renamed"), "clash");
        assertSelfTest(output.includes('"private-key":"priv"') && output.includes('"reserved":[1,2,3]'), "WireGuard 字段应保留");
        assertSelfTest(output.includes('"obfs-opts":{"mode":"tls","host":"example.com"}'), "Snell 嵌套字段应保留");
        assertSelfTest(output.includes('"congestion-controller":"bbr"') && output.includes('"alpn":["h3"]'), "TUIC 字段应保留");
        assertSelfTest(output.includes('"ports":"443 8443:8444"'), "Hysteria2 字段应保留");
      }
    },
    {
      name: "URI 扩展协议转 Clash",
      run() {
        const raw = [
          "wireguard://priv@198.51.100.10:51820?public-key=pub&ip=10.0.0.2&mtu=1280&udp=true#WG",
          "snell://psk@198.51.100.10:440?version=3&obfs=tls&host=example.com#SN",
          "tuic://uuid@198.51.100.10:443?password=p&sni=example.com&congestion-controller=bbr&alpn=h3#TU",
          "hysteria2://pass@198.51.100.10:443?alpn=h3&sni=example.com&insecure=1#HY2"
        ].join("\n");
        const result = selfTestParse(raw);
        const output = NodeProducer.render(result.nodes, NodeProducer.buildRecords(result.nodes, "renamed"), "clash");
        assertSelfTest(output.includes('"private-key":"priv"') && output.includes('"public-key":"pub"') && output.includes('"mtu":1280'), "WireGuard URI 字段应转入 Clash");
        assertSelfTest(output.includes('"psk":"psk"') && output.includes('"version":3') && output.includes('"obfs-opts":{"mode":"tls","host":"example.com"}'), "Snell URI 字段应转入 Clash");
        assertSelfTest(output.includes('"congestion-controller":"bbr"') && output.includes('"alpn":["h3"]'), "TUIC URI 字段应转入 Clash");
        assertSelfTest(output.includes('"skip-cert-verify":true'), "Hysteria2 insecure 应转为 skip-cert-verify");
      }
    },
    {
      name: "Clash 批量属性",
      run() {
        const result = selfTestParse("ss://aes-128-gcm:pwd@198.51.100.10:9443#US-SS");
        const previous = {
          udp: $("clashUdp").value,
          skipCert: $("clashSkipCert").value,
          fingerprint: $("clashFingerprint").value,
          servername: $("clashServername").value
        };
        $("clashUdp").value = "true";
        $("clashSkipCert").value = "true";
        $("clashFingerprint").value = "chrome";
        $("clashServername").value = "example.com";
        const clash = NodeProducer.render(result.nodes, NodeProducer.buildRecords(result.nodes, "renamed"), "clash");
        const uri = NodeProducer.render(result.nodes, NodeProducer.buildRecords(result.nodes, "renamed"), "uri");
        $("clashUdp").value = previous.udp;
        $("clashSkipCert").value = previous.skipCert;
        $("clashFingerprint").value = previous.fingerprint;
        $("clashServername").value = previous.servername;
        assertSelfTest(clash.includes('"udp":true'), "应写入 udp");
        assertSelfTest(clash.includes('"skip-cert-verify":true'), "应写入 skip-cert-verify");
        assertSelfTest(clash.includes('"client-fingerprint":"chrome"'), "应写入 client-fingerprint");
        assertSelfTest(clash.includes('"servername":"example.com"'), "应写入 servername");
        assertSelfTest(!uri.includes("client-fingerprint"), "URI 输出不应带 Clash 属性");
      }
    },
    {
      name: "解析错误报告",
      run() {
        const result = selfTestParse("note\nss://aes-128-gcm:pwd@198.51.100.10:9443#A\nss://aes-128-gcm:pwd@198.51.100.10:9443#B\nvmess://bad-base64\nproxies:\n  - name: Broken\n    type: ss\n    server: 198.51.100.10");
        assertSelfTest(result.nodes.length === 1, "应只保留 1 条有效节点");
        assertSelfTest(result.duplicateCount === 1, "应记录 1 条重复节点");
        assertSelfTest(result.invalidCount === 1, "应记录 1 条解析失败节点");
        assertSelfTest(result.issues.some(item => item.reason.includes("Clash YAML")), "应记录坏 Clash YAML");
        assertSelfTest(result.issues.some(item => item.reason.includes("VMess")), "应记录坏 VMess");
      }
    },
    {
      name: "节点二维码",
      run() {
        assertSelfTest(Boolean(window.ProxyNodeQr), "二维码模块应已加载");
        const qr = window.ProxyNodeQr.encode("ss://aes-128-gcm:pwd@198.51.100.10:9443#US-SS");
        assertSelfTest(qr.version >= 1 && qr.version <= 40, "二维码版本应在 1-40 范围内");
        assertSelfTest(qr.size === qr.version * 4 + 17, "二维码矩阵尺寸不正确");
        assertSelfTest(qr.modules.some(row => row.some(Boolean)), "二维码矩阵不应为空");
        const candidate = getFirstQrCandidate("说明\nss://aes-128-gcm:pwd@198.51.100.10:9443#A\nss://aes-128-gcm:pwd@198.51.100.11:9443#B");
        assertSelfTest(candidate.text.endsWith("#A") && candidate.count === 2, "多行输入应提取第一条节点");
      }
    }
  ];
}

function selfTestParse(raw) {
  const extracted = NodeParser.extract(raw);
  let items = extracted.items || [];
  const issues = [...(extracted.issues || [])];
  let duplicateCount = 0;

  const deduped = [];
  const seen = new Set();
  for (const item of items) {
    const key = item.raw.replace(/#.*$/, "");
    if (seen.has(key)) {
      duplicateCount++;
      issues.push({
        level: "skip",
        lineStart: item.lineStart,
        lineEnd: item.lineEnd,
        reason: "重复节点",
        text: item.raw
      });
      continue;
    }
    seen.add(key);
    deduped.push(item);
  }
  items = deduped;

  const nodes = [];
  let invalidCount = 0;
  items.forEach((item, index) => {
    const parsed = NodeParser.parse(item.raw, index);
    if (!parsed.valid) {
      invalidCount++;
      issues.push({
        level: "error",
        lineStart: item.lineStart,
        lineEnd: item.lineEnd,
        reason: parsed.error || "节点解析失败",
        text: item.raw
      });
      return;
    }
    parsed.lineStart = item.lineStart;
    parsed.lineEnd = item.lineEnd;
    parsed.source = item.source;
    nodes.push(parsed);
  });

  state.clashProxyHeader = extracted.clashProxyHeader || "";
  buildSelfTestNames(nodes);

  return {
    nodes,
    issues,
    duplicateCount,
    invalidCount,
    clashProxyHeader: extracted.clashProxyHeader || ""
  };
}

function buildSelfTestNames(nodes) {
  const groups = new Map();
  for (const node of nodes) {
    const key = node.groupId || node.vpsCandidate || node.host || node.id;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(node);
  }

  for (const groupNodes of groups.values()) {
    const protocolTotals = groupNodes.reduce((acc, node) => {
      const key = node.protocolCode || node.protocolLabel || node.scheme.toUpperCase();
      acc[key] = (acc[key] || 0) + 1;
      return acc;
    }, {});
    const protocolSeen = {};
    for (const node of groupNodes) {
      const key = node.protocolCode || node.protocolLabel || node.scheme.toUpperCase();
      protocolSeen[key] = (protocolSeen[key] || 0) + 1;
      node.nameProtocol = NodeProcessor.formatProtocolForName(key, protocolTotals[key] > 1 ? (node.port || protocolSeen[key]) : "");
      node.suggestedName = NodeProcessor.makeSuggestedName(node, node.vpsCandidate);
      node.customName = node.suggestedName;
    }
  }
}

function assertSelfTest(condition, message) {
  if (!condition) throw new Error(message);
}

function makeNodeDetailText(node, group) {
  const finalName = node.customName || node.suggestedName || node.rawName || node.protocolCode || "";
  const forward = getForwardConfig(node);
  const clashPatch = getClashBulkPatchSummary();
  const lines = [
    "识别结果",
    "- 来源：" + describeNodeSource(node),
    "- 行号：" + describeNodeLine(node),
    "- 协议：" + (node.protocolCode || node.protocolLabel || node.scheme.toUpperCase()),
    "- 协议详情：" + (node.protocolLabel || "-"),
    "- 入口：" + ([node.host || "", node.port || ""].filter(Boolean).join(":") || "-"),
    "- 国家：" + getNodeFlag(node) + "，来源：" + describeCountrySource(node),
    "- VPS 前缀：" + (group.name || node.vpsCandidate || "-") + "，来源：" + describeVpsSource(node),
    "- 原名称：" + (node.rawName || "-"),
    "- 推荐名称：" + (node.suggestedName || "-"),
    "- 最终名称：" + (finalName || "-"),
    "",
    "输出影响",
    "- 输出格式：" + getOutputFormatLabel(),
    "- Clash 批量属性：" + (clashPatch.length ? clashPatch.join(", ") : "未设置"),
    "- 转发副本：" + describeForwardEffect(node, forward),
    "",
    "原始节点",
    compactIssueText(node.raw)
  ];
  return lines.join("\n");
}

function describeNodeSource(node) {
  const source = node.source || node.sourceFormat || "uri";
  if (source === "clash-json") return "Clash JSON";
  if (source === "clash-yaml") return "Clash YAML";
  if (source === "clash") return "Clash";
  if (source === "uri") return "URL/URI";
  return source;
}

function describeNodeLine(node) {
  if (!node.lineStart) return "-";
  return describeLineRange(node.lineStart, node.lineEnd);
}

function describeCountrySource(node) {
  if ($("countryEmoji").value.trim()) return "自定义国家 emoji";
  if ($("autoDetectCountry").checked && node.detectedFlag) return "原节点名";
  return "国家/地区下拉框";
}

function describeVpsSource(node) {
  const raw = normalizeNodeName(node.rawName);
  if (!raw) return node.host ? "入口 host" : "自动编号";
  if (stripCustomNameNoise(raw) !== raw) return "自定义清理词表";
  if (raw !== node.vpsCandidate) return "原名称清理协议前缀/后缀";
  return "原名称";
}

function getOutputFormatLabel() {
  const select = $("outputFormat");
  return select.options[select.selectedIndex] ? select.options[select.selectedIndex].textContent : state.outputFormat;
}

function getClashBulkPatchSummary() {
  const values = [];
  if ($("clashUdp").value) values.push("udp=" + $("clashUdp").value);
  if ($("clashSkipCert").value) values.push("skip-cert-verify=" + $("clashSkipCert").value);
  if ($("clashFingerprint").value.trim()) values.push("client-fingerprint=" + $("clashFingerprint").value.trim());
  if ($("clashServername").value.trim()) values.push("servername/sni=" + $("clashServername").value.trim());
  return values;
}

function describeForwardEffect(node, forward) {
  if (!$("forwardEnabled").checked) return "未启用";
  if (!canForwardNode(node)) return "当前节点暂不支持";
  if (!node.forwardSelected) return "未选择";
  if (!forward.valid) return "已选择，但转发入口或端口无效";
  return "已启用 -> " + forward.host + ":" + forward.port + "，名称 " + (node.forwardName || NodeProcessor.makeForwardName(node, getGroupNameForNode(node)));
}

function renderGroups() {
  const root = $("groups");
  if (!state.groups.length) {
    root.innerHTML = '<div class="empty-state">暂无分析结果。</div>';
    return;
  }

  const heading = `
    <section class="section-heading">
      <h2>VPS 前缀与节点分组</h2>
      <p>清洗后按 VPS/主机特征分组，在这里调整 VPS 前缀、最终名称和节点二维码动作。</p>
    </section>
  `;

  root.innerHTML = heading + state.groups.map(group => {
    const perNodeForward = $("forwardMode").value === "per-node";
    const protocols = Array.from(new Set(group.nodes.map(n => n.protocolCode || n.protocolLabel))).filter(Boolean);
    const hosts = Array.from(new Set(group.nodes.map(n => n.host).filter(Boolean)));
    const rows = group.nodes.map(node => {
      const forwardable = canForwardNode(node);
      const qrReady = isQrShareLink(node.raw);
      const forwardQrLink = makeForwardQrLink(node);
      const forwardQrReady = Boolean(forwardQrLink);
      const expanded = state.expandedDetails.has(node.id);
      const detailColspan = 12;
      return `
        <tr>
          <td class="detail-cell">
            <button class="small ghost" data-node-detail="${node.id}">${expanded ? "收起" : "详情"}</button>
          </td>
          <td class="protocol">${escapeHtml(node.protocolLabel)}</td>
          <td class="host"><span class="cell-clip" title="${escapeAttr(node.host || "-")}">${escapeHtml(node.host || "-")}</span></td>
          <td class="port">${escapeHtml(node.port || "-")}</td>
          <td class="name"><span class="cell-clip" title="${escapeAttr(node.rawName || "-")}">${escapeHtml(node.rawName || "-")}</span></td>
          <td class="name"><span class="cell-clip" title="${escapeAttr(node.suggestedName || "")}">${escapeHtml(node.suggestedName || "")}</span></td>
          <td class="final-name-cell">
            <input class="name-input" data-node-name="${node.id}" value="${escapeAttr(node.customName || node.suggestedName || "")}">
          </td>
          <td class="forward-select-cell">
            <input type="checkbox" data-forward-select="${node.id}" ${node.forwardSelected && forwardable ? "checked" : ""} ${forwardable ? "" : "disabled"}>
          </td>
          <td class="forward-host-cell">
            <input data-forward-host="${node.id}" value="${escapeAttr(node.forwardHost || "")}" placeholder="${escapeAttr($("forwardHost").value.trim() || "入口")}" ${forwardable && perNodeForward ? "" : "disabled"}>
          </td>
          <td class="forward-port-cell">
            <input data-forward-port="${node.id}" value="${escapeAttr(node.forwardPort || "")}" placeholder="${escapeAttr($("forwardPort").value.trim() || "端口")}" ${forwardable && perNodeForward ? "" : "disabled"}>
          </td>
          <td class="forward-name-cell">
            <input class="name-input" data-forward-name="${node.id}" value="${escapeAttr(node.forwardName || NodeProcessor.makeForwardName(node, group.name))}" ${forwardable ? "" : "disabled placeholder=\"暂不支持\""}>
          </td>
          <td class="link">
            <div class="link-actions">
              <button class="small ghost qr-link-btn" data-qr-link="${node.id}" ${qrReady ? "" : "disabled title=\"当前行不是 URL/URI 节点链接\""}>原始</button>
              <button class="small ghost qr-link-btn" data-forward-qr-link="${node.id}" ${forwardQrReady ? "" : "disabled title=\"当前行还没有可生成二维码的转发节点链接\""}>转发</button>
            </div>
          </td>
        </tr>
        ${expanded ? '<tr class="node-detail-row"><td colspan="' + detailColspan + '"><pre class="node-detail">' + escapeHtml(makeNodeDetailText(node, group)) + '</pre></td></tr>' : ""}
      `;
    }).join("");

    return `
      <article class="group-panel" data-group="${group.id}">
        <div class="group-head">
          <div>
            <div class="group-title">
              <div>
                <label>VPS 前缀</label>
                <input data-group-name="${group.id}" value="${escapeAttr(group.name)}">
              </div>
              <div>
                <label>分组依据</label>
                <input readonly value="${escapeAttr(group.key)}">
              </div>
            </div>
            <div class="badges">
              <span class="badge">${group.nodes.length} 条节点</span>
              <span class="badge">${hosts.length || 0} 个入口</span>
              ${protocols.map(p => '<span class="badge protocol">' + escapeHtml(p) + '</span>').join("")}
            </div>
          </div>
          <div class="button-row group-tools">
            <button class="small" data-move-group="${group.id}" data-direction="-1">上移</button>
            <button class="small" data-move-group="${group.id}" data-direction="1">下移</button>
            <button class="small" data-apply-group="${group.id}">本组采用推荐</button>
          </div>
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>详情</th>
                <th>协议</th>
                <th>入口</th>
                <th>端口</th>
                <th>原名称</th>
                <th>推荐名称</th>
                <th>最终名称</th>
                <th>转发</th>
                <th>转发入口</th>
                <th>转发端口</th>
                <th>转发名称</th>
                <th>二维码</th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      </article>
    `;
  }).join("");

  root.querySelectorAll("[data-node-name]").forEach(input => {
    input.addEventListener("input", () => {
      const node = state.nodes.find(n => n.id === input.dataset.nodeName);
      if (!node) return;
      node.customName = input.value;
      node.manual = true;
      if (!node.forwardManual) {
        const group = state.groups.find(item => item.id === node.groupId);
        node.forwardName = NodeProcessor.makeForwardName(node, group ? group.name : node.vpsCandidate);
      }
      renderOutput();
    });
  });

  root.querySelectorAll("[data-node-detail]").forEach(button => {
    button.addEventListener("click", () => {
      const id = button.dataset.nodeDetail;
      if (state.expandedDetails.has(id)) {
        state.expandedDetails.delete(id);
      } else {
        state.expandedDetails.add(id);
      }
      renderGroups();
    });
  });

  root.querySelectorAll("[data-forward-select]").forEach(input => {
    input.addEventListener("change", () => {
      const node = state.nodes.find(n => n.id === input.dataset.forwardSelect);
      if (!node) return;
      node.forwardSelected = input.checked;
      if (input.checked) {
        $("forwardEnabled").checked = true;
      }
      syncForwardQrButton(root, node);
      renderOutput();
    });
  });

  root.querySelectorAll("[data-forward-host]").forEach(input => {
    input.addEventListener("input", () => {
      const node = state.nodes.find(n => n.id === input.dataset.forwardHost);
      if (!node) return;
      const portInput = root.querySelector('[data-forward-port="' + node.id + '"]');
      applyForwardEndpointInput(input, portInput);
      node.forwardHost = input.value.trim();
      if (portInput) {
        node.forwardPort = portInput.value.trim();
      }
      if (!node.forwardManual) {
        node.forwardName = NodeProcessor.makeForwardName(node, getGroupNameForNode(node));
      }
      syncForwardSelectionFromEndpoint(node);
      syncForwardSelectInput(root, node);
      syncForwardQrButton(root, node);
      renderOutput();
    });
  });

  root.querySelectorAll("[data-forward-port]").forEach(input => {
    input.addEventListener("input", () => {
      const node = state.nodes.find(n => n.id === input.dataset.forwardPort);
      if (!node) return;
      node.forwardPort = input.value.trim();
      if (!node.forwardManual) {
        node.forwardName = NodeProcessor.makeForwardName(node, getGroupNameForNode(node));
      }
      syncForwardSelectionFromEndpoint(node);
      syncForwardSelectInput(root, node);
      syncForwardQrButton(root, node);
      renderOutput();
    });
  });

  root.querySelectorAll("[data-forward-name]").forEach(input => {
    input.addEventListener("input", () => {
      const node = state.nodes.find(n => n.id === input.dataset.forwardName);
      if (!node) return;
      node.forwardName = input.value;
      node.forwardManual = true;
      syncForwardQrButton(root, node);
      renderOutput();
    });
  });

  root.querySelectorAll("[data-qr-link]").forEach(button => {
    button.addEventListener("click", () => {
      const node = state.nodes.find(n => n.id === button.dataset.qrLink);
      if (!node) return;
      setSingleNodeQrInput(node.raw, { open: true, message: "已载入该节点链接。" });
    });
  });

  root.querySelectorAll("[data-forward-qr-link]").forEach(button => {
    button.addEventListener("click", () => {
      const node = state.nodes.find(n => n.id === button.dataset.forwardQrLink);
      if (!node) return;
      const link = makeForwardQrLink(node);
      if (!link) {
        openSingleNodeQrDialog({ focusInput: false });
        setQrMessage("当前行还没有可生成二维码的转发节点链接。", "err");
        return;
      }
      setSingleNodeQrInput(link, { open: true, message: "已载入转发节点链接。" });
    });
  });

  root.querySelectorAll("[data-group-name]").forEach(input => {
    input.addEventListener("change", () => {
      const group = state.groups.find(g => g.id === input.dataset.groupName);
      if (!group) return;
      group.name = input.value.trim() || group.key;
      state.groupNames[group.key] = group.name;
      refreshSuggestedNames(false);
    });
  });

  root.querySelectorAll("[data-move-group]").forEach(button => {
    button.addEventListener("click", () => {
      moveGroup(button.dataset.moveGroup, Number(button.dataset.direction));
    });
  });

  root.querySelectorAll("[data-apply-group]").forEach(button => {
    button.addEventListener("click", () => {
      const group = state.groups.find(g => g.id === button.dataset.applyGroup);
      if (!group) return;
      for (const node of group.nodes) {
        node.customName = node.suggestedName;
        node.manual = false;
      }
      renderGroups();
      renderOutput();
      setMessage("本组已采用推荐名称。", "ok");
    });
  });
}

function renderOutput() {
  const out = $("output");
  if (!state.nodes.length) {
    out.textContent = "";
    renderOutputReport(null);
    return;
  }

  const nodes = getOrderedNodes();
  const records = NodeProducer.buildRecords(nodes, state.outputContent);
  const result = NodeProducer.produce(nodes, records, state.outputFormat);
  out.textContent = result.text;
  renderOutputReport(result);
}

function renderOutputReport(result) {
  const details = $("outputReport");
  const pre = $("outputReportText");
  if (!details || !pre) return;

  if (!result) {
    details.hidden = true;
    pre.textContent = "";
    return;
  }

  const hasWarnings = result.warnings && result.warnings.length;
  details.hidden = !hasWarnings;
  const summary = details.querySelector("summary");
  if (summary) {
    summary.textContent = "查看输出详情（成功 " + result.emitted + "，跳过 " + result.skipped + "）";
  }

  if (!hasWarnings) {
    pre.textContent = "";
    return;
  }

  pre.textContent = [
    "成功输出：" + result.emitted,
    "跳过输出：" + result.skipped,
    "",
    ...result.warnings.map(formatOutputWarning)
  ].join("\n");
}

function setSingleNodeQrInput(text, opts = {}) {
  $("singleNodeInput").value = String(text || "").trim();
  if (opts.open) {
    openSingleNodeQrDialog({ focusInput: false });
  }
  const generated = generateSingleNodeQr({ silentSuccess: Boolean(opts.message) });
  if (opts.message && generated) {
    setQrMessage(opts.message, "ok");
  }
}

function generateSingleNodeQr(opts = {}) {
  const candidate = getFirstQrCandidate($("singleNodeInput").value);
  if (!candidate.text) {
    clearQrCanvas();
    setQrMessage("请输入一条 URL/URI 节点链接。", "err");
    return false;
  }

  if (candidate.text !== $("singleNodeInput").value.trim()) {
    $("singleNodeInput").value = candidate.text;
  }

  try {
    if (!window.ProxyNodeQr) {
      throw new Error("二维码模块未加载。");
    }
    const qr = window.ProxyNodeQr.encode(candidate.text);
    window.ProxyNodeQr.drawToCanvas(qr, $("singleNodeQrCanvas"), { maxSize: 320 });
    $("singleNodeQrPreview").classList.add("has-qr");
    $("singleNodeQrMeta").textContent = [
      "QR version " + qr.version + "-" + qr.ecc,
      qr.size + " x " + qr.size,
      qr.byteLength + " bytes"
    ].join(" | ");
    state.singleNodeQrText = candidate.text;
    if (!opts.silentSuccess) {
      setQrMessage(candidate.count > 1 ? "已从多条内容中提取第一条并生成二维码。" : "二维码已生成。", "ok");
    }
    return true;
  } catch (err) {
    clearQrCanvas();
    setQrMessage(err.message || String(err), "err");
    return false;
  }
}

function getFirstQrCandidate(raw) {
  const text = String(raw || "").trim();
  if (!text) return { text: "", count: 0 };

  const extracted = NodeParser.extract(text);
  const uriItems = (extracted.items || []).filter(item => isQrShareLink(item.raw));
  if (uriItems.length) {
    return {
      text: uriItems[0].raw,
      count: uriItems.length
    };
  }

  const firstLine = text.split(/\r?\n/).map(line => line.trim()).filter(Boolean)[0] || "";
  return {
    text: isQrShareLink(firstLine) ? firstLine : "",
    count: isQrShareLink(firstLine) ? 1 : 0
  };
}

function isQrShareLink(value) {
  const text = String(value || "").trim().toLowerCase();
  return SHARE_SCHEMES.some(scheme => text.startsWith(scheme + "://"));
}

function clearSingleNodeQr(opts = {}) {
  $("singleNodeInput").value = "";
  state.singleNodeQrText = "";
  clearQrCanvas();
  $("singleNodeQrMeta").textContent = "未生成";
  if (!opts.silent) {
    setQrMessage("等待节点链接。", "");
  }
}

function clearQrCanvas() {
  const canvas = $("singleNodeQrCanvas");
  const ctx = canvas.getContext("2d");
  canvas.width = 320;
  canvas.height = 320;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  $("singleNodeQrPreview").classList.remove("has-qr");
  state.singleNodeQrText = "";
}

function copySingleNodeQrLink() {
  const candidate = state.singleNodeQrText || getFirstQrCandidate($("singleNodeInput").value).text;
  if (!candidate) {
    setQrMessage("没有可复制的节点链接。", "err");
    return;
  }
  copyText(candidate, "已复制节点链接。");
}

function downloadSingleNodeQrPng() {
  if (!state.singleNodeQrText && !generateSingleNodeQr()) return;
  const canvas = $("singleNodeQrCanvas");
  const a = document.createElement("a");
  const ts = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
  a.href = canvas.toDataURL("image/png");
  a.download = "proxy-node-qr-" + ts + ".png";
  a.click();
  setQrMessage("二维码 PNG 已生成下载。", "ok");
}

function setQrMessage(message, type = "") {
  const box = $("singleNodeQrMessage");
  box.className = "message qr-message" + (type ? " " + type : "");
  box.textContent = message || "";
}

function openSingleNodeQrDialog(opts = {}) {
  const dialog = $("singleNodeQrDialog");
  dialog.hidden = false;
  if (opts.focusInput !== false) {
    $("singleNodeInput").focus();
  }
}

function closeSingleNodeQrDialog() {
  $("singleNodeQrDialog").hidden = true;
}

function formatOutputWarning(warning) {
  const line = warning.lineStart ? describeLineRange(warning.lineStart, warning.lineEnd) + "：" : "";
  const proto = warning.protocol ? " [" + warning.protocol + "]" : "";
  return "- " + line + warning.name + proto + " | " + warning.reason;
}

function describeLineRange(lineStart, lineEnd) {
  return lineEnd && lineEnd !== lineStart ? "第 " + lineStart + "-" + lineEnd + " 行" : "第 " + lineStart + " 行";
}

function formatOutputLines(nodes, lines) {
  if (state.clashProxyHeader && nodes.length && nodes.every(node => node.sourceFormat === "clash")) {
    return [state.clashProxyHeader, ...lines];
  }
  return lines;
}

function buildOutputRecords(nodes, contentMode) {
  const renamed = contentMode !== "clean";
  const forwardMode = renamed ? state.forwardOutputMode : "original-only";
  const records = [];
  const forwardWarnings = [];
  for (const node of nodes) {
    const name = renamed ? (node.customName || node.suggestedName || node.rawName || node.protocolCode) : (node.rawName || node.protocolCode);
    const originalRecord = {
      node,
      raw: renamed ? NodeProducer.rewriteName(node.raw, name) : node.raw,
      name,
      isForward: false
    };

    if (!renamed || forwardMode === "original-only") {
      records.push(originalRecord);
      continue;
    }

    if (forwardMode !== "forward-only") {
      records.push(originalRecord);
    }

    const forward = getForwardConfig(node);
    const skipReason = getForwardSkipReason(node, forward);
    if (skipReason) {
      if (node.forwardSelected || (forward.host || forward.port)) {
        forwardWarnings.push(makeOutputWarning(originalRecord, skipReason));
      }
      continue;
    }

    const forwardedRaw = NodeProducer.rewriteEndpoint(node, forward.host, forward.port);
    if (forwardedRaw === node.raw) {
      forwardWarnings.push(makeOutputWarning(originalRecord, "转发入口已填写，但当前节点无法改写入口"));
      continue;
    }

    const forwardName = node.forwardName || NodeProcessor.makeForwardName(node, getGroupNameForNode(node));
    records.push({
      node,
      raw: NodeProducer.rewriteName(forwardedRaw, forwardName),
      name: forwardName,
      isForward: true
    });
  }
  records.forwardWarnings = forwardWarnings;
  return records;
}

function produceOutputResult(nodes, records, format) {
  const warnings = [...((records && records.forwardWarnings) || [])];
  let lines = [];
  let text = "";
  let emitted = 0;

  if (format === "uri") {
    lines = records.map(record => produceUriRecord(record, warnings)).filter(Boolean);
    text = lines.join("\n");
    emitted = lines.length;
  } else if (format === "clash") {
    const clash = produceClashOutput(records, warnings);
    text = clash.text;
    lines = clash.lines;
    emitted = clash.emitted;
  } else if (format === "base64-uri") {
    lines = records.map(record => produceUriRecord(record, warnings)).filter(Boolean);
    text = base64Encode(lines.join("\n"));
    emitted = lines.length;
  } else {
    lines = records.map(record => record.raw);
    text = NodeProducer.formatLines(nodes, lines).join("\n");
    emitted = lines.length;
  }

  return {
    text,
    total: records.length,
    emitted,
    skipped: warnings.length,
    warnings,
    format
  };
}

function renderProducedOutput(nodes, records, format) {
  return produceOutputResult(nodes, records, format).text;
}

function buildRenamedOutputLines(nodes) {
  return buildOutputRecords(nodes, "renamed").map(record => record.raw);
}

function produceUriRecord(record, warnings = []) {
  if (!record || !record.raw) return "";
  if (/^[a-z0-9+.-]+:\/\//i.test(record.raw)) return record.raw;

  const proxy = getClashProxyFromRaw(record.raw);
  if (!proxy) {
    warnings.push(makeOutputWarning(record, "无法读取 Clash proxy，不能转为 URL/URI"));
    return "";
  }
  const uri = clashProxyToUri(proxy, record.name);
  if (!uri) {
    warnings.push(makeOutputWarning(record, "暂不支持将 " + (proxy.type || "未知协议") + " 转为 URL/URI"));
  }
  return uri;
}

function produceClashOutput(records, warnings = []) {
  const lines = ["proxies:"];
  let emitted = 0;
  for (const record of records) {
    const parsedUriNode = /^[a-z0-9+.-]+:\/\//i.test(record.raw) ? NodeParser.parse(record.raw, 0) : null;
    const proxy = getClashProxyFromRaw(record.raw) || nodeToClashProxy(parsedUriNode && parsedUriNode.valid ? parsedUriNode : record.node, record.name);
    if (!proxy) {
      warnings.push(makeOutputWarning(record, "暂不支持将该节点转为 Clash proxy"));
      continue;
    }
    if (record.name) proxy.name = record.name;
    applyClashBulkPatch(proxy);
    lines.push(formatClashProxy(proxy));
    emitted++;
  }
  return {
    text: lines.join("\n"),
    lines: lines.slice(1),
    emitted
  };
}

function formatClashProxy(proxy) {
  return $("clashStyle").value === "yaml" ? formatClashProxyYaml(proxy) : "  - " + JSON.stringify(proxy);
}

function formatClashProxyYaml(proxy) {
  const lines = [];
  writeYamlValue(lines, 2, "-", proxy);
  return lines.join("\n");
}

function writeYamlValue(lines, indent, key, value) {
  const pad = " ".repeat(indent);
  if (Array.isArray(value)) {
    lines.push(pad + key + ":");
    value.forEach(item => writeYamlListItem(lines, indent + 2, item));
    return;
  }
  if (value && typeof value === "object") {
    if (key === "-") {
      const entries = Object.entries(value);
      if (!entries.length) {
        lines.push(pad + "- {}");
        return;
      }
      const [firstKey, firstValue] = entries[0];
      if (firstValue && typeof firstValue === "object") {
        lines.push(pad + "- " + firstKey + ":");
        writeYamlNestedValue(lines, indent + 4, firstValue);
      } else {
        lines.push(pad + "- " + firstKey + ": " + formatYamlScalar(firstValue));
      }
      entries.slice(1).forEach(([childKey, childValue]) => writeYamlValue(lines, indent + 2, childKey, childValue));
      return;
    }
    lines.push(pad + key + ":");
    writeYamlNestedValue(lines, indent + 2, value);
    return;
  }
  lines.push(pad + key + ": " + formatYamlScalar(value));
}

function writeYamlNestedValue(lines, indent, value) {
  if (Array.isArray(value)) {
    value.forEach(item => writeYamlListItem(lines, indent, item));
    return;
  }
  if (value && typeof value === "object") {
    Object.entries(value).forEach(([key, childValue]) => writeYamlValue(lines, indent, key, childValue));
    return;
  }
  lines.push(" ".repeat(indent) + formatYamlScalar(value));
}

function writeYamlListItem(lines, indent, value) {
  const pad = " ".repeat(indent);
  if (value && typeof value === "object") {
    writeYamlValue(lines, indent, "-", value);
  } else {
    lines.push(pad + "- " + formatYamlScalar(value));
  }
}

function formatYamlScalar(value) {
  if (value === null) return "null";
  if (typeof value === "boolean" || typeof value === "number") return String(value);
  const text = String(value ?? "");
  if (!text || /[:#{}\[\],&*?|\-<>=!%@`]|^\s|\s$|\n|^(?:true|false|null|yes|no|on|off)$/i.test(text)) {
    return JSON.stringify(text);
  }
  return text;
}

function makeOutputWarning(record, reason) {
  const node = record && record.node ? record.node : {};
  return {
    lineStart: node.lineStart || "",
    lineEnd: node.lineEnd || "",
    name: record && record.name ? record.name : node.rawName || node.protocolCode || "节点",
    protocol: node.protocolCode || node.protocolLabel || node.scheme || "",
    reason
  };
}

function applyClashBulkPatch(proxy) {
  const udp = $("clashUdp").value;
  const skipCert = $("clashSkipCert").value;
  const fingerprint = $("clashFingerprint").value.trim();
  const servername = $("clashServername").value.trim();

  if (udp) proxy.udp = udp === "true";
  if (skipCert) proxy["skip-cert-verify"] = skipCert === "true";
  if (fingerprint) proxy["client-fingerprint"] = fingerprint;
  if (servername) {
    proxy.servername = servername;
    if (usesSniField(proxy.type)) {
      proxy.sni = servername;
    }
  }
  return proxy;
}

function usesSniField(type) {
  return ["trojan", "hysteria2", "hy2", "tuic"].includes(String(type || "").toLowerCase());
}

function getClashProxyFromRaw(raw) {
  const parsed = NodeParser.parseClashProxy(raw);
  return parsed ? cloneProxy(parsed.proxy) : null;
}

function nodeToClashProxy(node, name) {
  if (!node) return null;
  if (node.sourceFormat === "clash" && node.clashMeta && node.clashMeta.proxy) {
    const proxy = cloneProxy(node.clashMeta.proxy);
    if (name) proxy.name = name;
    return proxy;
  }

  const proxyName = name || node.rawName || node.protocolCode || "node";
  const base = {
    name: proxyName,
    type: normalizeClashOutputType(node.scheme),
    server: node.host,
    port: parsePortValue(node.port)
  };
  if (!base.type || !base.server || !base.port) return null;

  if (node.scheme === "ss") {
    return {
      ...base,
      cipher: node.method || "aes-128-gcm",
      password: node.user || "password",
      udp: true
    };
  }

  if (node.scheme === "vless") {
    const q = node.query || {};
    const proxy = {
      ...base,
      uuid: node.user || "",
      network: q.type || "tcp"
    };
    if (q.flow) proxy.flow = q.flow;
    if (q.security === "tls") proxy.tls = true;
    if (q.security === "reality") {
      proxy.tls = true;
      proxy["reality-opts"] = {
        "public-key": q.pbk || "",
        "short-id": q.sid || ""
      };
    }
    if (q.sni) proxy.servername = q.sni;
    if (q.fp) proxy["client-fingerprint"] = q.fp;
    if ((q.type || "").toLowerCase() === "ws") {
      proxy["ws-opts"] = {};
      if (q.path) proxy["ws-opts"].path = q.path;
      if (q.host) proxy["ws-opts"].headers = { Host: q.host };
    }
    return proxy;
  }

  if (node.scheme === "vmess") {
    const q = node.query || {};
    const proxy = {
      ...base,
      uuid: node.user || "",
      alterId: q.aid || 0,
      cipher: q.cipher || "auto",
      network: q.type || "tcp"
    };
    if (q.security === "tls") proxy.tls = true;
    if (q.sni) proxy.servername = q.sni;
    return proxy;
  }

  if (node.scheme === "http") {
    const auth = splitCredential(node.user);
    return {
      ...base,
      username: auth.username,
      password: (node.query && node.query.password) || auth.password
    };
  }

  if (node.scheme === "socks" || node.scheme === "socks5") {
    const auth = splitCredential(node.user);
    return {
      ...base,
      type: "socks5",
      username: auth.username,
      password: (node.query && node.query.password) || auth.password,
      udp: true
    };
  }

  if (node.scheme === "trojan") {
    const q = node.query || {};
    const proxy = {
      ...base,
      password: node.user || ""
    };
    if (q.sni) proxy.sni = q.sni;
    return proxy;
  }

  if (node.scheme === "hysteria2" || node.scheme === "hy2") {
    const q = node.query || {};
    const proxy = {
      ...base,
      type: "hysteria2",
      password: node.user || ""
    };
    if (q.sni) proxy.sni = q.sni;
    if (q.alpn) proxy.alpn = splitListValue(q.alpn);
    if (q.obfs) proxy.obfs = q.obfs;
    if (q["obfs-password"] || q.obfspassword) proxy["obfs-password"] = q["obfs-password"] || q.obfspassword;
    if (node.extra && node.extra.beforeQueryTail) proxy.ports = node.extra.beforeQueryTail;
    if (q.insecure === "1" || q.allowinsecure === "1") proxy["skip-cert-verify"] = true;
    return proxy;
  }

  if (node.scheme === "hysteria") {
    const q = node.query || {};
    const proxy = {
      ...base,
      auth_str: node.user || "",
      protocol: q.protocol || ""
    };
    if (q.sni) proxy.sni = q.sni;
    if (q.obfs) proxy.obfs = q.obfs;
    if (q.alpn) proxy.alpn = splitListValue(q.alpn);
    return proxy;
  }

  if (node.scheme === "tuic") {
    const q = node.query || {};
    const proxy = {
      ...base,
      uuid: node.user || ""
    };
    if (q.password) proxy.password = q.password;
    if (q.sni) proxy.sni = q.sni;
    if (q.alpn) proxy.alpn = splitListValue(q.alpn);
    assignIfPresent(proxy, "congestion-controller", firstQueryValue(q, ["congestion-controller", "congestioncontroller", "congestion"]));
    assignIfPresent(proxy, "udp-relay-mode", firstQueryValue(q, ["udp-relay-mode", "udprelaymode"]));
    assignBooleanIfPresent(proxy, "reduce-rtt", firstQueryValue(q, ["reduce-rtt", "reducertt"]));
    assignBooleanIfPresent(proxy, "disable-sni", firstQueryValue(q, ["disable-sni", "disablesni"]));
    return proxy;
  }

  if (node.scheme === "snell") {
    const q = node.query || {};
    const proxy = {
      ...base,
      psk: node.user || firstQueryValue(q, ["psk", "password"])
    };
    const version = firstQueryValue(q, ["version", "v"]);
    if (version) proxy.version = parseMaybeNumber(version);
    if (q.obfs) {
      proxy["obfs-opts"] = { mode: q.obfs };
      if (q.host) proxy["obfs-opts"].host = q.host;
      if (q.path) proxy["obfs-opts"].path = q.path;
    }
    return proxy;
  }

  if (node.scheme === "wireguard") {
    const q = node.query || {};
    const proxy = {
      ...base,
      "private-key": node.user || firstQueryValue(q, ["private-key", "privatekey"])
    };
    assignIfPresent(proxy, "public-key", firstQueryValue(q, ["public-key", "publickey"]));
    assignIfPresent(proxy, "pre-shared-key", firstQueryValue(q, ["pre-shared-key", "presharedkey", "psk"]));
    assignIfPresent(proxy, "ip", firstQueryValue(q, ["ip", "address"]));
    assignIfPresent(proxy, "ipv6", q.ipv6);
    assignIfPresent(proxy, "reserved", q.reserved);
    assignIfPresent(proxy, "dns", firstQueryValue(q, ["dns", "remote-dns", "remotedns"]));
    assignNumberIfPresent(proxy, "mtu", q.mtu);
    assignBooleanIfPresent(proxy, "udp", q.udp);
    return proxy;
  }

  if (node.scheme === "ssh") {
    const q = node.query || {};
    const auth = splitCredential(node.user);
    const proxy = {
      ...base,
      username: auth.username,
      password: q.password || auth.password
    };
    assignIfPresent(proxy, "private-key", firstQueryValue(q, ["private-key", "privatekey"]));
    assignIfPresent(proxy, "public-key", firstQueryValue(q, ["public-key", "publickey"]));
    return proxy;
  }

  if (node.scheme === "mieru") {
    const q = node.query || {};
    const proxy = {
      ...base,
      username: node.user || q.username || "",
      password: q.password || ""
    };
    assignIfPresent(proxy, "transport", q.transport);
    assignIfPresent(proxy, "multiplexing", q.multiplexing);
    return proxy;
  }

  return base;
}

function cloneProxy(proxy) {
  return JSON.parse(JSON.stringify(proxy || {}));
}

function splitCredential(value) {
  const text = String(value || "");
  const colon = text.indexOf(":");
  if (colon === -1) {
    return { username: text, password: "" };
  }
  return {
    username: text.slice(0, colon),
    password: text.slice(colon + 1)
  };
}

function firstQueryValue(query, keys) {
  for (const key of keys) {
    if (query && query[key] !== undefined && query[key] !== "") return query[key];
  }
  return "";
}

function assignIfPresent(target, key, value) {
  if (value !== undefined && value !== "") target[key] = value;
}

function assignNumberIfPresent(target, key, value) {
  if (value === undefined || value === "") return;
  const parsed = Number(value);
  target[key] = Number.isFinite(parsed) ? parsed : value;
}

function assignBooleanIfPresent(target, key, value) {
  if (value === undefined || value === "") return;
  target[key] = parseBoolValue(value);
}

function parseMaybeNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : value;
}

function parseBoolValue(value) {
  if (typeof value === "boolean") return value;
  return /^(1|true|yes|on)$/i.test(String(value));
}

function splitListValue(value) {
  const text = String(value || "").trim();
  if (!text) return [];
  return text.split(/[,，]+/).map(item => item.trim()).filter(Boolean);
}

function normalizeClashOutputType(scheme) {
  const clean = String(scheme || "").toLowerCase();
  if (clean === "hy2") return "hysteria2";
  if (clean === "socks") return "socks5";
  return clean;
}

function parsePortValue(port) {
  const value = Number(port);
  return Number.isInteger(value) && value > 0 && value <= 65535 ? value : "";
}

function clashProxyToUri(proxy, fallbackName) {
  const type = String(proxy.type || "").toLowerCase();
  const name = fallbackName || proxy.name || "node";
  const encodedName = $("encodeNodeName").checked ? encodeURIComponent(name) : name;
  const server = formatHostForShare(String(proxy.server || ""));
  const port = proxy.port;
  if (!server || !port) return "";

  if (type === "ss") {
    const user = (proxy.cipher || "aes-128-gcm") + ":" + (proxy.password || "");
    return "ss://" + user + "@" + server + ":" + port + "#" + encodedName;
  }

  if (type === "vless") {
    const params = new URLSearchParams();
    params.set("encryption", proxy.encryption || "none");
    if (proxy.flow) params.set("flow", proxy.flow);
    if (proxy.network) params.set("type", proxy.network);
    if (proxy.tls) params.set("security", proxy["reality-opts"] ? "reality" : "tls");
    if (proxy.servername) params.set("sni", proxy.servername);
    if (proxy["client-fingerprint"]) params.set("fp", proxy["client-fingerprint"]);
    if (proxy["reality-opts"]) {
      if (proxy["reality-opts"]["public-key"]) params.set("pbk", proxy["reality-opts"]["public-key"]);
      if (proxy["reality-opts"]["short-id"]) params.set("sid", proxy["reality-opts"]["short-id"]);
    }
    return "vless://" + (proxy.uuid || "") + "@" + server + ":" + port + "?" + params.toString() + "#" + encodedName;
  }

  if (type === "vmess") {
    return "vmess://" + base64Encode(JSON.stringify({
      v: "2",
      ps: name,
      add: String(proxy.server || ""),
      port: String(proxy.port || ""),
      id: proxy.uuid || "",
      aid: String(proxy.alterId || proxy.alterId === 0 ? proxy.alterId : 0),
      net: proxy.network || "tcp",
      type: "none",
      host: proxy.servername || "",
      path: proxy["ws-opts"] && proxy["ws-opts"].path ? proxy["ws-opts"].path : "",
      tls: proxy.tls ? "tls" : ""
    }));
  }

  if (type === "trojan") {
    const params = new URLSearchParams();
    if (proxy.sni || proxy.servername) params.set("sni", proxy.sni || proxy.servername);
    const query = params.toString();
    return "trojan://" + (proxy.password || "") + "@" + server + ":" + port + (query ? "?" + query : "") + "#" + encodedName;
  }

  if (type === "hysteria2" || type === "hy2") {
    const params = new URLSearchParams();
    if (proxy.sni) params.set("sni", proxy.sni);
    const query = params.toString();
    return "hysteria2://" + (proxy.password || "") + "@" + server + ":" + port + (query ? "?" + query : "") + "#" + encodedName;
  }

  if (type === "socks5" || type === "socks") {
    const userInfo = proxy.username ? encodeURIComponent(proxy.username) + (proxy.password ? ":" + encodeURIComponent(proxy.password) : "") + "@" : "";
    return "socks://" + userInfo + server + ":" + port + "#" + encodedName;
  }

  if (type === "http") {
    const userInfo = proxy.username ? encodeURIComponent(proxy.username) + (proxy.password ? ":" + encodeURIComponent(proxy.password) : "") + "@" : "";
    return "http://" + userInfo + server + ":" + port + "#" + encodedName;
  }

  if (type === "hysteria") {
    const params = new URLSearchParams();
    if (proxy.sni) params.set("sni", proxy.sni);
    if (proxy.protocol) params.set("protocol", proxy.protocol);
    const query = params.toString();
    return "hysteria://" + (proxy.auth_str || proxy.password || "") + "@" + server + ":" + port + (query ? "?" + query : "") + "#" + encodedName;
  }

  return "";
}

function getGroupNameForNode(node) {
  const group = state.groups.find(item => item.id === node.groupId);
  return group ? group.name : node.vpsCandidate;
}

function isValidForwardPort(port) {
  const portNum = Number(port);
  return Number.isInteger(portNum) && portNum > 0 && portNum <= 65535;
}

function normalizeForwardHost(host) {
  return String(host || "")
    .trim()
    .replace(/^[a-z][a-z0-9+.-]*:\/\//i, "")
    .replace(/[/?#].*$/, "")
    .replace(/^\[([^\]]+)\]$/, "$1");
}

function splitForwardEndpoint(value) {
  const host = normalizeForwardHost(value);
  const bracketMatch = host.match(/^\[([^\]]+)\]:(\d{1,5})$/);
  if (bracketMatch && isValidForwardPort(bracketMatch[2])) {
    return { host: bracketMatch[1], port: bracketMatch[2], hasPort: true };
  }

  const hostPortMatch = host.match(/^(.+):(\d{1,5})$/);
  if (hostPortMatch && !hostPortMatch[1].includes(":") && isValidForwardPort(hostPortMatch[2])) {
    return { host: hostPortMatch[1], port: hostPortMatch[2], hasPort: true };
  }

  return { host, port: "", hasPort: false };
}

function applyForwardEndpointInput(hostInput, portInput) {
  const split = splitForwardEndpoint(hostInput.value);
  if (!split.hasPort) return;
  hostInput.value = split.host;
  if (portInput) {
    portInput.value = split.port;
  }
}

function syncForwardSelectionFromEndpoint(node) {
  if (!node) return;
  const forward = getForwardConfig(node);
  if (forward.valid && canForwardNode(node)) {
    node.forwardSelected = true;
    $("forwardEnabled").checked = true;
    return;
  }
  if (!forward.host && !forward.port) {
    node.forwardSelected = false;
  }
}

function syncForwardSelectInput(root, node) {
  if (!root || !node) return;
  const input = root.querySelector('[data-forward-select="' + node.id + '"]');
  if (input && !input.disabled) {
    input.checked = Boolean(node.forwardSelected);
  }
}

function syncForwardQrButton(root, node) {
  if (!root || !node) return;
  const button = root.querySelector('[data-forward-qr-link="' + node.id + '"]');
  if (!button) return;
  const ready = Boolean(makeForwardQrLink(node));
  button.disabled = !ready;
  if (ready) {
    button.removeAttribute("title");
  } else {
    button.title = "当前行还没有可生成二维码的转发节点链接";
  }
}

function shouldOutputForwardNode(node, forward) {
  return !getForwardSkipReason(node, forward);
}

function makeForwardQrLink(node) {
  const forward = getForwardConfig(node);
  const skipReason = getForwardSkipReason(node, forward);
  if (skipReason) return "";

  const forwardedRaw = NodeProducer.rewriteEndpoint(node, forward.host, forward.port);
  if (forwardedRaw === node.raw) return "";

  const forwardName = node.forwardName || NodeProcessor.makeForwardName(node, getGroupNameForNode(node));
  const link = NodeProducer.rewriteName(forwardedRaw, forwardName);
  return isQrShareLink(link) ? link : "";
}

function getForwardSkipReason(node, forward) {
  if (!$("forwardEnabled").checked) return "未启用转发输出";
  if (!node.forwardSelected) return "当前节点未选择转发";
  if (!forward.valid) return "转发入口或端口无效";
  if (!canForwardNode(node)) return "当前节点暂不支持改写入口";
  return "";
}

function canForwardNode(node) {
  if (node.sourceFormat === "clash") return Boolean(node.host && node.port);
  return /@(?:\[[^\]]+\]|[^:?\s/#]+):\d+/.test(node.raw || "")
    || hasDirectShareEndpoint(node)
    || ((node.scheme === "ss" || node.scheme === "vmess") && Boolean(node.host && node.port));
}

function hasDirectShareEndpoint(node) {
  if (!node || !node.scheme || !node.host || !node.port) return false;
  const host = escapeRegExp(formatHostForShare(node.host));
  return new RegExp("^" + escapeRegExp(node.scheme) + ":\\/\\/" + host + ":" + escapeRegExp(String(node.port)) + "(?:[/?#]|$)", "i").test(node.raw || "");
}

function getForwardConfig(node) {
  const perNode = $("forwardMode").value === "per-node";
  let host = perNode && node ? (node.forwardHost || "").trim() : $("forwardHost").value.trim();
  let port = perNode && node ? (node.forwardPort || "").trim() : $("forwardPort").value.trim();
  const split = splitForwardEndpoint(host);
  host = split.host;
  if (!port && split.hasPort) {
    port = split.port;
  }

  return {
    host,
    port,
    valid: Boolean(host) && isValidForwardPort(port)
  };
}

function rewriteEndpoint(nodeOrRaw, host, port) {
  const node = typeof nodeOrRaw === "string" ? null : nodeOrRaw;
  const raw = node ? node.raw : nodeOrRaw;
  const scheme = node ? node.scheme : ((raw.match(/^([a-z0-9+.-]+):\/\//i) || [])[1] || "").toLowerCase();

  if (node && node.sourceFormat === "clash") {
    return rewriteClashProxy(raw, { server: host.trim().replace(/^\[|\]$/g, ""), port: Number(port) });
  }
  if (scheme === "ss") {
    return rewriteShadowsocksEndpoint(raw, host, port);
  }
  if (scheme === "vmess") {
    return rewriteVmessEndpoint(raw, host, port);
  }

  const endpoint = formatHostForShare(host) + ":" + port;
  if (/@(?:\[[^\]]+\]|[^:?\s/#]+):\d+/.test(raw)) {
    return raw.replace(/@(?:\[[^\]]+\]|[^:?\s/#]+):\d+/, "@" + endpoint);
  }
  if (node && hasDirectShareEndpoint(node)) {
    return raw.replace(
      new RegExp("^(" + escapeRegExp(node.scheme) + ":\\/\\/)(?:\\[[^\\]]+\\]|[^:?\\s/#]+):" + escapeRegExp(String(node.port)), "i"),
      "$1" + endpoint
    );
  }
  return raw;
}

function rewriteShadowsocksEndpoint(raw, host, port) {
  const prefix = "ss://";
  const withoutScheme = raw.replace(/^ss:\/\//i, "");
  const fragmentSplit = splitFragment(withoutScheme);
  const querySplit = splitQuery(fragmentSplit.body);
  const body = querySplit.body.trim();
  const endpoint = formatHostForShare(host) + ":" + port;

  let nextBody = body;
  if (body.includes("@")) {
    const at = body.lastIndexOf("@");
    nextBody = body.slice(0, at + 1) + endpoint;
  } else {
    const decoded = decodeBase64(body);
    if (!decoded || !decoded.includes("@")) return raw;
    const at = decoded.lastIndexOf("@");
    nextBody = base64Encode(decoded.slice(0, at + 1) + endpoint);
  }

  return prefix
    + nextBody
    + (querySplit.query ? "?" + querySplit.query : "")
    + (fragmentSplit.fragment ? "#" + fragmentSplit.fragment : "");
}

function rewriteVmessEndpoint(raw, host, port) {
  const withoutScheme = raw.replace(/^vmess:\/\//i, "");
  const fragmentSplit = splitFragment(withoutScheme);
  const decoded = decodeBase64(fragmentSplit.body);
  if (!decoded) return raw;

  try {
    const data = JSON.parse(decoded);
    data.add = host.trim().replace(/^\[|\]$/g, "");
    data.port = String(port);
    return "vmess://" + base64Encode(JSON.stringify(data)) + (fragmentSplit.fragment ? "#" + fragmentSplit.fragment : "");
  } catch (err) {
    return raw;
  }
}

function formatHostForShare(host) {
  const clean = host.trim().replace(/^\[|\]$/g, "");
  if ((clean.match(/:/g) || []).length >= 2 && !clean.includes(".")) {
    return "[" + clean + "]";
  }
  return clean;
}

function rewriteName(raw, name) {
  const cleanName = String(name || "").replace(/[\r\n#]+/g, " ").replace(/\s+/g, " ").trim();
  if (NodeParser.parseClashProxy(raw)) {
    return rewriteClashProxy(raw, { name: cleanName });
  }
  if (/^vmess:\/\//i.test(raw)) {
    return rewriteVmessName(raw, cleanName);
  }
  const finalName = $("encodeNodeName").checked ? encodeURIComponent(cleanName) : cleanName;
  if (raw.includes("#")) {
    return raw.replace(/#.*$/, "#" + finalName);
  }
  return raw + "#" + finalName;
}

function rewriteVmessName(raw, name) {
  const withoutScheme = raw.replace(/^vmess:\/\//i, "");
  const fragmentSplit = splitFragment(withoutScheme);
  const decoded = decodeBase64(fragmentSplit.body);
  if (!decoded) return raw;

  try {
    const data = JSON.parse(decoded);
    data.ps = name;
    return "vmess://" + base64Encode(JSON.stringify(data));
  } catch (err) {
    return raw;
  }
}

function rewriteClashProxy(raw, patch) {
  const parsed = NodeParser.parseClashProxy(raw);
  if (!parsed) return raw;
  const proxy = { ...cloneProxy(parsed.proxy), ...patch };
  return parsed.prefix + JSON.stringify(proxy) + parsed.suffix;
}

function updateMetrics() {
  $("metricNodes").textContent = String(state.nodes.length);
  $("metricGroups").textContent = String(state.groups.length);
  $("metricProtocols").textContent = String(new Set(state.nodes.map(n => n.protocolCode)).size);
  $("metricRemoved").textContent = String(state.removedLines + state.duplicateCount + state.invalidCount);
}

function setMessage(message, type = "") {
  const box = $("message");
  box.className = "message" + (type ? " " + type : "");
  box.textContent = message || "";
}

async function copyOutput() {
  const text = $("output").textContent;
  if (!text) {
    setMessage("当前没有可复制的输出。", "err");
    return;
  }
  copyText(text, "已复制当前输出。");
}

async function copyText(text, successMessage) {
  try {
    await navigator.clipboard.writeText(text);
    setMessage(successMessage, "ok");
  } catch (err) {
    setMessage("浏览器阻止了剪贴板写入，请手动选择输出内容复制。", "warn");
  }
}

function downloadOutput() {
  const text = $("output").textContent;
  if (!text) {
    setMessage("当前没有可下载的输出。", "err");
    return;
  }
  const blob = new Blob([text], { type: "text/plain;charset=utf-8" });
  const a = document.createElement("a");
  const ts = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
  a.href = URL.createObjectURL(blob);
  a.download = "proxy-nodes-" + state.outputContent + "-" + state.outputFormat + "-" + ts + ".txt";
  a.click();
  URL.revokeObjectURL(a.href);
}

function decodeSafe(value) {
  try {
    return decodeURIComponent(value);
  } catch (err) {
    return value;
  }
}

function decodeBase64(value) {
  try {
    let input = value.trim().replace(/-/g, "+").replace(/_/g, "/");
    while (input.length % 4) input += "=";
    const binary = atob(input);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return new TextDecoder().decode(bytes);
  } catch (err) {
    return "";
  }
}

function base64Encode(text) {
  const bytes = new TextEncoder().encode(text);
  let binary = "";
  bytes.forEach(byte => binary += String.fromCharCode(byte));
  return btoa(binary);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function escapeAttr(value) {
  return escapeHtml(value).replace(/`/g, "&#96;");
}

clearSingleNodeQr({ silent: true });
renderAll("等待输入。", "warn");
