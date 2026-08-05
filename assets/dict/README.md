# s2twp.txt — 簡體 → 繁體(台灣正體)轉換字典

## 用途

裝置內翻譯(Google ML Kit)的中文只有**簡體**(`zh`),沒有繁體選項,因此「英→中」的
譯文需要再轉一次繁體。`lib/services/chinese_convert.dart` 讀取本檔以純 Dart 完成轉換。

不使用現成 opencc 套件的原因:皆帶 native C++(需 NDK)或實驗性 native-assets,
會增加 iOS/Android 的跨平台編譯風險。改用「OpenCC 的字典資料 + 純 Dart 最長匹配」,
品質相同且無編譯依賴。

## 來源與授權

字典資料取自 **OpenCC (Open Chinese Convert)** 的 `s2twp` 轉換鏈:

- 專案:<https://github.com/BYVoid/OpenCC>
- 授權:**Apache License 2.0**

使用的原始字典檔:

| 檔案 | 作用 |
|---|---|
| `STPhrases.txt` | 簡→繁詞組(處理一簡多繁歧義,如 头发→頭髮) |
| `STCharacters.txt` | 簡→繁單字 |
| `TWPhrasesIT.txt` / `TWPhrasesName.txt` / `TWPhrasesOther.txt` | 台灣用語(如 软件→軟體) |
| `TWVariants.txt` | 台灣正體變體 |

## 本檔格式與體積優化

兩個區段,每行 `簡體<TAB>繁體`(原始檔多候選者取第一個,即 OpenCC 預設):

```
#S2T     ← 階段一:簡→繁(詞優先、字次之)
#TW      ← 階段二:台灣用語 + 正體變體
```

`STPhrases` 原有 49041 條,其中約 80% 用單字轉換即可得到相同結果,已濾除;
僅保留 9866 條會造成差異的詞組。字典因此由 ~1MB 降至 ~234KB,轉換品質不變。

驗證見 `test/chinese_convert_test.dart`。
