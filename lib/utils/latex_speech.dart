/// LaTeX → 自然中文语音文本。
///
/// 设计原则：
///   - 结构性词汇：\frac → "X分之Y"，\sqrt → "根号X"，^ → "X的N次方"
///   - 函数名汉化：\sin → "正弦"，\ln → "自然对数" 等
///   - 运算符汉化：+ → "加"，× → "乘以" 等
///   - 括号静默：数学括号不读出，用语序暗示结构
///   - 保留数字字面量：交给 TTS 引擎朗读
library;

/// 将单段 LaTeX 串转为中文语音文本。
String latexToSpeech(String latex) {
  final preprocessed = _preprocessMatrix(latex.trim());
  final raw = _Lts(preprocessed).read();
  return _arabicToChinese(raw);
}

/// 将矩阵行列式结构替换为可播报的中文描述，例如：
///   |\begin{matrix}2&3\\4&5\end{matrix}|  →  行列式，第一行2，3，第二行4，5
///   \det\begin{pmatrix}...\end{pmatrix}    →  同上
String _preprocessMatrix(String s) {
  // 统一处理各种矩阵行列式写法
  final patterns = [
    RegExp(
      r'\\det\s*\\begin\{[A-Za-z]*matrix\}(.*?)\\end\{[A-Za-z]*matrix\}',
      dotAll: true,
    ),
    RegExp(
      r'\|\\begin\{[A-Za-z]*matrix\}(.*?)\\end\{[A-Za-z]*matrix\}\|',
      dotAll: true,
    ),
    RegExp(r'\\begin\{[Vv]matrix\}(.*?)\\end\{[Vv]matrix\}', dotAll: true),
  ];
  for (final pat in patterns) {
    s = s.replaceAllMapped(pat, (m) => _matrixToSpeech(m.group(1)!));
  }
  return s;
}

String _matrixToSpeech(String content) {
  final rowStrs = content.split(RegExp(r'\\\\'));
  final parts = <String>[];
  final rowNames = ['第一行', '第二行', '第三行', '第四行', '第五行'];
  for (int i = 0; i < rowStrs.length; i++) {
    final row = rowStrs[i].trim();
    if (row.isEmpty) continue;
    final cells = row.split('&').map((c) => c.trim()).join('，');
    final label = i < rowNames.length ? rowNames[i] : '第${i + 1}行';
    parts.add('$label$cells');
  }
  return '行列式，${parts.join('，')}';
}

/// 将表达式 token 列表 + 计算结果合成完整播报文本。
///
/// 示例：
///   expression = [r'\frac{1}{2}', '+', r'\sqrt{3}']
///   calcResult = '= 1.866'
///   → "二分之一，加，根号三，等于，一点八六六"
String buildSpeechText(List<String> expression, String calcResult) {
  final parts = expression
      .map(latexToSpeech)
      .where((s) => s.isNotEmpty)
      .toList();
  final exprText = parts.join('，');
  final r = calcResult.replaceFirst(RegExp(r'^=\s*'), '');
  final rChinese = _arabicToChinese(r);
  if (r.isEmpty) return exprText;
  return exprText.isEmpty ? '等于，$rChinese' : '$exprText，等于，$rChinese';
}

// ─── 阿拉伯数字 → 中文 ────────────────────────────────────────────────────────

const _kDigits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

/// 将文本中所有阿拉伯数字序列替换为中文，避免 iOS TTS 将 "2" 读作 "两"。
String _arabicToChinese(String text) => text.replaceAllMapped(
  RegExp(r'-?\d+(?:\.\d+)?'),
  (m) => _numToChinese(m[0]!),
);

String _numToChinese(String s) {
  final negative = s.startsWith('-');
  final abs = negative ? s.substring(1) : s;
  final prefix = negative ? '负' : '';
  if (abs.contains('.')) {
    final parts = abs.split('.');
    final intPart = _intToChinese(int.parse(parts[0]));
    final decPart = parts[1]
        .split('')
        .map((d) => _kDigits[int.parse(d)])
        .join();
    return '$prefix$intPart点$decPart';
  }
  return '$prefix${_intToChinese(int.parse(abs))}';
}

String _intToChinese(int n) {
  if (n == 0) return '零';
  if (n < 10) return _kDigits[n];
  if (n < 20) return n == 10 ? '十' : '十${_kDigits[n - 10]}';
  if (n < 100) {
    final t = _kDigits[n ~/ 10];
    final o = n % 10 == 0 ? '' : _kDigits[n % 10];
    return '$t十$o';
  }
  if (n < 1000) {
    final h = _kDigits[n ~/ 100];
    final rest = n % 100;
    if (rest == 0) return '$h百';
    if (rest < 10) return '$h百零${_kDigits[rest]}';
    return '$h百${_intToChinese(rest)}';
  }
  if (n < 10000) {
    final th = _kDigits[n ~/ 1000];
    final rest = n % 1000;
    if (rest == 0) return '$th千';
    if (rest < 100) return '$th千零${_intToChinese(rest)}';
    return '$th千${_intToChinese(rest)}';
  }
  // 万以上保留阿拉伯数字，让 TTS 自行处理
  return n.toString();
}

// ─── 核心解析器 ──────────────────────────────────────────────────────────────

class _Lts {
  final String _s;
  int _pos = 0;

  _Lts(this._s);

  String read() {
    final sb = StringBuffer();
    while (_pos < _s.length) {
      sb.write(_next());
    }
    return sb.toString().replaceAll(RegExp(r'，{2,}'), '，').trim();
  }

  String _next() {
    if (_pos >= _s.length) return '';
    final c = _s[_pos];

    if (c == '\\') return _command();
    if (c == '{') return _brace();
    if (c == '^') return _power();
    if (c == '_') {
      _skipSub();
      return '';
    }
    if (c == '&') {
      _pos++;
      return '，';
    } // 矩阵列分隔符
    if (c == '|') return _absBar();
    if (c == '(') {
      _pos++;
      return '';
    }
    if (c == ')') {
      _pos++;
      return '';
    }
    if (c == '!') {
      _pos++;
      return '的阶乘';
    }
    if (c == '%') {
      _pos++;
      return '百分';
    }
    if (c == '+') {
      _pos++;
      return '加';
    }
    if (c == '-') {
      _pos++;
      return '减';
    }
    if (c == '×' || c == '*') {
      _pos++;
      return '乘以';
    }
    if (c == '÷' || c == '/') {
      _pos++;
      return '除以';
    }
    if (c == '=') {
      _pos++;
      return '等于';
    }
    if (c == ',') {
      _pos++;
      return '，';
    }
    if (c == ' ') {
      _pos++;
      return '';
    }
    _pos++;
    return c; // 数字、字母等直接保留，交给 TTS
  }

  // ── \command 处理 ──────────────────────────────────────────────────────────

  String _command() {
    _pos++; // 跳过 '\'
    final start = _pos;
    // 读取命令名（纯字母）
    while (_pos < _s.length && _isLetter(_s[_pos])) {
      _pos++;
    }
    // 处理单字符命令（\, \! 等）
    if (_pos == start && _pos < _s.length) _pos++;
    final cmd = _s.substring(start, _pos);

    switch (cmd) {
      // ── 结构 ────────────────────────────────────────────────────────
      case 'frac':
        final num = _braceContent();
        final den = _braceContent();
        return '${_sub(den)}分之${_sub(num)}';

      case 'sqrt':
        if (_pos < _s.length && _s[_pos] == '[') {
          final n = _bracketContent();
          final a = _braceContent();
          return '${_sub(n)}次根号${_sub(a)}';
        } else {
          final a = _braceContent();
          return '根号${_sub(a)}';
        }

      case 'binom':
        final n = _braceContent();
        final k = _braceContent();
        return '${_sub(n)}取${_sub(k)}';

      case 'log':
        // \log_{base}{arg} 或普通 \log
        if (_pos < _s.length && _s[_pos] == '_') {
          _pos++; // 跳过 _
          final base = _pos < _s.length && _s[_pos] == '{'
              ? _braceContent()
              : _singleChar();
          return '以${_sub(base)}为底的对数';
        }
        return '对数';

      // ── 三角函数 ─────────────────────────────────────────────────────
      case 'sin':
        return '正弦';
      case 'cos':
        return '余弦';
      case 'tan':
        return '正切';
      case 'cot':
        return '余切';
      case 'sec':
        return '正割';
      case 'csc':
        return '余割';
      case 'arcsin':
        return '反正弦';
      case 'arccos':
        return '反余弦';
      case 'arctan':
        return '反正切';
      case 'sinh':
        return '双曲正弦';
      case 'cosh':
        return '双曲余弦';
      case 'tanh':
        return '双曲正切';

      // ── 对数 / 指数 ──────────────────────────────────────────────────
      case 'ln':
        return '自然对数';
      case 'exp':
        return '指数函数';

      // ── 常量 ─────────────────────────────────────────────────────────
      case 'pi':
        return 'π'; // 多数 TTS 读"派"
      case 'infty':
        return '无穷大';
      case 'e':
        return 'e';

      // ── 运算符 ───────────────────────────────────────────────────────
      case 'times':
        return '乘以';
      case 'cdot':
        return '乘以';
      case 'div':
        return '除以';
      case 'pm':
        return '正负';
      case 'mp':
        return '负正';

      // ── 括号修饰（\left \right \big 等，忽略） ───────────────────────
      case 'left':
      case 'right':
      case 'big':
      case 'Big':
      case 'bigg':
      case 'Bigg':
        return '';

      // ── 取整符号（配对，用语序表达） ─────────────────────────────────
      case 'lfloor':
        return '向下取整(';
      case 'rfloor':
        return ')';
      case 'lceil':
        return '向上取整(';
      case 'rceil':
        return ')';

      default:
        return cmd; // 未知命令直接读字母
    }
  }

  // ── ^ 幂 ──────────────────────────────────────────────────────────────────

  String _power() {
    _pos++; // 跳过 '^'
    final exp = _pos < _s.length && _s[_pos] == '{'
        ? _braceContent()
        : _singleChar();
    final expText = _sub(exp);
    if (expText == '2') return '的平方';
    if (expText == '3') return '的立方';
    return '的$expText次方';
  }

  // ── | 绝对值 ──────────────────────────────────────────────────────────────

  String _absBar() {
    _pos++; // 跳过第一个 |
    final inner = StringBuffer();
    while (_pos < _s.length && _s[_pos] != '|') {
      inner.write(_next());
    }
    if (_pos < _s.length) _pos++; // 跳过第二个 |
    return '$inner的绝对值';
  }

  // ── { } 大括号（不读出，只处理内容） ─────────────────────────────────────

  String _brace() {
    final content = _braceContent();
    return _sub(content);
  }

  void _skipSub() {
    _pos++; // 跳过 '_'
    if (_pos < _s.length && _s[_pos] == '{') {
      _braceContent(); // 丢弃
    } else if (_pos < _s.length) {
      _pos++;
    }
  }

  // ── 辅助提取 ──────────────────────────────────────────────────────────────

  /// 提取 {…} 内容字符串（不含外层括号）。
  String _braceContent() {
    if (_pos >= _s.length || _s[_pos] != '{') return '';
    int depth = 0, start = _pos + 1;
    while (_pos < _s.length) {
      if (_s[_pos] == '{') {
        depth++;
      } else if (_s[_pos] == '}' && --depth == 0) {
        final content = _s.substring(start, _pos);
        _pos++;
        return content;
      }
      _pos++;
    }
    return _s.substring(start);
  }

  /// 提取 […] 内容字符串。
  String _bracketContent() {
    if (_pos >= _s.length || _s[_pos] != '[') return '';
    int depth = 0, start = _pos + 1;
    while (_pos < _s.length) {
      if (_s[_pos] == '[') {
        depth++;
      } else if (_s[_pos] == ']' && --depth == 0) {
        final content = _s.substring(start, _pos);
        _pos++;
        return content;
      }
      _pos++;
    }
    return _s.substring(start);
  }

  /// 读取单个字符作为"参数"（用于 ^2 等简写形式）。
  String _singleChar() {
    if (_pos >= _s.length) return '';
    return _s[_pos++];
  }

  /// 递归处理子表达式。
  String _sub(String s) => _Lts(s).read();

  bool _isLetter(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }
}
