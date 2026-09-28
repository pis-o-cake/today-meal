/// 온디바이스 ASR 모델 파일을 앱 저장소로 꺼낸다.
///
/// 네이티브 엔진은 **실제 파일 경로**를 요구한다. Flutter 의 asset 은 APK 안에 압축돼
/// 있어 경로로 열 수 없으므로 첫 실행에 한 번 복사한다.
///
/// 모델을 내려받지 않고 번들한 이유는 **시연에서 네트워크 없이 떠야** 하기 때문이다.
/// 대가는 앱 크기 약 134MB 와 첫 실행의 복사 시간이다.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 복사해 둘 모델 파일. 이름이 바뀌면 여기와 `pubspec.yaml` 을 함께 고친다.
const _modelFiles = <String>[
  'tokens.txt',
  'bpe.model',
  'encoder-epoch-99-avg-1.int8.onnx',
  'decoder-epoch-99-avg-1.int8.onnx',
  'joiner-epoch-99-avg-1.int8.onnx',
];

/// 준비된 모델 파일의 경로.
class AsrModelPaths {
  const AsrModelPaths({
    required this.tokens,
    required this.encoder,
    required this.decoder,
    required this.joiner,
  });

  final String tokens;
  final String encoder;
  final String decoder;
  final String joiner;
}

/// 모델을 앱 저장소에 준비하고 경로를 돌려준다.
///
/// 이미 있고 크기가 같으면 다시 복사하지 않는다 — 매 실행 134MB 를 다시 쓰면 기동이
/// 느려진다.
Future<AsrModelPaths> prepareAsrModel() async {
  final dir = await getApplicationSupportDirectory();
  final target = Directory('${dir.path}/asr');
  if (!target.existsSync()) target.createSync(recursive: true);

  for (final name in _modelFiles) {
    final file = File('${target.path}/$name');
    final data = await rootBundle.load('assets/asr/$name');
    // 크기가 같으면 같은 파일로 본다. 해시까지 보면 기동이 느려진다.
    if (file.existsSync() && file.lengthSync() == data.lengthInBytes) continue;
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }

  return AsrModelPaths(
    tokens: '${target.path}/tokens.txt',
    encoder: '${target.path}/encoder-epoch-99-avg-1.int8.onnx',
    decoder: '${target.path}/decoder-epoch-99-avg-1.int8.onnx',
    joiner: '${target.path}/joiner-epoch-99-avg-1.int8.onnx',
  );
}
