# 發布給公司同事使用

本文件說明如何把「會議助理」發給同事安裝,以及日後如何更新。

- **Android** → 正式 keystore 簽章 + APK 放公司雲端/內網
- **iOS** → TestFlight(iOS 無法直接發安裝檔)

---

## 一次性準備:Android 正式 keystore

現在的 release APK 是用 **debug key** 簽的,自己測試沒問題,但**不可發給同事**:debug 簽章
每台機器不同,同事日後將無法覆蓋更新(必須卸載重裝)。

### 1. 產生 keystore(只做一次,之後永久用同一把)

在 Windows PowerShell:

```powershell
mkdir C:\Users\victor\keys
keytool -genkey -v -keystore C:\Users\victor\keys\scribe-upload.jks `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias scribe
```

會依序問密碼與姓名/單位資訊(單位資訊可隨意填,不影響安裝)。

> `keytool` 隨 JDK 附帶。找不到指令時用 Android Studio 內建的 JDK,例如
> `& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" ...`

### 2. 建立 `android/key.properties`

複製 `android/key.properties.example` 成 `android/key.properties`,填入實際值:

```properties
storePassword=剛才設定的 keystore 密碼
keyPassword=剛才設定的 key 密碼
keyAlias=scribe
storeFile=C:/Users/victor/keys/scribe-upload.jks
```

`key.properties` 與 `.jks` 都已列入 `.gitignore`,**絕對不要提交進 git**。

### ⚠️ 務必備份

把 **keystore 檔案**與**兩個密碼**異地備份(例如公司密碼管理系統)。遺失後就無法再發出
可覆蓋更新的版本,所有同事都得卸載重裝。

---

## Android:build 與分發

```powershell
git pull
flutter clean
flutter pub get
flutter build apk --release
```

產出:`build\app\outputs\flutter-apk\app-release.apk`

把這個 APK 放到公司雲端硬碟/內網/Teams,給同事連結。

**同事端安裝**:下載 APK → 點開 → 若提示「不允許安裝未知來源」,依指示允許該來源後再安裝。

首次啟動需允許:**麥克風**、**通知**(Android 13+ 前景服務需要通知才能在鎖屏持續錄音)。

> 想要「自動通知同事有新版」可改用 **Firebase App Distribution**(免費):上傳同一個 APK、
> 用 email 邀請,同事會收到新版通知。仍需上面的 keystore。

---

## iOS:TestFlight

iOS 不能直接發安裝檔。用 TestFlight(需公司 Apple Developer 帳號,team `99R5HCXZK2`)。

### 1. 在 App Store Connect 建立 App

<https://appstoreconnect.apple.com> → App → ＋ → 新增 App
- 平台:iOS
- Bundle ID:`com.netchinese.scribe`
- SKU:自訂(例如 `scribe-app`)

### 2. 打包並上傳(在 Mac 上)

```bash
flutter build ipa
```

產出 `build/ios/ipa/*.ipa`。上傳二選一:
- **Xcode**:`open ios/Runner.xcworkspace` → Product ▸ Archive → Distribute App ▸ App Store Connect
- **Transporter**(Mac App Store 免費下載):把 `.ipa` 拖進去上傳

### 3. 邀請同事

App Store Connect ▸ 你的 App ▸ TestFlight:

| 測試者類型 | 上限 | 審核 | 適用 |
|---|---|---|---|
| **內部測試** | 100 人 | **免審核,上傳後幾分鐘可用** | 同事已是 App Store Connect 成員 |
| **外部測試** | 10,000 人 | 首次需 Beta App Review(1～2 天) | 只有 email、不想加進團隊 |

**同事端**:App Store 安裝「TestFlight」→ 開啟你寄的邀請信/連結 → 安裝。**有新版會自動通知**。

---

## 日後更新版本

每次要發新版,**先在 `pubspec.yaml` 遞增版號**:

```yaml
version: 1.0.1+2    # 格式:versionName+buildNumber
```

- **Android**:`+` 後面的 build number 建議每次遞增(便於辨識版本)
- **iOS/TestFlight**:build number **必須**比上次大,否則上傳會被拒絕

然後重跑上面的 build 指令即可。因為簽章不變,**同事直接覆蓋更新,App 內資料保留**。

---

## 資料保存說明

本 App 是瘦客戶端 —— 重要資料存在 scribe server:

| 資料 | 位置 | 卸載/換簽章重裝後 |
|---|---|---|
| 會議清單、逐字稿、摘要 | **Server 資料庫** | ✅ 重新登入即回復 |
| 手機錄的錄音檔(`.wav`) | 手機本機沙盒 | ❌ 遺失(可先用「分享錄音檔」存出) |
| 設定(Server 位址等) | 本機 SharedPreferences | ❌ 需重設 |
| 登入狀態 | 本機加密儲存 | ❌ 需重新登入 |

只要**簽章不變**,正常更新不會動到任何本機資料。
