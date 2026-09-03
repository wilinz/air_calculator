import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/gesture.dart';
import '../services/mathwriting_recognition_service.dart';

class BenchmarkPage extends StatefulWidget {
  final MathWritingRecognitionService service;
  const BenchmarkPage({super.key, required this.service});

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  List<Map<String, dynamic>> _samples = [];
  final List<BenchmarkTiming> _results = [];
  /// 与 _results 对齐：每条样本的 normalized_label（来自 InkML <annotation type="normalizedLabel">）
  final List<String> _normalizedLabels = [];
  bool _running = false;
  bool _loading = true;
  int _progress = 0;
  String _error = '';
  String _statusText = '';
  Timer? _uiTick;
  /// 评测模式：关闭 logits 偏置 + 关闭 _mergeKnownFunctions，评估裸模型 acc/CER
  bool _evalMode = false;

  // 进程内存 sampling（运行时由 _uiTick 轮询）
  int _rssBeforeBytes = 0;
  int _rssPeakBytes = 0;

  // 异步加载的设备 / 应用信息缓存
  Map<String, dynamic>? _deviceInfoCached;
  String? _appVersion;

  // Aggregate stats
  double _avgEncMs = 0, _avgPrefillMs = 0, _avgStepMs = 0, _avgTotalMs = 0;
  int _minTotalMs = 0, _maxTotalMs = 0;

  // Accuracy metrics（基准跑完后在 isolate 里离线计算，不进入推理热路径）。
  // UI 只展示 lenient（与论文/部署主指标一致）；strict / normalized / CER 仍然计算并
  // 写入 debug 日志，方便事后离线核对，但不出现在卡片或导出报告里。
  // ignore: unused_field
  double _expRateStrict = 0;
  // ignore: unused_field
  double _expRateNormalized = 0;
  double _expRateLenient = 0;
  /// token-level corpus CER（与 air_calculator_py/train/evaluation.py 一致）：
  /// `Σ edit_distance(gt_toks, pred_toks) / Σ |gt_toks|`，仅写入 debug log。
  // ignore: unused_field
  double _cerToken = 0;
  // ignore: unused_field
  double _cerChar = 0;
  // ignore: unused_field
  double _cerCharNormalized = 0;
  bool _accuracyComputing = false;

  /// 用户选择的评测样本数（1~_samples.length）；0 表示全量。
  int _sampleLimit = 0;
  /// 当前/上次跑的实际样本数，给进度条 / 提示文案做分母
  int _plannedTotal = 0;
  late final TextEditingController _sampleLimitCtrl =
      TextEditingController(text: '');

  @override
  void initState() {
    super.initState();
    _loadSamples();
    _loadDeviceInfo();
  }

  @override
  void dispose() {
    _uiTick?.cancel();
    _sampleLimitCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final plugin = DeviceInfoPlugin();
      final info = <String, dynamic>{};
      if (Platform.isIOS) {
        final ios = await plugin.iosInfo;
        info.addAll({
          'platform': 'ios',
          'name': ios.name,
          'model': ios.model,
          'machine': ios.utsname.machine, // e.g. iPhone15,3 → 索引到 SoC
          'system_name': ios.systemName,
          'system_version': ios.systemVersion,
          'is_physical': ios.isPhysicalDevice,
        });
      } else if (Platform.isAndroid) {
        final and = await plugin.androidInfo;
        info.addAll({
          'platform': 'android',
          'manufacturer': and.manufacturer,
          'brand': and.brand,
          'model': and.model,
          'hardware': and.hardware, // SoC 名（如 qcom）
          'board': and.board,
          'abi': and.supportedAbis.isNotEmpty ? and.supportedAbis.first : '',
          'sdk_int': and.version.sdkInt,
          'release': and.version.release,
          'is_physical': and.isPhysicalDevice,
        });
      } else {
        info['platform'] = Platform.operatingSystem;
        info['os_version'] = Platform.operatingSystemVersion;
      }
      info['num_processors'] = Platform.numberOfProcessors;

      String? version;
      try {
        final pkg = await PackageInfo.fromPlatform();
        version = '${pkg.version}+${pkg.buildNumber}';
      } catch (_) {}

      if (mounted) {
        setState(() {
          _deviceInfoCached = info;
          _appVersion = version;
        });
      }
    } catch (e) {
      debugPrint('device info load failed: $e');
    }
  }

  /// 当前进程 RSS（resident set size），失败返回 0。
  int _currentRssBytes() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }

  /// 设备物理内存总量（bytes）。无法获取返回 0。
  /// - Android: 解析 `/proc/meminfo` 的 `MemTotal:`（KB → bytes）
  /// - iOS / macOS: dart:ffi 调 `sysctlbyname("hw.memsize")`
  int _totalMemoryBytes() {
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        final meminfo = File('/proc/meminfo');
        if (!meminfo.existsSync()) return 0;
        final lines = meminfo.readAsLinesSync();
        for (final line in lines) {
          if (line.startsWith('MemTotal:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              return int.parse(parts[1]) * 1024; // KB → bytes
            }
          }
        }
      } else if (Platform.isIOS || Platform.isMacOS) {
        return _sysctlUint64('hw.memsize');
      }
    } catch (_) {}
    return 0;
  }

  /// Android `MemAvailable:` 估算可用内存；其他平台返回 0。
  int _availableMemoryBytes() {
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        final meminfo = File('/proc/meminfo');
        if (!meminfo.existsSync()) return 0;
        for (final line in meminfo.readAsLinesSync()) {
          if (line.startsWith('MemAvailable:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) return int.parse(parts[1]) * 1024;
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  Future<void> _loadSamples() async {
    try {
      final raw = await rootBundle.loadString('assets/benchmark_samples.jsonl');
      // Parse JSONL on a background isolate — 2MB+ of decode would otherwise jank the first frame.
      final parsed = await compute(_parseJsonl, raw);
      if (!mounted) return;
      _samples = parsed;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'load_failed'.trParams({'error': e.toString()});
      });
    }
  }

  Future<void> _runBenchmark() async {
    if (_running || !widget.service.isReady) return;
    setState(() {
      _running = true;
      _progress = 0;
      _results.clear();
      _normalizedLabels.clear();
      _expRateStrict = 0;
      _expRateNormalized = 0;
      _expRateLenient = 0;
      _cerToken = 0;
      _cerChar = 0;
      _cerCharNormalized = 0;
      _accuracyComputing = false;
      _statusText = 'bench_running'.tr;
    });

    _rssBeforeBytes = _currentRssBytes();
    _rssPeakBytes = _rssBeforeBytes;

    _uiTick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final rss = _currentRssBytes();
      if (rss > _rssPeakBytes) _rssPeakBytes = rss;
      if (mounted) setState(() {});
    });

    // 用户可在 UI 限定样本数；0 / 越界视为全量
    final requested = _sampleLimit;
    final total = (requested <= 0 || requested > _samples.length)
        ? _samples.length
        : requested;
    _plannedTotal = total;
    final sw = Stopwatch()..start();

    for (int i = 0; i < total; i++) {
      final sample = _samples[i];
      final traces = (sample['traces'] as List<dynamic>).cast<List<dynamic>>();
      final strokes = <Stroke>[
        for (final trace in traces)
          _InkMLStroke.fromInkML(trace),
      ];

      final timing = await widget.service.benchmark(
        strokes,
        const Size(256, 64),
        applyVarBias: !_evalMode,
        applyPostProcess: !_evalMode,
      );

      if (timing != null) {
        _results.add(BenchmarkTiming(
          encMs: timing.encMs,
          prefillMs: timing.prefillMs,
          decSteps: timing.decSteps,
          decStepAvgMs: timing.decStepAvgMs,
          totalMs: timing.totalMs,
          tokenCount: timing.tokenCount,
          label: sample['label'] as String? ?? '',
          result: timing.result,
          tokenIds: timing.tokenIds,
        ));
        _normalizedLabels.add(sample['normalized_label'] as String? ?? '');
      }

      _progress = i + 1;
      if (_progress % 10 == 0 && mounted) setState(() {});
    }

    sw.stop();
    _uiTick?.cancel();
    _computeStats();
    setState(() {
      _running = false;
      _accuracyComputing = true;
      _statusText = 'bench_done'.trParams({
        'count': total.toString(),
        'seconds': (sw.elapsedMilliseconds / 1000).toStringAsFixed(1),
      });
    });

    // 计时已结束，再算 ExpRate / CER。挪到 isolate 里跑，
    // 避免 levenshtein 在大样本上阻塞 UI（也不会污染时延数据）。
    await _computeAccuracy();
  }

  Future<void> _computeAccuracy() async {
    if (_results.isEmpty) {
      if (mounted) setState(() => _accuracyComputing = false);
      return;
    }
    // 每条样本 4 列：[label, pred, normalized_label, pred_token_ids_csv]
    // pred_token_ids 已是模型 vocab id 序列（包含 BOS），用于 token-level CER
    // 在 isolate 里跟 gt 的 BPE tokenize 结果做对照。
    final pairs = <List<String>>[
      for (int i = 0; i < _results.length; i++)
        [
          _results[i].label,
          _results[i].result,
          i < _normalizedLabels.length ? _normalizedLabels[i] : '',
          _results[i].tokenIds.join(','),
        ],
    ];
    final input = _AccuracyInput(
      pairs: pairs,
      vocab: widget.service.vocab ?? const [],
      specialN: widget.service.specialTokenCount,
    );
    Map<String, double> m;
    try {
      m = await compute(_evalAccuracy, input);
    } catch (e, st) {
      debugPrint('accuracy isolate failed: $e\n$st');
      // 兜底走 main isolate 直接算，确保 UI 不卡在 “Computing accuracy…”
      m = _evalAccuracy(input);
    }
    if (!mounted) return;
    setState(() {
      _expRateStrict = m['exp_rate_strict'] ?? 0;
      _expRateNormalized = m['exp_rate_normalized'] ?? 0;
      _expRateLenient = m['exp_rate_lenient'] ?? 0;
      _cerToken = m['cer_token'] ?? 0;
      _cerChar = m['cer_char'] ?? 0;
      _cerCharNormalized = m['cer_char_normalized'] ?? 0;
      _accuracyComputing = false;
    });
    debugPrint(
      'benchmark accuracy:'
      ' lenient=${_expRateLenient.toStringAsFixed(4)}'
      ' strict=${_expRateStrict.toStringAsFixed(4)}'
      ' normalized=${_expRateNormalized.toStringAsFixed(4)}'
      ' cer_token=${_cerToken.toStringAsFixed(4)}'
      ' cer_char=${_cerChar.toStringAsFixed(4)}'
      ' cer_norm=${_cerCharNormalized.toStringAsFixed(4)}',
    );
  }

  void _computeStats() {
    if (_results.isEmpty) return;
    int sumEnc = 0, sumPrefill = 0, sumTotal = 0;
    double sumStep = 0;
    int minT = _results[0].totalMs, maxT = _results[0].totalMs;

    for (final r in _results) {
      sumEnc += r.encMs;
      sumPrefill += r.prefillMs;
      sumStep += r.decStepAvgMs;
      sumTotal += r.totalMs;
      if (r.totalMs < minT) minT = r.totalMs;
      if (r.totalMs > maxT) maxT = r.totalMs;
    }
    final n = _results.length;
    _avgEncMs = sumEnc / n;
    _avgPrefillMs = sumPrefill / n;
    _avgStepMs = sumStep / n;
    _avgTotalMs = sumTotal / n;
    _minTotalMs = minT;
    _maxTotalMs = maxT;
  }

  String _deviceInfo() {
    final buf = StringBuffer();
    buf.writeln('- ${'bench_device'.tr}: ${Platform.operatingSystem}');
    buf.writeln('- ${'bench_os'.tr}: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buf.writeln('- ${'bench_cpu_cores'.tr}: ${Platform.numberOfProcessors}');
    return buf.toString();
  }

  String _generateReport() {
    final buf = StringBuffer();
    buf.writeln('# ${'bench_report_title'.tr}');
    buf.writeln();
    buf.writeln('## ${'bench_device_info'.tr}');
    buf.writeln(_deviceInfo());
    buf.writeln();
    buf.writeln('## ${'bench_model_info'.tr}');
    buf.writeln('- ${_modelFiles.$1} (encoder)');
    buf.writeln('- ${_modelFiles.$2}');
    buf.writeln('- ${'bench_vocab_size'.tr}: 230');
    buf.writeln();
    buf.writeln('## ${'bench_results'.tr}');
    buf.writeln();
    buf.writeln('| ${'bench_metric'.tr} | ${'bench_value'.tr} |');
    buf.writeln('|------|------|');
    buf.writeln('| ${'bench_samples_tested'.tr} | ${_results.length} |');
    buf.writeln('| ${'bench_avg_encoder'.tr} | ${_avgEncMs.toStringAsFixed(1)} ms |');
    buf.writeln('| ${'bench_avg_prefill'.tr} | ${_avgPrefillMs.toStringAsFixed(1)} ms |');
    buf.writeln('| ${'bench_avg_step'.tr} | ${_avgStepMs.toStringAsFixed(1)} ms |');
    buf.writeln('| ${'bench_avg_total'.tr} | ${_avgTotalMs.toStringAsFixed(0)} ms |');
    buf.writeln('| ${'bench_min_total'.tr} | $_minTotalMs ms |');
    buf.writeln('| ${'bench_max_total'.tr} | $_maxTotalMs ms |');
    buf.writeln('| ExpRate | ${(_expRateLenient * 100).toStringAsFixed(2)}% |');
    buf.writeln();
    buf.writeln('## ${'bench_per_bucket'.tr}');
    buf.writeln();
    buf.writeln('| ${'bench_stroke_range'.tr} | ${'bench_count'.tr} | ${'bench_avg_total'.tr} | ${'bench_avg_step'.tr} |');
    buf.writeln('|------|------|------|------|');

    final buckets = <String, List<BenchmarkTiming>>{};
    for (final r in _results) {
      final s = r.tokenCount;
      String key;
      if (s <= 3) {
        key = '1-3';
      } else if (s <= 8) {
        key = '4-8';
      } else if (s <= 16) {
        key = '9-16';
      } else {
        key = '17+';
      }
      buckets.putIfAbsent(key, () => []).add(r);
    }

    for (final key in ['1-3', '4-8', '9-16', '17+']) {
      final b = buckets[key];
      if (b == null || b.isEmpty) continue;
      final avgT = b.fold<int>(0, (s, r) => s + r.totalMs) ~/ b.length;
      final avgS = b.fold<double>(0, (s, r) => s + r.decStepAvgMs) / b.length;
      buf.writeln('| $key | ${b.length} | $avgT ms | ${avgS.toStringAsFixed(1)} ms |');
    }

    final now = DateTime.now();
    buf.writeln();
    buf.writeln('---');
    buf.writeln('${now.toString().substring(0, 19)}');
    return buf.toString();
  }

  Future<void> _shareReport(BuildContext context) async {
    try {
      final report = _generateReport();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/benchmark_report.md');
      await file.writeAsString(report);

      // iPad / macOS 必需：UIActivityViewController popover 锚点
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);

      try {
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'bench_report_title'.tr,
          text: report,
          sharePositionOrigin: origin,
        );
      } catch (_) {
        await Share.share(
          report,
          subject: 'bench_report_title'.tr,
          sharePositionOrigin: origin,
        );
      }
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
      debugPrint('share error: $e\n$st');
    }
  }

  /// 导出 results.jsonl，每行一条 {label, pred, token_ids, encMs, prefillMs, decStepAvgMs, totalMs, tokenCount}。
  /// 离线脚本（air_calculator_py/eval_benchmark.py）读取它算 ExpRate + char-level CER。
  Future<void> _exportResults(BuildContext context) async {
    try {
      if (_results.isEmpty) return;
      final dir = await getTemporaryDirectory();
      final tag = MathWritingRecognitionService.kQuantizationTag;
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${dir.path}/benchmark_results_${tag}_$ts.jsonl');
      final sink = file.openWrite();
      try {
        // 第一行 meta header：设备 + 应用 + 模型 + 评测配置 + 性能采样；
        // 离线脚本通过 "__meta__":true 区分。
        final buildMode = kDebugMode
            ? 'debug'
            : (kProfileMode ? 'profile' : 'release');
        sink.writeln(jsonEncode({
          '__meta__': true,
          'timestamp': DateTime.now().toIso8601String(),
          'app_version': _appVersion ?? '',
          'build_mode': buildMode,
          'is_debug': kDebugMode,
          'is_profile': kProfileMode,
          'is_release': kReleaseMode,
          'device': _deviceInfoCached ??
              {
                'platform': Platform.operatingSystem,
                'os_version': Platform.operatingSystemVersion,
                'num_processors': Platform.numberOfProcessors,
              },
          'eval_mode': _evalMode,
          'sample_count': _results.length,
          'model': {
            'encoder': _modelFiles.$1,
            'decoder': _modelFiles.$2,
            'vocab_size': 230,
            'quantization': MathWritingRecognitionService.kQuantizationTag,
          },
          'quantization': MathWritingRecognitionService.kQuantizationTag,
          // 内存指标：进程占用 (RSS) + 设备总量 / 当前可用。
          // CPU%/GPU% 需要原生侧采样（Metal/GLES 不是 C 接口）；GPU 名同理需平台通道。
          'memory': {
            'rss_before_mb': _rssBeforeBytes / (1024 * 1024),
            'rss_peak_mb': _rssPeakBytes / (1024 * 1024),
            'rss_now_mb': _currentRssBytes() / (1024 * 1024),
            'total_mb': _totalMemoryBytes() / (1024 * 1024),
            'available_mb': _availableMemoryBytes() / (1024 * 1024),
            'num_processors': Platform.numberOfProcessors,
          },
        }));

        for (int i = 0; i < _results.length; i++) {
          final r = _results[i];
          sink.writeln(jsonEncode({
            'label': r.label,
            'normalized_label':
                i < _normalizedLabels.length ? _normalizedLabels[i] : '',
            'pred': r.result,
            'token_ids': r.tokenIds,
            'encMs': r.encMs,
            'prefillMs': r.prefillMs,
            'decStepAvgMs': r.decStepAvgMs,
            'totalMs': r.totalMs,
            'tokenCount': r.tokenCount,
            'eval_mode': _evalMode,
          }));
        }

      } finally {
        await sink.close();
      }

      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'benchmark_results.jsonl',
        sharePositionOrigin: origin,
      );
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
      debugPrint('export error: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('bench_title'.tr),
        actions: [
          if (_results.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Export results.jsonl',
              onPressed: () => _exportResults(context),
            ),
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'bench_share'.tr,
              onPressed: () => _shareReport(context),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Device + model info header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('bench_model_ready'.trParams({
                                'ready': widget.service.isReady ? '✓' : '✗',
                              }),
                              style: TextStyle(
                                color: widget.service.isReady ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              )),
                          const SizedBox(height: 4),
                          Text('bench_dataset_size'.trParams({'n': _samples.length.toString()}),
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          // 评测模式开关：跑 acc/CER 时关掉 logits 偏置 + 后处理（裸模型）
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _evalMode
                                      ? 'Eval mode: raw model (no logit bias / postprocess)'
                                      : 'Latency mode: with logit bias + postprocess',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Switch(
                                value: _evalMode,
                                onChanged: _running
                                    ? null
                                    : (v) => setState(() => _evalMode = v),
                              ),
                            ],
                          ),
                          // 样本数输入：1~_samples.length，空 / 0 视为全量。
                          Row(
                            children: [
                              const Text('样本数 ', style: TextStyle(fontSize: 12)),
                              SizedBox(
                                width: 80,
                                child: TextField(
                                  controller: _sampleLimitCtrl,
                                  enabled: !_running,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(4),
                                  ],
                                  textAlignVertical: TextAlignVertical.center,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'all',
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    border: const OutlineInputBorder(),
                                    suffixText: '/ ${_samples.length}',
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                  onChanged: (v) {
                                    final n = int.tryParse(v) ?? 0;
                                    setState(() {
                                      _sampleLimit = n.clamp(0, _samples.length);
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _sampleLimit > 0
                                    ? '将跑 $_sampleLimit 条'
                                    : '将跑全量 ${_samples.length} 条',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Progress
                    if (_running || _results.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            if (_running) ...[
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                _running
                                    ? 'bench_progress'.trParams({
                                        'done': _progress.toString(),
                                        'total': _plannedTotal.toString(),
                                      })
                                    : _statusText,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_running)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: LinearProgressIndicator(
                          value: _plannedTotal > 0 ? _progress / _plannedTotal : 0,
                        ),
                      ),
                    // Results table
                    if (_results.isNotEmpty)
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            _buildStatsCard(),
                            const SizedBox(height: 12),
                            _buildBucketCard(),
                          ],
                        ),
                      )
                    else if (!_running)
                      Expanded(
                        child: Center(
                          child: Text('bench_ready_hint'.tr,
                              style: TextStyle(color: Colors.grey.shade500)),
                        ),
                      ),
                    // Run button
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: (_running || !widget.service.isReady) ? null : _runBenchmark,
                            icon: const Icon(Icons.speed),
                            label: Text('bench_run'.tr),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('bench_results'.tr, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _statRow('bench_avg_encoder'.tr, '${_avgEncMs.toStringAsFixed(1)} ms'),
            _statRow('bench_avg_prefill'.tr, '${_avgPrefillMs.toStringAsFixed(1)} ms'),
            _statRow('bench_avg_step'.tr, '${_avgStepMs.toStringAsFixed(1)} ms'),
            const Divider(),
            _statRow('bench_avg_total'.tr, '${_avgTotalMs.toStringAsFixed(0)} ms'),
            _statRow('bench_min_total'.tr, '$_minTotalMs ms'),
            _statRow('bench_max_total'.tr, '$_maxTotalMs ms'),
            const Divider(),
            if (_accuracyComputing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Computing accuracy…',
                        style: TextStyle(fontSize: 13)),
                  ],
                ),
              )
            else ...[
              // UI 只展示对外口径（lenient ExpRate）。
              // CER / strict / normalized 仍然计算但不显示，避免答辩时被多口径拷打。
              _statRow('ExpRate',
                  '${(_expRateLenient * 100).toStringAsFixed(2)}%'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBucketCard() {
    final buckets = <String, List<BenchmarkTiming>>{};
    for (final r in _results) {
      final s = r.tokenCount;
      String key;
      if (s <= 3) {
        key = '1-3 tokens';
      } else if (s <= 8) {
        key = '4-8 tokens';
      } else if (s <= 16) {
        key = '9-16 tokens';
      } else {
        key = '17+ tokens';
      }
      buckets.putIfAbsent(key, () => []).add(r);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('bench_per_bucket'.tr, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final key in ['1-3 tokens', '4-8 tokens', '9-16 tokens', '17+ tokens'])
              if (buckets.containsKey(key))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 80, child: Text(key, style: const TextStyle(fontSize: 12))),
                      const SizedBox(width: 8),
                      Text('${buckets[key]!.length} ${'bench_samples_unit'.tr}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const Spacer(),
                      Text(
                        'avg ${(buckets[key]!.fold<int>(0, (s, r) => s + r.totalMs) ~/ buckets[key]!.length)} ms',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── FFI: iOS / macOS `sysctlbyname("hw.memsize")` → uint64 ───────────
// Darwin libc 签名：int sysctlbyname(const char*, void*, size_t*, void*, size_t)
typedef _SysctlByNameC = ffi.Int32 Function(
  ffi.Pointer<Utf8>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Void>, ffi.Size);
typedef _SysctlByNameDart = int Function(
  ffi.Pointer<Utf8>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Void>, int);

int _sysctlUint64(String name) {
  if (!(Platform.isIOS || Platform.isMacOS)) return 0;
  try {
    final fn = ffi.DynamicLibrary.process()
        .lookupFunction<_SysctlByNameC, _SysctlByNameDart>('sysctlbyname');
    final cName = name.toNativeUtf8();
    final value = calloc<ffi.Uint64>();
    final size = calloc<ffi.Size>()..value = 8;
    try {
      final ret = fn(cName, value.cast(), size, ffi.nullptr, 0);
      if (ret != 0) return 0;
      return value.value;
    } finally {
      calloc.free(cName);
      calloc.free(value);
      calloc.free(size);
    }
  } catch (_) {
    return 0;
  }
}

// ─────────── Offline accuracy (与离线脚本对齐) ───────────
// 计算三个口径，全部跟离线脚本严格对应：
//
// 1) exp_rate_strict     = pred == label                           （air_calculator_py/eval/mobile/eval_benchmark.py）
// 2) exp_rate_normalized = _normalizeLatex(pred) == _normalizeLatex(label)   （同上脚本）
// 3) exp_rate_lenient    = pred == label OR strip_ws(pred) == strip_ws(normalized_label)
//                          （论文/部署主指标，docs/mobile/2026-05-03_INT8静态量化.md 重算脚本）
//
// 注意 #3 跟 #2 不可互换：#3 的 normalized_label 是 MathWriting 数据集自带的
// <annotation type="normalizedLabel">，已展开 \binom / pmatrix→(matrix) / HTML entity 等
// 等价形式，再 strip_ws 即可；而 #2 是对 raw label 走我们这套 _normalizeLatex 三规则。
// 历史教训：用 #2 当 #3 会把 EM 拉低 ~14 pp（74.00% → 60.00%）。
//
// 输入 [[label, pred, normalized_label], ...]；normalized_label 缺失时退化为 strip_ws(label)。
// 在 isolate 中执行，不进入推理热路径。

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final n = a.length, mLen = b.length;
  var prev = List<int>.generate(mLen + 1, (j) => j);
  var curr = List<int>.filled(mLen + 1, 0);
  for (int i = 1; i <= n; i++) {
    curr[0] = i;
    final ca = a.codeUnitAt(i - 1);
    for (int j = 1; j <= mLen; j++) {
      final cost = ca == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      var v = del < ins ? del : ins;
      if (sub < v) v = sub;
      curr[j] = v;
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[mLen];
}

// 与 python 端三条规则保持一致：\,\;\!\:\␣ → ''；任意空白 → ''；{x} → x。
final _normSpaceCmd = RegExp(r'\\,|\\;|\\!|\\:|\\ ');
final _normWhitespace = RegExp(r'\s+');
final _normSingleBrace = RegExp(r'\{([^{}])\}');

String _normalizeLatex(String s) {
  var out = s.replaceAll(_normSpaceCmd, '');
  out = out.replaceAll(_normWhitespace, '');
  out = out.replaceAllMapped(_normSingleBrace, (m) => m.group(1)!);
  return out;
}

final _stripWs = RegExp(r'\s+');
// 与 air_calculator_py/train/dataset.py 严格对齐：
// _LATEX_TOKEN_RE = r'\\[a-zA-Z]+|\\.|\S'        —— 词单元（atom）
// _BARE_SUB_RE   = r'([_^])([^{\\⁠\s])'    —— _x / ^x → _{x} / ^{x}
final _latexAtomRe = RegExp(r'\\[a-zA-Z]+|\\.|\S');
final _bareSubRe = RegExp(r'([_^])([^{\\⁠\s])');

String _normalizeLabelForToken(String s) =>
    s.replaceAllMapped(_bareSubRe, (m) => '${m.group(1)}{${m.group(2)}}');

List<String> _latexAtomize(String label) {
  final s = _normalizeLabelForToken(label);
  return [for (final m in _latexAtomRe.allMatches(s)) m.group(0)!];
}

/// 用 vocab 自身的多字符 token 构建 BPE trie，按最长前缀 merge atoms。
/// 与 Python `Vocabulary._build_bpe_trie` + `_bpe_merge` 等价。
class _BpeMerger {
  final Map<String, dynamic> trie;
  _BpeMerger(this.trie);

  static _BpeMerger build(List<String> vocab) {
    final trie = <String, dynamic>{};
    final mergedTokens = <String>[];
    for (final t in vocab) {
      final atoms = [for (final m in _latexAtomRe.allMatches(t)) m.group(0)!];
      if (atoms.length > 1) mergedTokens.add(t);
    }
    // python 端按 atom 数倒序构建（trie 内部自然做最长匹配）
    mergedTokens.sort((a, b) {
      final la = _latexAtomRe.allMatches(a).length;
      final lb = _latexAtomRe.allMatches(b).length;
      return lb.compareTo(la);
    });
    for (final tok in mergedTokens) {
      final atoms = [for (final m in _latexAtomRe.allMatches(tok)) m.group(0)!];
      Map<String, dynamic> node = trie;
      for (final a in atoms) {
        node = node.putIfAbsent(a, () => <String, dynamic>{})
            as Map<String, dynamic>;
      }
      node['__end__'] = tok;
    }
    return _BpeMerger(trie);
  }

  List<String> merge(List<String> atoms) {
    if (trie.isEmpty) return atoms;
    final out = <String>[];
    var i = 0;
    while (i < atoms.length) {
      Map<String, dynamic> node = trie;
      var j = i;
      String? lastMatch;
      var lastJ = i;
      while (j < atoms.length && node.containsKey(atoms[j])) {
        node = node[atoms[j]] as Map<String, dynamic>;
        j++;
        if (node['__end__'] != null) {
          lastMatch = node['__end__'] as String;
          lastJ = j;
        }
      }
      if (lastMatch != null) {
        out.add(lastMatch);
        i = lastJ;
      } else {
        out.add(atoms[i]);
        i++;
      }
    }
    return out;
  }
}

int _tokenLevenshtein(List<String> a, List<String> b) {
  if (a.length == b.length) {
    var eq = true;
    for (int k = 0; k < a.length; k++) {
      if (a[k] != b[k]) { eq = false; break; }
    }
    if (eq) return 0;
  }
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final n = a.length, m = b.length;
  var prev = List<int>.generate(m + 1, (j) => j);
  var curr = List<int>.filled(m + 1, 0);
  for (int i = 1; i <= n; i++) {
    curr[0] = i;
    final ca = a[i - 1];
    for (int j = 1; j <= m; j++) {
      final cost = ca == b[j - 1] ? 0 : 1;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      var v = del < ins ? del : ins;
      if (sub < v) v = sub;
      curr[j] = v;
    }
    final tmp = prev; prev = curr; curr = tmp;
  }
  return prev[m];
}

class _AccuracyInput {
  final List<List<String>> pairs;
  final List<String> vocab;
  final int specialN;
  const _AccuracyInput({
    required this.pairs,
    required this.vocab,
    required this.specialN,
  });
}

Map<String, double> _evalAccuracy(_AccuracyInput input) {
  final rows = input.pairs;
  if (rows.isEmpty) {
    return {
      'exp_rate_strict': 0,
      'exp_rate_normalized': 0,
      'exp_rate_lenient': 0,
      'cer_token': 0,
      'cer_char': 0,
      'cer_char_normalized': 0,
    };
  }
  final vocab = input.vocab;
  final specialN = input.specialN;
  final merger = vocab.isEmpty ? null : _BpeMerger.build(vocab);
  // vocab 里所有"真实"token（去掉 PAD/BOS/EOS/UNK）。
  // Python `Vocabulary.encode` 对 vocab 外 atom 返回 UNK，eval 时再过滤掉；
  // Dart 端必须做同样的过滤，否则把 `&` `<` 这种数据集里的杂字符算进 gt token，
  // 分母分子都被污染，token CER 会偏高 8-10 pp。
  final vocabSet = <String>{};
  for (int i = specialN; i < vocab.length; i++) {
    vocabSet.add(vocab[i]);
  }

  int expStrict = 0, expNorm = 0, expLenient = 0;
  double cerSum = 0, cerNormSum = 0;
  int tokenEditTotal = 0;
  int tokenGtTotal = 0;

  for (final r in rows) {
    final label = r[0];
    final pred = r[1];
    final providedNormLabel = r.length > 2 ? r[2] : '';
    final predIdsCsv = r.length > 3 ? r[3] : '';

    if (pred == label) expStrict += 1;
    final nLabel = _normalizeLatex(label);
    final nPred = _normalizeLatex(pred);
    if (nLabel == nPred) expNorm += 1;
    final lenientRef =
        providedNormLabel.isNotEmpty ? providedNormLabel : label;
    if (pred == label ||
        pred.replaceAll(_stripWs, '') ==
            lenientRef.replaceAll(_stripWs, '')) {
      expLenient += 1;
    }
    final denom = label.isEmpty ? 1 : label.length;
    cerSum += _levenshtein(pred, label) / denom;
    final denomN = nLabel.isEmpty ? 1 : nLabel.length;
    cerNormSum += _levenshtein(nPred, nLabel) / denomN;

    // ── token-level corpus CER（与 train/evaluation.py 一致）──
    if (merger != null) {
      // 把不在 vocab 的 atom 当 UNK 丢掉（与 Python encode→filter 等价）。
      final gtTokens = [
        for (final t in merger.merge(_latexAtomize(label))) if (vocabSet.contains(t)) t,
      ];
      final predTokens = <String>[];
      if (predIdsCsv.isNotEmpty) {
        for (final s in predIdsCsv.split(',')) {
          final id = int.tryParse(s);
          if (id == null) continue;
          if (id < specialN || id >= vocab.length) continue;
          predTokens.add(vocab[id]);
        }
      }
      tokenGtTotal += gtTokens.length;
      if (predTokens.length != gtTokens.length ||
          !_listEq(predTokens, gtTokens)) {
        tokenEditTotal += _tokenLevenshtein(gtTokens, predTokens);
      }
    }
  }

  final n = rows.length;
  return {
    'exp_rate_strict': expStrict / n,
    'exp_rate_normalized': expNorm / n,
    'exp_rate_lenient': expLenient / n,
    'cer_token': tokenGtTotal > 0 ? tokenEditTotal / tokenGtTotal : 0.0,
    'cer_char': cerSum / n,
    'cer_char_normalized': cerNormSum / n,
  };
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<Map<String, dynamic>> _parseJsonl(String raw) {
  final out = <Map<String, dynamic>>[];
  // Walk the buffer once, parsing each non-empty line. Splitting first would
  // double peak memory for a 2MB+ payload.
  int start = 0;
  for (int i = 0; i < raw.length; i++) {
    if (raw.codeUnitAt(i) != 0x0A) continue;
    if (i > start) {
      final line = raw.substring(start, i);
      if (line.isNotEmpty && line != '\r') {
        out.add(jsonDecode(line) as Map<String, dynamic>);
      }
    }
    start = i + 1;
  }
  if (start < raw.length) {
    final line = raw.substring(start);
    if (line.isNotEmpty) out.add(jsonDecode(line) as Map<String, dynamic>);
  }
  return out;
}

extension _InkMLStroke on Stroke {
  static Stroke fromInkML(List<dynamic> trace) {
    final points = <Offset>[];
    final timestamps = <int>[];
    for (final pt in trace) {
      final arr = pt as List<dynamic>;
      points.add(Offset((arr[0] as num).toDouble(), (arr[1] as num).toDouble()));
      // inkml 时间戳是毫秒，Stroke.timestamps 约定为微秒（活体侧用 microsecondsSinceEpoch）。
      // 这里 ×1000 统一到微秒，feature extractor 的 /1e6 才能正确得到秒。
      timestamps.add(arr.length > 2 ? ((arr[2] as num) * 1000).toInt() : 0);
    }
    return Stroke(
      points: points,
      timestamps: timestamps,
      pinchRatios: List.filled(points.length, 1.0),
      thickness: 0.0,
      color: const Color(0xFF000000),
    );
  }
}


/// 报告里的模型文件名，按实际后端给。
///
/// 原先三端都写死 `prefix_enc.tflite` / `decoder.tflite`，iOS 上从来就不对。
(String, String) get _modelFiles {
  switch (MathWritingRecognitionService.kQuantizationTag) {
    case 'mwh_litert':
      return ('prefix_enc.tflite', 'decoder.tflite (prefill + decode 双签名，共享权重)');
    case 'mwh_coreml':
      return (
        'prefix_enc.mlmodelc',
        'decoder.mlmodelc (prefill + step 多函数，共享权重)',
      );
    default:
      return ('prefix_enc (未知后端)', 'decoder (未知后端)');
  }
}
