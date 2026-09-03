// Copyright 2026 wilinz.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:ui';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 状态文案里的图标用私有区哨兵占位，渲染时由 AppGlyphText 换成自绘图标。
import '../widgets/app_icons.dart';

class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => const {
    'zh_CN': _zh,
    'en_US': _en,
  };
}

const _zh = <String, String>{
  'app_title': 'Air Calculator',
  'formula_editor_title': '公式编辑器',
  'cancel': '取消',
  'save': '保存',
  'confirm': '确定',
  'clear': '清空',
  'undo': '撤销',
  'redo': '重做',
  'restore': '撤全部',
  'restore_formula': '撤公式',
  'restore_tooltip': '撤销本次识别：还原公式与笔画',
  'restore_formula_tooltip': '仅撤回公式文本，保留画布清空状态',
  'scissor': '剪刀',
  'skeleton': '骨架',
  'recognize': '识别',
  'recognizing': '识别中',
  'recognize_insert': '识别 → 插入',
  'recognizing_dots': '识别中...',
  'recognize_failed': '识别失败，请重试',
  'recognize_prefix': '${AppGlyph.check} 识别：',
  'drawing_label': '绘制',
  'no_drawing': '禁绘',
  'handwriting': '手写',
  'air': '空中',
  'voice': '语音',
  'speak': '播报',
  'history': '历史',
  'settings': '设置',
  'history_records': '历史记录',
  'press_to_record': '长按录音',
  'set_api_key_first': '请先设置 API Key',
  'openai_settings': 'OpenAI 设置',
  'ai_settings': 'AI 设置',
  'chat_model': '文字模型',
  'audio_model': '语音模型',
  'gateway_hint': '统一网关：URL/Key 不变，模型可切换',
  'calc_history': '计算历史',
  'no_records': '暂无记录',
  'close_camera': '关闭摄像头',
  'open_air_writing': '开启空中手写',
  'processing': '处理中...',
  'equals_calculate': '= 计算',
  'camera_perm_perma_denied': '相机权限被永久拒绝，请前往设置开启',
  'camera_perm_denied': '相机权限被拒绝',
  'open_settings': '打开设置',
  'model_loading_wait': '手写模型正在加载，请稍后再试',
  'camera_init_failed_prefix': '摄像头初始化失败：',
  'retry': '重试',
  'put_hand_in_view': '请将手放入画面',
  'drawing_status': '${AppGlyph.pen} 绘制中',
  'stopped': '${AppGlyph.handStop} 停止',
  'strokes_suffix': ' 笔',
  'waiting_camera': '等待摄像头...',
  'loading_hw_model': '正在加载手写模型...',
  'write_then_recognize': '在下方手写后点"识别"',
  'model_load_failed': '模型加载失败',
  'write_first': '请先手写',
  'set_api_key_in_corner': '请先在右上角设置 API Key',
  'no_mic_perm': '无麦克风权限',
  'recording_release_to_send': '${AppGlyph.mic} 录音中…松开发送',
  'recognizing_voice': '识别中…',
  'could_not_recognize': '未能识别',
  'updated_auto_calc': '${AppGlyph.check} 已更新，自动计算',
  'error_prefix': '出错: ',
  'calc_failed': '计算失败',
  'air_draw_hint': '在屏幕上空中绘制，点"识别"识别手写内容',
  'swipe_to_move_cursor': '左右滑动移动光标',
  'tap_keyboard_input': '点击键盘输入',
  'latex_raw': 'LaTeX 原文',
  'cat_basic': '数字',
  'cat_power_root': '幂根',
  'cat_fraction': '分数',
  'cat_trig': '三角',
  'cat_log': '对数',
  'cat_other': '其他',
  'language': '语言',
  'fps_suffix': 'fps',
  // air_writing_page / controller
  'checking_camera_perm': '正在检查相机权限...',
  'starting_camera': '正在启动相机与检测器...',
  'ready_put_hand': '就绪 - 请将手放入画面',
  'init_failed_prefix': '初始化失败: ',
  'request_camera_perm': '请求相机权限',
  'go_to_settings': '前往设置',
  'copied_result': '已复制计算结果',
  'calculate': '计算',
  'delete': '删除',
  'clear_expr': '清式',
  'clear_canvas': '清画',
  'cleared_canvas': '已清空画布',
  'strokes_label': '笔画: ',
  'formula': '公式',
  'demo': '演示',
  'restored_history': '已恢复历史记录',
  'copied': '已复制',
  'edit_in_formula_editor': '在公式编辑器中修改',
  'delete_this_item': '删除此项',
  'api_settings': 'API 设置',
  'api_settings_hint': '用于语音指令识别（Whisper + GPT-4o-mini）',
  'model_load_failed_short': '模型加载失败',
  'no_hand_detected': '未检测到手部',
  'drawing_with_ratio': '${AppGlyph.pen} 绘制中 (比例: ',
  'stopped_with_ratio': '${AppGlyph.handStop} 已停止 (比例: ',
  'recognize_result_prefix': '识别: ',
  'recognize_first': '请先识别表达式',
  'calculating': '计算中...',
  'recording_dots': '录音中...',
  'voice_recognize_failed': '语音识别失败',
  'executing_calc': '执行计算',
  'completed': '${AppGlyph.check} 完成',
  'cannot_understand_prefix': '无法理解: ',
  'equals_word': '等于',
  'waiting_camera_short': '等待相机...',
  // Benchmark
  'bench_title': '推理延迟测试',
  'bench_share': '分享报告',
  'bench_run': '开始测试 (500 样本)',
  'bench_running': '测试中...',
  'bench_ready_hint': '模型就绪后点击下方按钮开始测试',
  'bench_model_ready': '模型状态: @ready',
  'bench_dataset_size': '测试集: @n 条样本',
  'bench_progress': '@done / @total',
  'bench_done': '完成 @count 条, 耗时 @seconds 秒',
  'bench_device_info': '设备信息',
  'bench_device': '设备',
  'bench_os': '操作系统',
  'bench_cpu_cores': 'CPU 核心数',
  'bench_model_info': '模型信息',
  'bench_vocab_size': '词表大小',
  'bench_results': '延迟测试结果',
  'bench_metric': '指标',
  'bench_value': '值',
  'bench_samples_tested': '测试样本数',
  'bench_avg_encoder': '编码器平均',
  'bench_avg_prefill': 'Prefill 平均',
  'bench_avg_step': '每步解码平均',
  'bench_avg_total': '总流水线平均',
  'bench_min_total': '总流水线最小',
  'bench_max_total': '总流水线最大',
  'bench_per_bucket': '按输出长度分布',
  'bench_stroke_range': 'Token 数',
  'bench_count': '样本数',
  'bench_samples_unit': '条',
  'bench_report_title': '端侧推理延迟测试报告',
  'bench_entry': '推理延迟测试',
  'load_failed': '加载失败: @error',
  'about': '关于',
  'project_repo': '项目地址',
};

const _en = <String, String>{
  'app_title': 'Air Calculator',
  'formula_editor_title': 'Formula Editor',
  'cancel': 'Cancel',
  'save': 'Save',
  'confirm': 'OK',
  'clear': 'Clear',
  'undo': 'Undo',
  'redo': 'Redo',
  'restore': 'Undo All',
  'restore_formula': 'Undo Text',
  'restore_tooltip': 'Undo recognition: restore formula and strokes',
  'restore_formula_tooltip': 'Restore formula text only, keep canvas cleared',
  'scissor': 'Cut',
  'skeleton': 'Skeleton',
  'recognize': 'Recognize',
  'recognizing': 'Recognizing',
  'recognize_insert': 'Recognize → Insert',
  'recognizing_dots': 'Recognizing...',
  'recognize_failed': 'Recognition failed, please retry',
  'recognize_prefix': '${AppGlyph.check} Recognized: ',
  'drawing_label': 'Draw',
  'no_drawing': 'No Draw',
  'handwriting': 'Write',
  'air': 'Air',
  'voice': 'Voice',
  'speak': 'Speak',
  'history': 'History',
  'settings': 'Settings',
  'history_records': 'History',
  'press_to_record': 'Hold to record',
  'set_api_key_first': 'Set API Key first',
  'openai_settings': 'OpenAI Settings',
  'ai_settings': 'AI Settings',
  'chat_model': 'Chat Model',
  'audio_model': 'Audio Model',
  'gateway_hint': 'Unified gateway: URL/Key fixed, model switchable',
  'calc_history': 'Calculation History',
  'no_records': 'No records',
  'close_camera': 'Close camera',
  'open_air_writing': 'Open air writing',
  'processing': 'Processing...',
  'equals_calculate': '= Calculate',
  'camera_perm_perma_denied':
      'Camera permission permanently denied, please enable in Settings',
  'camera_perm_denied': 'Camera permission denied',
  'open_settings': 'Open Settings',
  'model_loading_wait': 'Handwriting model is loading, please try again',
  'camera_init_failed_prefix': 'Camera init failed: ',
  'retry': 'Retry',
  'put_hand_in_view': 'Place your hand in the frame',
  'drawing_status': '${AppGlyph.pen} Drawing',
  'stopped': '${AppGlyph.handStop} Stopped',
  'strokes_suffix': ' strokes',
  'waiting_camera': 'Waiting for camera...',
  'loading_hw_model': 'Loading handwriting model...',
  'write_then_recognize': 'Write below, then tap "Recognize"',
  'model_load_failed': 'Model load failed',
  'write_first': 'Write something first',
  'set_api_key_in_corner': 'Set API Key in the top-right corner first',
  'no_mic_perm': 'No microphone permission',
  'recording_release_to_send': '${AppGlyph.mic} Recording... release to send',
  'recognizing_voice': 'Recognizing...',
  'could_not_recognize': 'Could not recognize',
  'updated_auto_calc': '${AppGlyph.check} Updated, auto calculating',
  'error_prefix': 'Error: ',
  'calc_failed': 'Calculation failed',
  'air_draw_hint': 'Draw in the air, tap "Recognize" to recognize handwriting',
  'swipe_to_move_cursor': 'Swipe to move cursor',
  'tap_keyboard_input': 'Tap keyboard to type',
  'latex_raw': 'LaTeX source',
  'cat_basic': 'Basic',
  'cat_power_root': 'Power',
  'cat_fraction': 'Frac',
  'cat_trig': 'Trig',
  'cat_log': 'Log',
  'cat_other': 'Other',
  'language': 'Language',
  'fps_suffix': 'fps',
  'checking_camera_perm': 'Checking camera permission...',
  'starting_camera': 'Starting camera and detector...',
  'ready_put_hand': 'Ready — place your hand in the frame',
  'init_failed_prefix': 'Init failed: ',
  'request_camera_perm': 'Request camera permission',
  'go_to_settings': 'Open Settings',
  'copied_result': 'Result copied',
  'calculate': 'Calc',
  'delete': 'Delete',
  'clear_expr': 'Clear Expr',
  'clear_canvas': 'Clear',
  'cleared_canvas': 'Canvas cleared',
  'strokes_label': 'Strokes: ',
  'formula': 'Formula',
  'demo': 'Demo',
  'restored_history': 'History restored',
  'copied': 'Copied',
  'edit_in_formula_editor': 'Edit in formula editor',
  'delete_this_item': 'Delete this item',
  'api_settings': 'API Settings',
  'api_settings_hint': 'For voice command recognition (Whisper + GPT-4o-mini)',
  'model_load_failed_short': 'Model load failed',
  'no_hand_detected': 'No hand detected',
  'drawing_with_ratio': '${AppGlyph.pen} Drawing (ratio: ',
  'stopped_with_ratio': '${AppGlyph.handStop} Stopped (ratio: ',
  'recognize_result_prefix': 'Result: ',
  'recognize_first': 'Recognize the expression first',
  'calculating': 'Calculating...',
  'recording_dots': 'Recording...',
  'voice_recognize_failed': 'Voice recognition failed',
  'executing_calc': 'Calculating',
  'completed': '${AppGlyph.check} Done',
  'cannot_understand_prefix': 'Cannot understand: ',
  'equals_word': 'equals',
  'waiting_camera_short': 'Waiting for camera...',
  // Benchmark
  'bench_title': 'Inference Latency Test',
  'bench_share': 'Share Report',
  'bench_run': 'Run Test (500 samples)',
  'bench_running': 'Testing...',
  'bench_ready_hint': 'Click the button below to start after model is ready',
  'bench_model_ready': 'Model status: @ready',
  'bench_dataset_size': 'Dataset: @n samples',
  'bench_progress': '@done / @total',
  'bench_done': '@count samples done in @seconds s',
  'bench_device_info': 'Device Info',
  'bench_device': 'Device',
  'bench_os': 'OS',
  'bench_cpu_cores': 'CPU Cores',
  'bench_model_info': 'Model Info',
  'bench_vocab_size': 'Vocab Size',
  'bench_results': 'Latency Results',
  'bench_metric': 'Metric',
  'bench_value': 'Value',
  'bench_samples_tested': 'Samples Tested',
  'bench_avg_encoder': 'Encoder Avg',
  'bench_avg_prefill': 'Prefill Avg',
  'bench_avg_step': 'Per-Step Decode Avg',
  'bench_avg_total': 'Total Pipeline Avg',
  'bench_min_total': 'Total Pipeline Min',
  'bench_max_total': 'Total Pipeline Max',
  'bench_per_bucket': 'By Output Length',
  'bench_stroke_range': 'Tokens',
  'bench_count': 'Count',
  'bench_samples_unit': '',
  'bench_report_title': 'On-Device Inference Latency Report',
  'bench_entry': 'Inference Latency Test',
  'load_failed': 'Load failed: @error',
  'about': 'About',
  'project_repo': 'Project repository',
};

/// Manages app locale: persists to SharedPreferences and toggles between zh/en.
class LocaleService {
  static const _kPrefKey = 'app_locale';
  static const supportedLocales = <Locale>[
    Locale('zh', 'CN'),
    Locale('en', 'US'),
  ];
  static const fallbackLocale = Locale('en', 'US');

  /// Read the stored locale once at boot. Falls back to system locale (zh→zh_CN,
  /// otherwise en_US).
  static Future<Locale> loadInitialLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kPrefKey);
    if (stored != null) {
      final parts = stored.split('_');
      if (parts.length == 2) return Locale(parts[0], parts[1]);
    }
    final sys = PlatformDispatcher.instance.locale;
    if (sys.languageCode == 'zh') return const Locale('zh', 'CN');
    return const Locale('en', 'US');
  }

  static Future<void> setLocale(Locale locale) async {
    Get.updateLocale(locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPrefKey,
      '${locale.languageCode}_${locale.countryCode ?? ''}',
    );
  }

  static Future<void> toggle() async {
    final cur = Get.locale ?? fallbackLocale;
    final next = cur.languageCode == 'zh'
        ? const Locale('en', 'US')
        : const Locale('zh', 'CN');
    await setLocale(next);
  }

  static bool get isZh => (Get.locale ?? fallbackLocale).languageCode == 'zh';
}
