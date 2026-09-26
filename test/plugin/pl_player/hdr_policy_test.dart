import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/plugin/pl_player/models/hdr_playback.dart';
import 'package:PiliPlus/plugin/pl_player/utils/hdr_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HdrPolicy.classifyTransfer', () {
    test('PQ 编码识别为 HDR', () {
      expect(
        HdrPolicy.classifyTransfer('pq', 4.9),
        VideoDynamicRange.hdr10,
      );
      expect(
        HdrPolicy.classifyTransfer('smpte2084', null),
        VideoDynamicRange.hdr10,
      );
    });

    test('HLG 编码识别为 HDR', () {
      expect(HdrPolicy.classifyTransfer('hlg', 1.0), VideoDynamicRange.hlg);
      expect(
        HdrPolicy.classifyTransfer('arib-std-b67', null),
        VideoDynamicRange.hlg,
      );
    });

    test('SDR 传递函数识别为 SDR', () {
      for (final gamma in ['bt.1886', 'srgb', 'linear', 'bt.709', 'gamma2.4']) {
        expect(
          HdrPolicy.classifyTransfer(gamma, 1.0),
          VideoDynamicRange.sdr,
          reason: gamma,
        );
      }
    });

    test('元数据缺失时不猜测，只有信号峰值能佐证 HDR', () {
      expect(HdrPolicy.classifyTransfer(null, null), isNull);
      expect(HdrPolicy.classifyTransfer('auto', 1.0), isNull);
      expect(
        HdrPolicy.classifyTransfer('auto', 4.9),
        VideoDynamicRange.hdr10,
      );
      // 不以位深或色域单独判定 HDR
      expect(HdrPolicy.classifyTransfer(null, 1.0), isNull);
    });

    test('实测取值：HDR10 为 pq/4.9261，SDR 为 bt.1886/0', () {
      expect(
        HdrPolicy.classifyTransfer('pq', 4.9261),
        VideoDynamicRange.hdr10,
      );
      expect(HdrPolicy.classifyTransfer('bt.1886', 0), VideoDynamicRange.sdr);
      expect(HdrPolicy.classifyTransfer('hlg', 4.9261), VideoDynamicRange.hlg);
    });
  });

  group('HdrPolicy.resolve', () {
    test('SDR 片源按 SDR 输出', () {
      const info = HdrPlaybackInfo();
      expect(info.output, HdrOutputMode.sdr);

      final resolved = HdrPolicy.resolve(
        decoded: const HdrVideoParams(gamma: 'bt.1886', primaries: 'bt.709'),
      );
      expect(resolved.source, VideoDynamicRange.sdr);
      expect(resolved.output, HdrOutputMode.sdr);
      expect(resolved.reason, HdrFallbackReason.notHdr);
      expect(resolved.displayText, 'SDR');
    });

    test('未识别到片源时保持未知', () {
      final resolved = HdrPolicy.resolve();
      expect(resolved.source, VideoDynamicRange.unknown);
      expect(resolved.output, HdrOutputMode.sdr);
    });

    test('HDR 片源在当前 8 位纹理链路回退到 SDR', () {
      final pq = HdrPolicy.resolve(
        decoded: const HdrVideoParams(gamma: 'pq', primaries: 'bt.2020'),
      );
      expect(pq.source, VideoDynamicRange.hdr10);
      expect(pq.output, HdrOutputMode.sdr);
      expect(pq.reason, HdrFallbackReason.rendererSdr);
      expect(pq.isHdrSource, isTrue);
      expect(pq.displayText, 'HDR10 (PQ) → SDR（当前渲染链路仅支持 SDR）');

      final hlg = HdrPolicy.resolve(
        decoded: const HdrVideoParams(gamma: 'hlg'),
      );
      expect(hlg.source, VideoDynamicRange.hlg);
      expect(hlg.reason, HdrFallbackReason.rendererSdr);
    });

    test('播放器不支持色彩参数时标记参数回退', () {
      final resolved = HdrPolicy.resolve(
        decoded: const HdrVideoParams(gamma: 'pq'),
        optionUnsupported: true,
      );
      expect(resolved.reason, HdrFallbackReason.paramUnsupported);
    });

    test('杜比视界与 HDR Vivid 标记优先于解码结果', () {
      final dv = HdrPolicy.resolve(
        decoded: const HdrVideoParams(gamma: 'pq', primaries: 'bt.2020'),
        hint: HdrSourceFormat.dolbyVision,
      );
      expect(dv.source, VideoDynamicRange.dolbyVision);
      expect(dv.output, HdrOutputMode.sdr);
      expect(dv.reason, HdrFallbackReason.rendererSdr);

      final vivid = HdrPolicy.resolve(
        hint: HdrSourceFormat.hdrVivid,
      );
      expect(vivid.source, VideoDynamicRange.hdrVivid);
      expect(vivid.reason, HdrFallbackReason.rendererSdr);
    });

    test('HDR 标记的片源解码为 SDR 时提示 HDR 层无法解码', () {
      final dv = HdrPolicy.resolve(
        decoded: const HdrVideoParams(gamma: 'bt.1886'),
        hint: HdrSourceFormat.dolbyVision,
      );
      expect(dv.source, VideoDynamicRange.dolbyVision);
      expect(dv.reason, HdrFallbackReason.hdrLayerUnsupported);

      final vivid = HdrPolicy.resolve(
        decoded: const HdrVideoParams(gamma: 'bt.1886'),
        hint: HdrSourceFormat.hdrVivid,
      );
      expect(vivid.reason, HdrFallbackReason.hdrLayerUnsupported);
    });

    test('HDR10 画质提示与解码结果冲突时以解码结果为准', () {
      final resolved = HdrPolicy.resolve(
        decoded: const HdrVideoParams(gamma: 'bt.1886'),
        hint: HdrSourceFormat.hdr10,
      );
      expect(resolved.source, VideoDynamicRange.sdr);
      expect(resolved.reason, HdrFallbackReason.notHdr);
    });

    test('HDR10 画质提示在解码参数缺失时仍标记为 HDR', () {
      final resolved = HdrPolicy.resolve(hint: HdrSourceFormat.hdr10);
      expect(resolved.source, VideoDynamicRange.hdr10);
      expect(resolved.reason, HdrFallbackReason.rendererSdr);
    });
  });

  group('HdrSourceFormat.from', () {
    test('由画质识别片源格式', () {
      expect(
        HdrSourceFormat.from(quality: VideoQuality.hdr),
        HdrSourceFormat.hdr10,
      );
      expect(
        HdrSourceFormat.from(quality: VideoQuality.dolbyVision),
        HdrSourceFormat.dolbyVision,
      );
      expect(
        HdrSourceFormat.from(quality: VideoQuality.hdrVivid),
        HdrSourceFormat.hdrVivid,
      );
      expect(
        HdrSourceFormat.from(quality: VideoQuality.high1080),
        HdrSourceFormat.none,
      );
      expect(HdrSourceFormat.from(), HdrSourceFormat.none);
    });

    test('由编码识别杜比视界', () {
      expect(
        HdrSourceFormat.from(
          quality: VideoQuality.high1080,
          codecs: 'dvh1.05.06',
        ),
        HdrSourceFormat.dolbyVision,
      );
    });
  });

  group('HdrPlaybackTracker', () {
    test('换源时按画质标记重置，解码参数到达后修正', () {
      final tracker = HdrPlaybackTracker();
      expect(tracker.info, HdrPlaybackInfo.unknown);

      // 切换到杜比视界片源，解码参数尚未到达
      final reset = tracker.reset(HdrSourceFormat.dolbyVision);
      expect(reset.source, VideoDynamicRange.dolbyVision);
      expect(reset.isHdrSource, isTrue);

      // 解码参数到达，确认为 PQ
      // 状态与画质标记一致，无需变更
      expect(
        tracker.update(
          const HdrVideoParams(gamma: 'pq', primaries: 'bt.2020'),
        ),
        isFalse,
      );
      expect(tracker.info.source, VideoDynamicRange.dolbyVision);
      expect(tracker.info.reason, HdrFallbackReason.rendererSdr);

      // 同一参数重复上报保持一致
      expect(
        tracker.update(
          const HdrVideoParams(gamma: 'pq', primaries: 'bt.2020'),
        ),
        isFalse,
      );
    });

    test('无画质标记时由解码参数首次确定片源类型', () {
      final tracker = HdrPlaybackTracker()..reset(HdrSourceFormat.none);
      expect(tracker.info.source, VideoDynamicRange.unknown);

      expect(
        tracker.update(const HdrVideoParams(gamma: 'pq', sigPeak: 4.9261)),
        isTrue,
      );
      expect(tracker.info.source, VideoDynamicRange.hdr10);
      expect(tracker.info.reason, HdrFallbackReason.rendererSdr);
    });

    test('HDR 片源切换到 SDR 片源后恢复 SDR 判定', () {
      final tracker = HdrPlaybackTracker()
        ..reset(HdrSourceFormat.hdr10);
      tracker.update(const HdrVideoParams(gamma: 'pq', sigPeak: 4.9261));
      expect(tracker.info.source, VideoDynamicRange.hdr10);

      // 新片源为普通画质
      tracker.reset(HdrSourceFormat.none);
      expect(tracker.info.isHdrSource, isFalse);
      tracker.update(const HdrVideoParams(gamma: 'bt.1886', sigPeak: 0));
      expect(tracker.info.source, VideoDynamicRange.sdr);
      expect(tracker.info.reason, HdrFallbackReason.notHdr);
    });

    test('播放器不支持色彩参数时同步到状态', () {
      final tracker = HdrPlaybackTracker()
        ..reset(HdrSourceFormat.hdr10, optionUnsupported: true);
      tracker.update(
        const HdrVideoParams(gamma: 'pq'),
        optionUnsupported: true,
      );
      expect(tracker.info.reason, HdrFallbackReason.paramUnsupported);
    });
  });
}
