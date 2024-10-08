import 'dart:io';

import 'package:cutting_room/src/assets.dart';
import 'package:ffmpeg_cli/ffmpeg_cli.dart';

import 'compositions.dart';

// TODO: figure out how to generate a color composition that plays nice
//       with video timing. Currently it causes video rendering to go
//       on forever. That's why white and black use associated PNGs.
class ColorComposition extends VirtualComposition {
  ColorComposition({
    required FfmpegColor color,
  }) : _color = color;

  final FfmpegColor _color;

  @override
  Future<bool> hasVideo() async {
    return true;
  }

  @override
  Future<bool> hasAudio() async {
    return false;
  }

  @override
  Future<Duration> computeIntrinsicDuration() async {
    return Duration.zero;
  }

  @override
  DiagnosticsNode createDiagnosticsNode() {
    return DiagnosticsNode(
      name: 'ColorComposition',
      properties: [
        PropertyNode(name: 'color: $_color'),
      ],
    );
  }

  @override
  Future<FfmpegStream> build(FfmpegBuilder builder, CompositionSettings settings) async {
    final colorStream = builder.addVideoVirtualDevice(
      "color=color=${_color.toCli()}:size=${settings.videoDimensions.width}x${settings.videoDimensions.height}:rate=30:duration='${settings.duration.inMilliseconds / 1000}'",
    );
    final audioStream = builder.addNullAudio();
    final colorWithDurationStream = builder.createStream(hasVideo: true, hasAudio: true);

    builder.addFilterChain(
      FilterChain(
        inputs: [colorStream.videoOnly],
        filters: [FpsFilter(fps: 30), TrimFilter(duration: settings.duration)],
        outputs: [colorWithDurationStream.videoOnly],
      ),
    );

    builder.addFilterChain(
      FilterChain(
        inputs: [audioStream.audioOnly],
        filters: [const ANullFilter()],
        outputs: [colorWithDurationStream.audioOnly],
      ),
    );

    return colorWithDurationStream;
  }
}

class ColorBitmapComposition extends VirtualComposition {
  ColorBitmapComposition.white({
    bool hasAudio = true,
  })  : _bitmapAsset = Assets.whitePng,
        _hasAudio = hasAudio;

  ColorBitmapComposition.black({
    bool hasAudio = true,
  })  : _bitmapAsset = Assets.blackPng,
        _hasAudio = hasAudio;

  final bool _hasAudio;
  final Asset _bitmapAsset;

  @override
  Future<bool> hasVideo() async {
    return true;
  }

  @override
  Future<bool> hasAudio() async {
    return _hasAudio;
  }

  @override
  Future<Duration> computeIntrinsicDuration() async {
    return Duration.zero;
  }

  @override
  DiagnosticsNode createDiagnosticsNode() {
    return DiagnosticsNode(
      name: 'ColorBitmapComposition',
      properties: [
        PropertyNode(name: 'asset: $_bitmapAsset'),
      ],
    );
  }

  @override
  Future<FfmpegStream> build(FfmpegBuilder builder, CompositionSettings settings) async {
    final compStream = builder.createStream(hasVideo: true, hasAudio: _hasAudio);

    final absoluteBitmapPath = await _bitmapAsset.findOrInflate(Directory("./generated_assets"));

    final colorVideoStream = builder.addAsset(absoluteBitmapPath, hasAudio: false);
    builder.addFilterChain(FilterChain(
      inputs: [colorVideoStream.videoOnly],
      filters: [
        // The bitmap is 1920x1080. Scale down, if needed.
        if (settings.videoDimensions != const Size(1920, 1080)) //
          ScaleFilter(
            width: settings.videoDimensions.width.toInt(),
            height: settings.videoDimensions.height.toInt(),
          ),
        SetSarFilter(sar: '1/1'),
        TPadFilter(
          stopDuration: settings.duration,
          stopMode: 'clone',
        ),
      ],
      outputs: [compStream.videoOnly],
    ));

    if (_hasAudio) {
      final nullAudioStream = builder.addNullAudio();
      builder.addFilterChain(
        FilterChain(
          inputs: [nullAudioStream.audioOnly],
          filters: [ATrimFilter(duration: settings.duration)],
          outputs: [compStream.audioOnly],
        ),
      );
    }

    return compStream;
  }
}
