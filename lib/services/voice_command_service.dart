import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 通过 OpenAI Whisper + Chat Completions（兼容 Anthropic）将语音指令转换为表达式操作。
/// 使用统一网关，URL/Key 不变，模型名可切换。
const _kDefaultBaseUrl = 'https://api.openai.com';

/// 默认文字模型（编辑/解析 LaTeX）
const String kDefaultChatModel = 'claude-sonnet-4-6';

/// 默认语音转写模型
const String kDefaultAudioModel = 'whisper-1';

/// 设置面板中的备选文字模型（2026-04 最新）
const List<String> kChatModelOptions = [
  'claude-sonnet-4-6',  // 默认 — 最新 Claude Sonnet
  'claude-opus-4-7',    // 旗舰
  'claude-haiku-4-5',   // 最快
  'gpt-5.5',            // OpenAI 旗舰
  'gpt-5.4-mini',       // 高吞吐
  'gpt-5.4-nano',       // 低延迟
];

/// 设置面板中的备选语音模型（2026-04）
const List<String> kAudioModelOptions = [
  'whisper-1',              // 默认 — OpenAI 经典 Whisper
  'gpt-4o-transcribe',      // 当前最佳
  'gpt-4o-mini-transcribe', // 经济版
];

class VoiceCommandService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _apiKey;
  String _baseUrl = _kDefaultBaseUrl;
  String _chatModel = kDefaultChatModel;
  String _audioModel = kDefaultAudioModel;
  String? _tempPath;

  void setApiKey(String key) => _apiKey = key.trim();
  String? get apiKey => _apiKey;
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  void setBaseUrl(String url) {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    _baseUrl = trimmed.isEmpty ? _kDefaultBaseUrl : trimmed;
  }

  String get baseUrl => _baseUrl;

  void setChatModel(String m) {
    final t = m.trim();
    if (t.isNotEmpty) _chatModel = t;
  }
  String get chatModel => _chatModel;

  void setAudioModel(String m) {
    final t = m.trim();
    if (t.isNotEmpty) _audioModel = t;
  }
  String get audioModel => _audioModel;

  // ── 录音 ─────────────────────────────────────────────────────────────────

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> startRecording() async {
    final dir = await getTemporaryDirectory();
    _tempPath =
        '${dir.path}/voice_cmd_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
      path: _tempPath!,
    );
  }

  Future<String?> stopRecordingAndRecognize(
    List<String> currentExpression,
  ) async {
    if (!await _recorder.isRecording()) return null;
    final path = await _recorder.stop();
    if (path == null || _apiKey == null || _apiKey!.isEmpty) return null;

    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 1024) return null;

    try {
      final transcript = await _whisperTranscribe(file);
      if (transcript == null || transcript.isEmpty) return null;
      final action = await _chatParseAction(transcript, currentExpression);
      return action;
    } finally {
      file.deleteSync();
    }
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }

  /// 录音停止 → Whisper 转文本 → 让 LLM 直接产出"新的整段 LaTeX"。
  ///
  /// 适用于把整个表达式当字符串编辑的页面（formula_editor_page）。
  /// 返回 `(newLatex, shouldCalculate)`：
  ///   - newLatex 为 null 表示语音失败/未变更
  ///   - shouldCalculate=true 表示用户要求计算（调用方触发）
  Future<({String? newLatex, bool shouldCalculate})>
      stopRecordingAndEditLatex(String currentLatex) async {
    if (!await _recorder.isRecording()) {
      return (newLatex: null, shouldCalculate: false);
    }
    final path = await _recorder.stop();
    if (path == null || _apiKey == null || _apiKey!.isEmpty) {
      return (newLatex: null, shouldCalculate: false);
    }
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 1024) {
      return (newLatex: null, shouldCalculate: false);
    }

    try {
      final transcript = await _whisperTranscribe(file);
      if (transcript == null || transcript.isEmpty) {
        return (newLatex: null, shouldCalculate: false);
      }
      return await _chatEditLatex(transcript, currentLatex);
    } finally {
      file.deleteSync();
    }
  }

  static const _editSystemPrompt = '''
你是一个 LaTeX 数学表达式助手。用户用中文语音说出数学算式或修改指令，你要返回**完整可计算**的 LaTeX。

只返回 JSON：{"latex": "<完整 LaTeX 字符串>", "calculate": true}

判断用户意图（关键）：
1) **新算式**：用户念出一个完整算式（如 "一加二乘三"、"计算 5 加 6"、"根号 9"、"二分之一加三分之一"）→
   忽略当前 LaTeX，直接输出该算式的 LaTeX。
2) **修改/追加**：用户用了"加上一个 X / 把 A 改成 B / 在末尾加 / 把 X 删掉"等编辑动词 →
   在原 LaTeX 基础上修改后输出。
3) 不确定时优先按"新算式"处理。

输出规范（必须严格遵守）：
- latex 字段必须是合法的 LaTeX **数学表达式**，不要 \$ 包裹、不要 \\begin{equation}、不要任何文字说明
- 必须可被数学求值器直接计算，不要保留中文（如"加"→"+"、"乘"→"\\times"、"分之"→"\\frac"）
- 常用：\\frac{a}{b}、\\sqrt{x}、\\pi、上下标 a^{2} a_{i}、\\times \\div \\pm
- 不要 a*b 这种用法，乘号统一 \\times
- calculate 字段：始终设为 true（语音流程总是自动计算）
- 完全无法理解时返回 {"latex": "<原 LaTeX 原样>", "calculate": false}

例：
- 用户说"一加二" → {"latex": "1+2", "calculate": true}
- 用户说"二分之一加三分之一" → {"latex": "\\\\frac{1}{2}+\\\\frac{1}{3}", "calculate": true}
- 当前 "1+2"，用户说"再加 5" → {"latex": "1+2+5", "calculate": true}

不要添加任何解释或额外字段。''';

  Future<({String? newLatex, bool shouldCalculate})> _chatEditLatex(
    String transcript,
    String currentLatex,
  ) async {
    final messages = [
      {'role': 'system', 'content': _editSystemPrompt},
      {
        'role': 'user',
        'content':
            '当前 LaTeX：${jsonEncode(currentLatex)}\n\n语音指令：$transcript',
      },
    ];

    final resp = await http
        .post(
          Uri.parse('$_baseUrl/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': _chatModel,
            'messages': messages,
            'max_tokens': 400,
            'temperature': 0,
            'response_format': {'type': 'json_object'},
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) {
      return (newLatex: null, shouldCalculate: false);
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final content =
        (data['choices'] as List).first['message']['content'] as String;
    try {
      final m = jsonDecode(content) as Map<String, dynamic>;
      final newLatex = (m['latex'] as String?)?.trim();
      final calc = m['calculate'] == true;
      return (newLatex: newLatex, shouldCalculate: calc);
    } catch (_) {
      return (newLatex: null, shouldCalculate: false);
    }
  }

  // ── Whisper ──────────────────────────────────────────────────────────────

  Future<String?> _whisperTranscribe(File audio) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/v1/audio/transcriptions'),
    );
    req.headers['Authorization'] = 'Bearer $_apiKey';
    req.fields['model'] = _audioModel;
    req.fields['language'] = 'zh';
    req.fields['response_format'] = 'text';
    req.files.add(await http.MultipartFile.fromPath('file', audio.path));

    final resp = await req.send().timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) return null;
    final body = await resp.stream.bytesToString();
    return body.trim();
  }

  // ── Chat ─────────────────────────────────────────────────────────────────

  static const _systemPrompt = '''
你是一个数学表达式编辑助手。用户会用中文语音指令来修改一个由 LaTeX token 组成的数学表达式。
当前表达式以 JSON 数组形式给出，每个元素是一个 LaTeX token（字符串）。

你的任务：根据用户的语音指令，返回一个 JSON 对象，描述要执行的操作。

支持的操作类型（action 字段）：
- "append"   : 在末尾追加一个 token。字段：token（字符串）
- "replace"  : 替换指定下标的 token。字段：index（整数），token（字符串）
- "delete"   : 删除指定下标的 token。字段：index（整数）
- "clear"    : 清空所有 token。无额外字段
- "calculate": 触发计算。无额外字段
- "unknown"  : 无法理解指令。字段：reason（字符串）

重要规则：
1. 只返回 JSON，不要任何解释文字
2. LaTeX token 要合法，例如分数用 \\frac{1}{2}，根号用 \\sqrt{2}，π 用 \\pi
3. 如果用户说"删除最后一个"，index = 当前表达式长度 - 1
4. 如果用户说"替换第N个"，index 从 0 开始计数（第一个 = 0）

示例：
用户说"在末尾加上加3"  → {"action":"append","token":"+3"}
用户说"把第一个换成二分之一" → {"action":"replace","index":0,"token":"\\frac{1}{2}"}
用户说"删除最后一个"（当前3个token）→ {"action":"delete","index":2}
用户说"清空" → {"action":"clear"}
用户说"计算" → {"action":"calculate"}
''';

  Future<String?> _chatParseAction(
    String transcript,
    List<String> expression,
  ) async {
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      {
        'role': 'user',
        'content': '当前表达式：${jsonEncode(expression)}\n\n语音指令：$transcript',
      },
    ];

    final resp = await http
        .post(
          Uri.parse('$_baseUrl/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': _chatModel,
            'messages': messages,
            'max_tokens': 200,
            'temperature': 0,
            'response_format': {'type': 'json_object'},
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final content =
        (data['choices'] as List).first['message']['content'] as String;
    return content.trim();
  }

  /// 将 JSON action 应用到表达式列表，返回修改后的列表。
  /// 若 action 为 "calculate" 返回 null（调用方触发计算）。
  /// 若 action 为 "unknown" 抛出 [VoiceActionException]。
  static VoiceAction parseAction(String json, List<String> expression) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final action = map['action'] as String;
    switch (action) {
      case 'append':
        final token = map['token'] as String;
        return VoiceAction.append(token);
      case 'replace':
        final idx = map['index'] as int;
        final token = map['token'] as String;
        return VoiceAction.replace(idx, token);
      case 'delete':
        final idx = map['index'] as int;
        return VoiceAction.delete(idx);
      case 'clear':
        return VoiceAction.clear();
      case 'calculate':
        return VoiceAction.calculate();
      default:
        final reason = (map['reason'] as String?) ?? '未知指令';
        throw VoiceActionException(reason);
    }
  }
}

class VoiceActionException implements Exception {
  final String reason;
  VoiceActionException(this.reason);
  @override
  String toString() => reason;
}

class VoiceAction {
  final VoiceActionType type;
  final String? token;
  final int? index;

  VoiceAction._(this.type, {this.token, this.index});
  factory VoiceAction.append(String token) =>
      VoiceAction._(VoiceActionType.append, token: token);
  factory VoiceAction.replace(int index, String token) =>
      VoiceAction._(VoiceActionType.replace, index: index, token: token);
  factory VoiceAction.delete(int index) =>
      VoiceAction._(VoiceActionType.delete, index: index);
  factory VoiceAction.clear() => VoiceAction._(VoiceActionType.clear);
  factory VoiceAction.calculate() => VoiceAction._(VoiceActionType.calculate);

  bool get isCalculate => type == VoiceActionType.calculate;
}

enum VoiceActionType { append, replace, delete, clear, calculate }
