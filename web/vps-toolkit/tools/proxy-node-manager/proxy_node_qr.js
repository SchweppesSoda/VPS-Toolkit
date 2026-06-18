(function (global) {
  "use strict";

  const MAX_VERSION = 40;
  const QUIET_ZONE = 4;
  const ECC_LOW = {
    label: "L",
    formatBits: 1,
    eccCodewordsPerBlock: [
      -1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18,
      20, 24, 26, 30, 22, 24, 28, 30, 28, 28,
      28, 28, 30, 30, 26, 28, 30, 30, 30, 30,
      30, 30, 30, 30, 30, 30, 30, 30, 30, 30
    ],
    numErrorCorrectionBlocks: [
      -1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4,
      4, 4, 4, 4, 6, 6, 6, 6, 7, 8,
      8, 9, 9, 10, 12, 12, 12, 13, 14, 15,
      16, 17, 18, 19, 19, 20, 21, 22, 24, 25
    ]
  };

  function encode(text) {
    if (typeof TextEncoder === "undefined") {
      throw new Error("当前浏览器不支持 TextEncoder，不能生成二维码。");
    }
    const payload = String(text || "");
    const bytes = Array.from(new TextEncoder().encode(payload));
    if (!bytes.length) {
      throw new Error("请输入节点链接。");
    }
    const version = chooseVersion(bytes);
    const dataCodewords = makeDataCodewords(bytes, version);
    const codewords = addEccAndInterleave(dataCodewords, version);
    const matrix = makeMatrix(version, codewords);
    return {
      version,
      ecc: ECC_LOW.label,
      size: matrix.length,
      modules: matrix,
      byteLength: bytes.length,
      text: payload
    };
  }

  function drawToCanvas(qr, canvas, opts = {}) {
    if (!canvas || !qr || !qr.modules) return;
    const scale = Math.max(2, opts.scale || Math.floor((opts.maxSize || 320) / (qr.size + QUIET_ZONE * 2)));
    const pixels = (qr.size + QUIET_ZONE * 2) * scale;
    canvas.width = pixels;
    canvas.height = pixels;
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, pixels, pixels);
    ctx.fillStyle = "#000000";
    for (let y = 0; y < qr.size; y++) {
      for (let x = 0; x < qr.size; x++) {
        if (qr.modules[y][x]) {
          ctx.fillRect((x + QUIET_ZONE) * scale, (y + QUIET_ZONE) * scale, scale, scale);
        }
      }
    }
  }

  function chooseVersion(bytes) {
    for (let version = 1; version <= MAX_VERSION; version++) {
      const countBits = version <= 9 ? 8 : 16;
      const capacityBits = getNumDataCodewords(version) * 8;
      if (bytes.length < (1 << countBits) && 4 + countBits + bytes.length * 8 <= capacityBits) {
        return version;
      }
    }
    throw new Error("链接太长，超过 QR Code version 40-L 的容量。");
  }

  function makeDataCodewords(bytes, version) {
    const capacityBits = getNumDataCodewords(version) * 8;
    const countBits = version <= 9 ? 8 : 16;
    const bits = [];
    appendBits(bits, 0x4, 4);
    appendBits(bits, bytes.length, countBits);
    bytes.forEach(byte => appendBits(bits, byte, 8));

    const terminator = Math.min(4, capacityBits - bits.length);
    appendBits(bits, 0, terminator);
    while (bits.length % 8) bits.push(0);

    const result = [];
    for (let i = 0; i < bits.length; i += 8) {
      let value = 0;
      for (let j = 0; j < 8; j++) {
        value = (value << 1) | bits[i + j];
      }
      result.push(value);
    }

    for (let pad = 0xec; result.length < getNumDataCodewords(version); pad ^= 0xec ^ 0x11) {
      result.push(pad);
    }
    return result;
  }

  function appendBits(bits, value, length) {
    for (let i = length - 1; i >= 0; i--) {
      bits.push((value >>> i) & 1);
    }
  }

  function addEccAndInterleave(data, version) {
    const numBlocks = ECC_LOW.numErrorCorrectionBlocks[version];
    const blockEccLen = ECC_LOW.eccCodewordsPerBlock[version];
    const rawCodewords = Math.floor(getNumRawDataModules(version) / 8);
    const numShortBlocks = numBlocks - rawCodewords % numBlocks;
    const shortBlockLen = Math.floor(rawCodewords / numBlocks);
    const rsDivisor = reedSolomonComputeDivisor(blockEccLen);
    const blocks = [];
    let offset = 0;

    for (let i = 0; i < numBlocks; i++) {
      const dataLen = shortBlockLen - blockEccLen + (i < numShortBlocks ? 0 : 1);
      const blockData = data.slice(offset, offset + dataLen);
      offset += dataLen;
      const ecc = reedSolomonComputeRemainder(blockData, rsDivisor);
      if (i < numShortBlocks) {
        blockData.push(0);
      }
      blocks.push(blockData.concat(ecc));
    }

    const result = [];
    for (let i = 0; i < blocks[0].length; i++) {
      for (let j = 0; j < blocks.length; j++) {
        if (i !== shortBlockLen - blockEccLen || j >= numShortBlocks) {
          result.push(blocks[j][i]);
        }
      }
    }
    return result;
  }

  function reedSolomonComputeDivisor(degree) {
    const result = Array(degree).fill(0);
    result[degree - 1] = 1;
    let root = 1;
    for (let i = 0; i < degree; i++) {
      for (let j = 0; j < degree; j++) {
        result[j] = reedSolomonMultiply(result[j], root);
        if (j + 1 < degree) {
          result[j] ^= result[j + 1];
        }
      }
      root = reedSolomonMultiply(root, 0x02);
    }
    return result;
  }

  function reedSolomonComputeRemainder(data, divisor) {
    const result = Array(divisor.length).fill(0);
    for (const byte of data) {
      const factor = byte ^ result[0];
      result.copyWithin(0, 1);
      result[result.length - 1] = 0;
      for (let i = 0; i < result.length; i++) {
        result[i] ^= reedSolomonMultiply(divisor[i], factor);
      }
    }
    return result;
  }

  function reedSolomonMultiply(x, y) {
    let z = 0;
    for (let i = 7; i >= 0; i--) {
      z = ((z << 1) ^ ((z >>> 7) * 0x11d)) & 0xff;
      z ^= ((y >>> i) & 1) * x;
    }
    return z;
  }

  function makeMatrix(version, codewords) {
    const size = version * 4 + 17;
    const modules = make2d(size, false);
    const isFunction = make2d(size, false);
    drawFunctionPatterns(version, modules, isFunction);
    drawCodewords(modules, isFunction, codewords);

    let bestMask = 0;
    let bestPenalty = Infinity;
    let bestModules = null;
    for (let mask = 0; mask < 8; mask++) {
      const trial = clone2d(modules);
      applyMask(trial, isFunction, mask);
      drawFormatBits(trial, null, mask);
      const penalty = getPenaltyScore(trial);
      if (penalty < bestPenalty) {
        bestMask = mask;
        bestPenalty = penalty;
        bestModules = trial;
      }
    }
    drawFormatBits(bestModules, null, bestMask);
    return bestModules;
  }

  function make2d(size, value) {
    return Array.from({ length: size }, () => Array(size).fill(value));
  }

  function clone2d(matrix) {
    return matrix.map(row => row.slice());
  }

  function drawFunctionPatterns(version, modules, isFunction) {
    const size = modules.length;
    drawFinderPattern(modules, isFunction, 3, 3);
    drawFinderPattern(modules, isFunction, size - 4, 3);
    drawFinderPattern(modules, isFunction, 3, size - 4);

    for (let i = 0; i < size; i++) {
      if (!isFunction[6][i]) setFunctionModule(modules, isFunction, i, 6, i % 2 === 0);
      if (!isFunction[i][6]) setFunctionModule(modules, isFunction, 6, i, i % 2 === 0);
    }

    const align = getAlignmentPatternPositions(version);
    for (const y of align) {
      for (const x of align) {
        if (!isFunction[y][x]) {
          drawAlignmentPattern(modules, isFunction, x, y);
        }
      }
    }

    drawFormatBits(modules, isFunction, 0);
    if (version >= 7) {
      drawVersionInfo(modules, isFunction, version);
    }
  }

  function drawFinderPattern(modules, isFunction, cx, cy) {
    const size = modules.length;
    for (let dy = -4; dy <= 4; dy++) {
      for (let dx = -4; dx <= 4; dx++) {
        const x = cx + dx;
        const y = cy + dy;
        if (x < 0 || y < 0 || x >= size || y >= size) continue;
        const dist = Math.max(Math.abs(dx), Math.abs(dy));
        setFunctionModule(modules, isFunction, x, y, dist !== 2 && dist !== 4);
      }
    }
  }

  function drawAlignmentPattern(modules, isFunction, cx, cy) {
    for (let dy = -2; dy <= 2; dy++) {
      for (let dx = -2; dx <= 2; dx++) {
        setFunctionModule(modules, isFunction, cx + dx, cy + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
      }
    }
  }

  function drawFormatBits(modules, isFunction, mask) {
    const size = modules.length;
    const data = (ECC_LOW.formatBits << 3) | mask;
    let rem = data;
    for (let i = 0; i < 10; i++) {
      rem = (rem << 1) ^ (((rem >>> 9) & 1) * 0x537);
    }
    const bits = ((data << 10) | rem) ^ 0x5412;
    const set = (x, y, dark) => isFunction
      ? setFunctionModule(modules, isFunction, x, y, dark)
      : setModule(modules, x, y, dark);

    for (let i = 0; i <= 5; i++) set(8, i, getBit(bits, i));
    set(8, 7, getBit(bits, 6));
    set(8, 8, getBit(bits, 7));
    set(7, 8, getBit(bits, 8));
    for (let i = 9; i < 15; i++) set(14 - i, 8, getBit(bits, i));
    for (let i = 0; i < 8; i++) set(size - 1 - i, 8, getBit(bits, i));
    for (let i = 8; i < 15; i++) set(8, size - 15 + i, getBit(bits, i));
    set(8, size - 8, true);
  }

  function drawVersionInfo(modules, isFunction, version) {
    const size = modules.length;
    let rem = version;
    for (let i = 0; i < 12; i++) {
      rem = (rem << 1) ^ (((rem >>> 11) & 1) * 0x1f25);
    }
    const bits = (version << 12) | rem;
    for (let i = 0; i < 18; i++) {
      const dark = getBit(bits, i);
      const a = size - 11 + i % 3;
      const b = Math.floor(i / 3);
      setFunctionModule(modules, isFunction, a, b, dark);
      setFunctionModule(modules, isFunction, b, a, dark);
    }
  }

  function drawCodewords(modules, isFunction, codewords) {
    const size = modules.length;
    let bitIndex = 0;
    for (let right = size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let vert = 0; vert < size; vert++) {
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? size - 1 - vert : vert;
        for (let j = 0; j < 2; j++) {
          const x = right - j;
          if (isFunction[y][x]) continue;
          const byte = codewords[Math.floor(bitIndex / 8)] || 0;
          modules[y][x] = getBit(byte, 7 - (bitIndex % 8));
          bitIndex++;
        }
      }
    }
  }

  function applyMask(modules, isFunction, mask) {
    const size = modules.length;
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        if (!isFunction[y][x] && shouldInvertMask(mask, x, y)) {
          modules[y][x] = !modules[y][x];
        }
      }
    }
  }

  function shouldInvertMask(mask, x, y) {
    switch (mask) {
      case 0: return (x + y) % 2 === 0;
      case 1: return y % 2 === 0;
      case 2: return x % 3 === 0;
      case 3: return (x + y) % 3 === 0;
      case 4: return (Math.floor(y / 2) + Math.floor(x / 3)) % 2 === 0;
      case 5: return (x * y) % 2 + (x * y) % 3 === 0;
      case 6: return ((x * y) % 2 + (x * y) % 3) % 2 === 0;
      case 7: return ((x + y) % 2 + (x * y) % 3) % 2 === 0;
      default: throw new Error("Invalid QR mask");
    }
  }

  function getAlignmentPatternPositions(version) {
    if (version === 1) return [];
    const size = version * 4 + 17;
    const numAlign = Math.floor(version / 7) + 2;
    const step = version === 32 ? 26 : Math.ceil((version * 4 + 4) / (numAlign * 2 - 2)) * 2;
    const result = [6];
    for (let pos = size - 7; result.length < numAlign; pos -= step) {
      result.splice(1, 0, pos);
    }
    return result;
  }

  function setFunctionModule(modules, isFunction, x, y, dark) {
    modules[y][x] = Boolean(dark);
    isFunction[y][x] = true;
  }

  function setModule(modules, x, y, dark) {
    modules[y][x] = Boolean(dark);
  }

  function getBit(value, index) {
    return ((value >>> index) & 1) !== 0;
  }

  function getNumDataCodewords(version) {
    return Math.floor(getNumRawDataModules(version) / 8)
      - ECC_LOW.eccCodewordsPerBlock[version] * ECC_LOW.numErrorCorrectionBlocks[version];
  }

  function getNumRawDataModules(version) {
    let result = (16 * version + 128) * version + 64;
    if (version >= 2) {
      const numAlign = Math.floor(version / 7) + 2;
      result -= (25 * numAlign - 10) * numAlign - 55;
      if (version >= 7) result -= 36;
    }
    return result;
  }

  function getPenaltyScore(modules) {
    const size = modules.length;
    let result = 0;
    for (let y = 0; y < size; y++) {
      result += getLinePenalty(modules[y]);
    }
    for (let x = 0; x < size; x++) {
      const column = [];
      for (let y = 0; y < size; y++) column.push(modules[y][x]);
      result += getLinePenalty(column);
    }

    for (let y = 0; y < size - 1; y++) {
      for (let x = 0; x < size - 1; x++) {
        const color = modules[y][x];
        if (color === modules[y][x + 1] && color === modules[y + 1][x] && color === modules[y + 1][x + 1]) {
          result += 3;
        }
      }
    }

    let dark = 0;
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        if (modules[y][x]) dark++;
      }
    }
    const total = size * size;
    result += Math.floor(Math.abs(dark * 20 - total * 10) / total) * 10;
    return result;
  }

  function getLinePenalty(line) {
    let result = 0;
    let runColor = false;
    let runLen = 0;
    for (let i = 0; i < line.length; i++) {
      if (i === 0 || line[i] !== runColor) {
        if (runLen >= 5) result += runLen - 2;
        runColor = line[i];
        runLen = 1;
      } else {
        runLen++;
      }
    }
    if (runLen >= 5) result += runLen - 2;

    const patternA = [true, false, true, true, true, false, true, false, false, false, false];
    const patternB = [false, false, false, false, true, false, true, true, true, false, true];
    for (let i = 0; i <= line.length - 11; i++) {
      if (matchesPattern(line, i, patternA) || matchesPattern(line, i, patternB)) {
        result += 40;
      }
    }
    return result;
  }

  function matchesPattern(line, offset, pattern) {
    for (let i = 0; i < pattern.length; i++) {
      if (line[offset + i] !== pattern[i]) return false;
    }
    return true;
  }

  global.ProxyNodeQr = {
    encode,
    drawToCanvas
  };
})(window);
