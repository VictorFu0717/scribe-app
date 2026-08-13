import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant/services/audio_convert.dart';

/// 驗證「是否為未壓縮 WAV」以檔案內容判斷。
///
/// 實測到的問題:先前用副檔名判斷,遇到內容是 WAV 卻不叫 .wav 的檔案就會跳過壓縮,
/// 分享出去仍是上百 MB 的原檔。
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('audio_convert_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File write(String name, List<int> bytes) {
    final f = File('${tmp.path}/$name');
    f.writeAsBytesSync(Uint8List.fromList(bytes));
    return f;
  }

  /// 最小 44-byte WAV 標頭(16kHz / mono / 16-bit),與 App 自產的格式相同。
  List<int> wavHeader() {
    final b = BytesBuilder();
    void str(String s) => b.add(s.codeUnits);
    void u32(int v) =>
        b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
    void u16(int v) =>
        b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
    str('RIFF');
    u32(36);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1);
    u16(1);
    u32(16000);
    u32(32000);
    u16(2);
    u16(16);
    str('data');
    u32(0);
    return b.toBytes();
  }

  test('WAV 內容即判定為 WAV —— 即使副檔名不是 .wav', () async {
    final noExt = write('recording', wavHeader());
    final wrongExt = write('recording.m4a', wavHeader());
    expect(await AudioConvert.isWav(noExt.path), isTrue);
    expect(await AudioConvert.isWav(wrongExt.path), isTrue);
  });

  test('非 WAV 內容不誤判 —— 即使叫 .wav', () async {
    // m4a 的 ftyp box(前 4 byte 是長度,接著 'ftyp')。
    final fake = write('fake.wav',
        [0, 0, 0, 24, ...'ftypM4A '.codeUnits, 0, 0, 0, 0]);
    expect(await AudioConvert.isWav(fake.path), isFalse);
  });

  test('過短或不存在的檔案回 false(不應丟例外)', () async {
    final short = write('short.wav', [0x52, 0x49]);
    expect(await AudioConvert.isWav(short.path), isFalse);
    expect(await AudioConvert.isWav('${tmp.path}/nope.wav'), isFalse);
  });
}
