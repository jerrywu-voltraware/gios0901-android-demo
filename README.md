# GIOS0901 Android Demo

透過藍牙廣播展示 0901SR 接收板的姿態、無線充電狀態與電力讀值。支援繁體中文、英文與亮暗色切換。

## 安裝與更新

從 [最新正式版](https://github.com/jerrywu-voltraware/gios0901-android-demo/releases/latest) 下載 APK。Android 7.0 或以上可安裝。1.0.2 起，在首頁右上角的「⋮」選單點「檢查更新」，即可查詢 GitHub 最新正式版，並在有新版時開啟 APK 下載。下載後點選 APK，依 Android 提示更新。覆蓋安裝會保留語言與外觀設定。

## 開發

目前以 Flutter 3.44.3、Android SDK 與 JDK 21 建置。在專案根目錄執行以下指令。

```sh
flutter pub get
flutter test
flutter run
```

## 發行新版

1. 在 `pubspec.yaml` 更新 `version`。例如從 `1.0.1+2` 升為 `1.0.2+3`。加號後是 Android 用來判斷更新的 build number，每次正式發行都要遞增。
2. 在原簽署機器設定 JDK 21 的 `JAVA_HOME`，執行 `.\tool\prepare-release.ps1`。腳本測試、建置並核對套件名稱、兩個版本欄位與簽章，輸出 `build/GIOS0901-Demo-版本-build.apk` 和 SHA-256。
3. 提交程式變更並推送到 `main`，為該 commit 建立對應的 Git tag。下列指令以 1.0.2 為例。
4. 在 GitHub 建立正式 Release 並附上腳本輸出的 APK。「檢查更新」依最新正式 Release 的 tag 及 APK 檔名讀取版本，不會提示安裝草稿或預覽版。

```powershell
git tag -a v1.0.2 -m "Release 1.0.2 (3)"
git push origin main v1.0.2
gh release create v1.0.2 build/GIOS0901-Demo-1.0.2-3.apk --verify-tag --latest --title "1.0.2" --generate-notes
```

### 簽章延續

既有展示手機使用套件 `com.voltraware.gios0901.demo`，由原工作站 Android debug keystore 簽署。為了讓手機能直接更新，正式 APK 須使用同一把私鑰。請將原 keystore 安全備份到版本庫以外的位置。換電腦建置時須還原原簽章，新產生的 debug keystore 會得到另一張憑證。

現有簽署憑證 SHA-256 為 `314038d83636b383d63f3da7044976d9bf8a5dcac51c2f1386d56459b0c2fe4f`。
