import SwiftUI
import Photos
import CoreImage.CIFilterBuiltins

// --- データモデルの定義 ---

// AlbumからMusicItemに名前を変更し、曲情報にも対応
struct MusicItem: Codable {
    let wrapperType: String // "collection" (アルバム) or "track" (曲)
    let artistName: String
    let collectionName: String // アルバム名
    let trackName: String?     // 曲名 (曲の場合のみ)
    let artworkUrl100: String
    let primaryGenreName: String
    let releaseDate: String
    
    let collectionId: Int?
    let trackId: Int?

    // ★ このidプロパティを追加 ★
    var id: String {
        // 曲ならtrackId、アルバムならcollectionIdを文字列として返す
        if let trackId = trackId {
            return String(trackId)
        }
        if let collectionId = collectionId {
            return String(collectionId)
        }
        return "" // 万が一どちらもなければ空文字
    }
    
    // 表示用の名前を決定する
    var displayName: String {
        if wrapperType == "track" {
            return trackName ?? collectionName
        }
        return collectionName
    }
    
    // リリース年から西暦だけを抽出する
    var releaseYear: String {
        // "2024-07-04T07:00:00Z" のような形式から最初の4文字を取得
        return String(releaseDate.prefix(4))
    }

    // 高解像度のアートワークURLを生成する
    var highResArtworkURL: URL? {
        let highResString = artworkUrl100
            .replacingOccurrences(of: "100x100bb.jpg", with: "2000x2000bb.jpg")
        return URL(string: highResString)
    }
}

// APIのレスポンス全体のモデル
struct SearchResult: Codable {
    let results: [MusicItem]
}

// ★★★ 新機能: iPhoneサイズを追加 ★★★
enum AspectRatio: String, CaseIterable, Identifiable {
    case threeToFour = "3:4"
    case nineToSixteen = "9:16"
    case iPhone = "iPhone"
    var id: Self { self }
}

// 背景スタイルの選択肢
enum BackgroundStyle: String, CaseIterable, Identifiable {
    case blurredArtwork = "ぼかし"
    case averageColor = "単色"
    case gradient = "グラデーション"
    var id: Self { self }
}

// フォントスタイルの選択肢
enum FontStyle: String, CaseIterable, Identifiable {
    case standard = "標準フォント"
    case monospaced = "等幅フォント"
    var id: Self { self }
}


// --- 画面の定義 ---
struct ContentView: View {
    // --- State変数 (アラート用の変数を追加) ---
    @State private var itemURL: String = ""
    @State private var statusMessage: String = "" // 初期メッセージは不要に
    @State private var isProcessing = false
    
    // ★ デフォルト設定 ★
    @State private var selectedAspectRatio: AspectRatio = .threeToFour
    @State private var selectedBackgroundStyle: BackgroundStyle = .blurredArtwork
    @State private var selectedFontStyle: FontStyle = .standard
    
    // ★ アラート表示用のState ★
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    // ★ HistoryManagerを準備 ★
    @StateObject private var historyManager = HistoryManager()
    
    // ★ 履歴画面を表示するためのState ★
    @State private var showingHistory = false
    
    // ContentView の中にこの変数を追加
    @State private var isQRCodeVisible = false

    var body: some View {
        NavigationView {
            // ★ Formを使って全体を囲む ★
            Form {
                // --- 設定セクション ---
                Section(header: Label("画像スタイル設定", systemImage: "paintbrush.fill")) {
                    Picker("背景", selection: $selectedBackgroundStyle) {
                        ForEach(BackgroundStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .glassEffect()

                    Picker("アスペクト比", selection: $selectedAspectRatio) {
                        ForEach(AspectRatio.allCases) { ratio in
                            Text(ratio.rawValue).tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)
                    .glassEffect()
                    
                    Picker("フォント", selection: $selectedFontStyle) {
                        ForEach(FontStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .glassEffect()
                    
                    // ★★★ このToggleを追加 ★★★
                    Toggle(isOn: $isQRCodeVisible) {
                        Label("QRコードを表示", systemImage: "qrcode.viewfinder")
                    }
                    .tint(.accentColor)
                }
                
                // --- URL入力セクション ---
                Section(header: Label("Apple Music URL", systemImage: "link")) {
                    // ★ テキストフィールドとペーストボタンを横に並べる ★
                    HStack {
                        TextField("アルバム・曲のURLを入力", text: $itemURL)
                            // .textFieldStyle(.roundedBorder)
                            .padding(10)
                            .glassEffect()
                            .multilineTextAlignment(.center)
                        
                        // ★ ペーストボタンを追加 ★
                        Button("ペースト") {
                            if let pastedString = UIPasteboard.general.string {
                                itemURL = pastedString
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(4)
                        .glassEffect()
                    }
                }
                
                // --- 実行ボタンセクション ---
                Section {
                    Button(action: {
                        Task {
                            await processURL()
                        }
                    }) {
                        // ★ 処理中かどうかで表示を切り替え ★
                        if isProcessing {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("処理中...")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(10)
                        } else {
                            Label("画像を作成してコピー", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                                .padding(10)
                        }
                    }
                    // ★ モダンなボタンスタイルに変更 ★
                    .buttonStyle(.borderedProminent)
                    .disabled(itemURL.isEmpty || isProcessing)
                    .glassEffect()
                }
                .navigationTitle("Music Info Getter")
                // ★ ナビゲーションバーに履歴ボタンを追加 ★
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showingHistory = true
                        }) {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }
                }
                // ★ 履歴画面をシートとして表示 ★
                .sheet(isPresented: $showingHistory) {
                    HistoryView(historyManager: historyManager)
                }
                .tint(.accentColor)
            }
            .navigationTitle("Music Info Getter")
            // ★ 処理結果をアラートで表示 ★
            .alert(isPresented: $showingAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    // ContentView の中、bodyの外側に関数を追加

    private func generateQRCode(from string: String) -> UIImage? {
        // 1. 文字列をデータに変換
        let data = string.data(using: .utf8)

        // 2. QRコード生成フィルターを取得
        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        qrFilter.setValue(data, forKey: "inputMessage")
        qrFilter.setValue("H", forKey: "inputCorrectionLevel") // 誤り訂正レベル

        // 3. フィルターからCIImageを生成
        guard let ciImage = qrFilter.outputImage else { return nil }

        // 4. 画像が小さいので、くっきり見えるように拡大する
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledCIImage = ciImage.transformed(by: transform)

        // 5. 表示できるUIImageに変換して返す
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledCIImage, from: scaledCIImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // --- メインの処理関数 (アラート表示のロジックを追加) ---
    func processURL() async {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        isProcessing = true
        
        guard let id = extractID(from: itemURL) else {
            showErrorAlert(message: "有効なIDが見つかりませんでした。URLを確認してください。")
            isProcessing = false
            return
        }
        
        /*do {
            let item = try await fetchMusicInfo(id: id)
            
            if let artworkURL = item.highResArtworkURL {
                try await saveImageToLibrary(
                    from: artworkURL,
                    item: item,
                    aspectRatio: selectedAspectRatio,
                    backgroundStyle: selectedBackgroundStyle,
                    fontStyle: selectedFontStyle
                )
            }*/
        // processURL関数の中のdo-catchブロック

        do {
            let item = try await fetchMusicInfo(id: id)
            
            // 1. アートワークのURLがあるか確認
            guard let artworkURL = item.highResArtworkURL else {
                throw URLError(.badURL)
            }
            
            // 2. URLから元のアートワーク画像をダウンロード
            let (data, _) = try await URLSession.shared.data(from: artworkURL)
            guard let originalArtwork = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            
            // 3. 元の画像を使って、文字などを合成した最終的な画像を作る
            guard let finalImage = createCompositeImage(
                artwork: originalArtwork,
                item: item,
                finalAspectRatio: selectedAspectRatio,
                backgroundStyle: selectedBackgroundStyle,
                fontStyle: selectedFontStyle
            ) else {
                throw URLError(.cannotCreateFile) // 合成失敗
            }
            
            // 4. finalImageを使って、履歴と写真ライブラリに保存する
            historyManager.addHistory(item: item, artwork: finalImage)
            try await saveImageToLibrary(image: finalImage)
            
            // 5. クリップボードにコピーして成功アラート
            copyToClipboard(itemName: item.displayName, artistName: item.artistName)
            
            alertTitle = "成功！"
            alertMessage = "画像を写真ライブラリに保存し、履歴にも追加しました。"
            showingAlert = true
            
        } catch {
            showErrorAlert(message: "処理中にエラーが発生しました。\n\(error.localizedDescription)")
        }

        isProcessing = false
    }
    
    // ★ エラーアラートを簡単に表示するための関数 ★
    private func showErrorAlert(message: String) {
        alertTitle = "エラー"
        alertMessage = message
        showingAlert = true
    }
    
    // --- ContentViewの中で使う関数たち ---
    
    // 新しいsaveImageToLibrary関数
    func saveImageToLibrary(image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else {
            // アクセスが許可されなかった場合
            throw URLError(.cancelled)
        }
        
        // 引数で渡された画像を写真ライブラリに保存
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
    

    // ★★ 司令塔となる関数 ★★
    // createCompositeImage関数をまるごと入れ替え

    func createCompositeImage(artwork: UIImage, item: MusicItem, finalAspectRatio: AspectRatio, backgroundStyle: BackgroundStyle, fontStyle: FontStyle) -> UIImage? {
        return generateImage(
            from: artwork,
            name: item.displayName,
            artistName: item.artistName,
            genre: item.primaryGenreName,
            releaseYear: item.releaseYear,
            aspectRatio: finalAspectRatio,
            backgroundStyle: backgroundStyle,
            fontStyle: fontStyle,
            // ★★★ 新しい引数を渡す ★★★
            isQRCodeVisible: self.isQRCodeVisible,
            urlString: self.itemURL
        )
    }
    
    // ★★ 実際に各パーツを配置して画像を生成するヘルパー関数 ★★
    private func generateImage(from artwork: UIImage, name: String, artistName: String, genre: String, releaseYear: String, aspectRatio: AspectRatio, backgroundStyle: BackgroundStyle, fontStyle: FontStyle, isQRCodeVisible: Bool, urlString: String) -> UIImage? {
        // --- 1. キャンバスの準備 ---
        let originalArtworkWidth = artwork.size.width
        let canvasWidth = originalArtworkWidth
        let canvasHeight: CGFloat
        
        // ★★★ iPhoneサイズの場合の比率を計算 ★★★
        switch aspectRatio {
        case .threeToFour:
            canvasHeight = canvasWidth * 4.0 / 3.0
        case .nineToSixteen:
            canvasHeight = canvasWidth * 16.0 / 9.0
        case .iPhone:
            let screenRatio = UIScreen.main.bounds.height / UIScreen.main.bounds.width
            canvasHeight = canvasWidth * screenRatio
        }
        
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)

        UIGraphicsBeginImageContextWithOptions(canvasSize, false, artwork.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // --- 2. 背景の描画 ---
        switch backgroundStyle {
        case .averageColor:
            let averageColor = artwork.averageColor() ?? .white
            averageColor.setFill()
            UIRectFill(CGRect(origin: .zero, size: canvasSize))
        case .blurredArtwork:
            if let blurredBackground = artwork.blurred(radius: 30) {
                let aspectFillRect = CGRect.makeRect(aspectRatio: blurredBackground.size, insideRect: CGRect(origin: .zero, size: canvasSize))
                blurredBackground.draw(in: aspectFillRect)
            } else {
                UIColor.white.setFill()
                UIRectFill(CGRect(origin: .zero, size: canvasSize))
            }
        case .gradient:
            let dominantColors = artwork.dominantColors(maxCount: 2)
            if dominantColors.count >= 2 {
                let colors = dominantColors.map { $0.cgColor }
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0]) {
                    let startPoint = CGPoint(x: canvasSize.width / 2, y: 0)
                    let endPoint = CGPoint(x: canvasSize.width / 2, y: canvasSize.height)
                    context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
                }
            } else {
                let averageColor = artwork.averageColor() ?? .white
                averageColor.setFill()
                UIRectFill(CGRect(origin: .zero, size: canvasSize))
            }
        }

        // --- 3. アートワークとテキストのレイアウト計算 ---
        let padding = canvasWidth * 0.05
        let newArtworkWidth = canvasWidth - (padding * 2)
        let cornerRadius = newArtworkWidth * 0.03

        let primaryTextColor = backgroundStyle == .blurredArtwork || backgroundStyle == .gradient ? UIColor.white : ((artwork.averageColor() ?? .black).isLight ? UIColor.black : UIColor.white)
        let secondaryTextColor = primaryTextColor.withAlphaComponent(0.8)
        
        let textShadow = NSShadow()
        textShadow.shadowBlurRadius = 5
        textShadow.shadowOffset = CGSize(width: 1, height: 1)
        textShadow.shadowColor = UIColor.black.withAlphaComponent(0.5)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let nameFontSize = newArtworkWidth * 0.065
        let nameFont: UIFont
        let artistFontSize = newArtworkWidth * 0.05
        let artistFont: UIFont
        let detailsFontSize = newArtworkWidth * 0.04
        let detailsFont: UIFont

        switch fontStyle {
        case .standard:
            nameFont = UIFont.systemFont(ofSize: nameFontSize, weight: .bold)
            artistFont = UIFont.systemFont(ofSize: artistFontSize, weight: .regular)
            detailsFont = UIFont.systemFont(ofSize: detailsFontSize, weight: .light)
        case .monospaced:
            nameFont = UIFont.monospacedSystemFont(ofSize: nameFontSize, weight: .bold)
            artistFont = UIFont.monospacedSystemFont(ofSize: artistFontSize, weight: .regular)
            detailsFont = UIFont.monospacedSystemFont(ofSize: detailsFontSize, weight: .light)
        }

        let nameAttributes: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: primaryTextColor, .paragraphStyle: paragraphStyle, .shadow: textShadow]
        let artistAttributes: [NSAttributedString.Key: Any] = [.font: artistFont, .foregroundColor: primaryTextColor, .paragraphStyle: paragraphStyle, .shadow: textShadow]
        let detailsText = "\(genre) • \(releaseYear)"
        let detailsAttributes: [NSAttributedString.Key: Any] = [.font: detailsFont, .foregroundColor: secondaryTextColor, .paragraphStyle: paragraphStyle, .shadow: textShadow]
        
        let nameHeight = name.boundingRect(with: CGSize(width: newArtworkWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: nameAttributes, context: nil).height
        let artistHeight = artistName.boundingRect(with: CGSize(width: newArtworkWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: artistAttributes, context: nil).height
        let detailsHeight = detailsText.boundingRect(with: CGSize(width: newArtworkWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: detailsAttributes, context: nil).height
        
        let textVerticalPadding: CGFloat = 15
        let totalTextBlockHeight = nameHeight + artistHeight + detailsHeight + (textVerticalPadding * 2)
        
        var artworkRect: CGRect
        var nameRect: CGRect
        var artistRect: CGRect
        var detailsRect: CGRect
        
        // ★★★ 縦長のレイアウト（9:16とiPhone）のロジックを共通化 ★★★
        if aspectRatio == .nineToSixteen || aspectRatio == .iPhone {
            let gapBetweenArtworkAndText: CGFloat = canvasHeight * 0.05
            let totalContentHeight = newArtworkWidth + gapBetweenArtworkAndText + totalTextBlockHeight
            let startY = (canvasHeight - totalContentHeight) / 2
            
            artworkRect = CGRect(x: padding, y: startY, width: newArtworkWidth, height: newArtworkWidth)
            
            var currentY = artworkRect.maxY + gapBetweenArtworkAndText
            nameRect = CGRect(x: padding, y: currentY, width: newArtworkWidth, height: nameHeight)
            currentY += nameHeight + textVerticalPadding
            artistRect = CGRect(x: padding, y: currentY, width: newArtworkWidth, height: artistHeight)
            currentY += artistHeight + textVerticalPadding
            detailsRect = CGRect(x: padding, y: currentY, width: newArtworkWidth, height: detailsHeight)
        } else { // 3:4のレイアウト
            artworkRect = CGRect(x: padding, y: padding, width: newArtworkWidth, height: newArtworkWidth)
            let totalTextAreaHeight = canvasHeight - artworkRect.maxY
            var currentY = artworkRect.maxY + (totalTextAreaHeight - totalTextBlockHeight) / 2
            
            nameRect = CGRect(x: padding, y: currentY, width: newArtworkWidth, height: nameHeight)
            currentY += nameHeight + textVerticalPadding
            artistRect = CGRect(x: padding, y: currentY, width: newArtworkWidth, height: artistHeight)
            currentY += artistHeight + textVerticalPadding
            detailsRect = CGRect(x: padding, y: currentY, width: newArtworkWidth, height: detailsHeight)
        }
        
        // --- 4. アートワークの描画 ---
        let roundedRectPath = UIBezierPath(roundedRect: artworkRect, cornerRadius: cornerRadius)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 4), blur: 15, color: UIColor.black.withAlphaComponent(0.5).cgColor)
        UIColor.black.setFill()
        roundedRectPath.fill()
        context.restoreGState()
        roundedRectPath.addClip()
        artwork.draw(in: artworkRect)
        context.resetClip()
        
        // --- 5. テキストの描画 ---
        name.draw(in: nameRect, withAttributes: nameAttributes)
        artistName.draw(in: artistRect, withAttributes: artistAttributes)
        detailsText.draw(in: detailsRect, withAttributes: detailsAttributes)

        // ★★★ ここからQRコードの描画処理を追加 ★★★
        if isQRCodeVisible, let qrCodeImage = generateQRCode(from: urlString) {
            let qrCodeSize = newArtworkWidth * 0.12 // QRコードのサイズ
            let qrCodePadding = padding * 0.3       // 端からの余白
            
            // QRコードを描画する位置を計算 (右下、少し内側)
            let qrCodeRect = CGRect(
                x: canvasWidth - qrCodeSize - qrCodePadding,
                y: canvasHeight - qrCodeSize - qrCodePadding,
                width: qrCodeSize,
                height: qrCodeSize
            )
            
            // ★★★ 背景色をアートワークの平均色に近づける（少し明るく）★★★
            let backgroundColor = artwork.averageColor()?.withAlphaComponent(0.8) ?? UIColor.white.withAlphaComponent(0.8)
            backgroundColor.setFill()
            let roundedRectPath = UIBezierPath(roundedRect: qrCodeRect, cornerRadius: qrCodeSize * 0.15)
            roundedRectPath.fill()
            
            // ★★★ 白い枠線を描画 ★★★
            UIColor.white.setStroke()
            roundedRectPath.lineWidth = qrCodeSize * 0.02
            roundedRectPath.stroke()
            
            // QRコード本体を描画 (少し小さくマージンを取る)
            let qrCodeInset = qrCodeSize * 0.08
            qrCodeImage.draw(in: qrCodeRect.insetBy(dx: qrCodeInset, dy: qrCodeInset))
        }
        
        // --- 6. 最終的な画像の生成 ---
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
    }
    
    func extractID(from urlString: String) -> String? {
        // 1. まずは曲のID ("i=")がないか最優先でチェックする (この部分は変更なし)
        if let range = urlString.range(of: "i=") {
            let subsequentString = urlString[range.upperBound...]
            return String(subsequentString.prefix { $0.isNumber })
        }
        
        // 2. URLのパスの最後の部分からアルバムIDを抜き出す (ここが新しいロジック！)
        // これで "?l=en-US" のようなパラメータが付いていても大丈夫
        if let url = URL(string: urlString) {
            let lastPathComponent = url.lastPathComponent
            // パスの最後の部分が数字だけで構成されているか確認
            if lastPathComponent.allSatisfy({ $0.isNumber }) {
                return lastPathComponent
            }
        }
        
        // どちらにも当てはまらなかった場合
        return nil
    }
    
    func fetchMusicInfo(id: String) async throws -> MusicItem {
        let urlString = "https://itunes.apple.com/lookup?id=\(id)&country=jp&lang=ja_jp&entity=song,album"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let searchResult = try JSONDecoder().decode(SearchResult.self, from: data)
        
        if let item = searchResult.results.first {
            return item
        } else {
            throw URLError(.cannotParseResponse)
        }
    }
    
    func copyToClipboard(itemName: String, artistName: String) {
        let text = "[\(itemName)] - \(artistName)"
        UIPasteboard.general.string = text
    }
}




// --- 拡張機能 (Extensions) ---

extension UIImage {
    // 白い線をなくすためにぼかし処理を修正
    func blurred(radius: CGFloat) -> UIImage? {
        guard let ciImage = CIImage(image: self) else { return nil }
        let context = CIContext(options: nil)
        
        // 1. 画像の端を引き伸ばす（クランプ）
        let clampedImage = ciImage.clampedToExtent()
        
        // 2. ガウシアンブラーを適用
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = clampedImage
        blurFilter.radius = Float(radius)
        
        guard let blurredImage = blurFilter.outputImage else { return nil }
        
        // 3. 元の画像のサイズに切り抜く（クロップ）
        let croppedImage = blurredImage.cropped(to: ciImage.extent)
        
        // 4. CGImageに変換してUIImageを生成
        guard let cgImage = context.createCGImage(croppedImage, from: croppedImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }

    // 画像の平均色を計算してUIColorとして返す関数
    func averageColor() -> UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull!])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(bitmap[0]) / 255.0, green: CGFloat(bitmap[1]) / 255.0, blue: CGFloat(bitmap[2]) / 255.0, alpha: CGFloat(bitmap[3]) / 255.0)
    }

    // 画像から主要な色を抽出する関数
    func dominantColors(maxCount: Int) -> [UIColor] {
        // 処理を高速化するため、画像を小さくリサイズ
        let newSize = CGSize(width: 50, height: 50)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1)
        draw(in: CGRect(origin: .zero, size: newSize))
        let smallImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let cgImage = smallImage?.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return []
        }
        
        // ピクセルを数えるためにNSCountedSetを使用
        let colorSet = NSCountedSet()
        let pixelsWide = cgImage.width
        let pixelsHigh = cgImage.height
        
        for x in 0 ..< pixelsWide {
            for y in 0 ..< pixelsHigh {
                let pixelInfo: Int = ((pixelsWide * y) + x) * 4
                let r = CGFloat(bytes[pixelInfo]) / 255.0
                let g = CGFloat(bytes[pixelInfo+1]) / 255.0
                let b = CGFloat(bytes[pixelInfo+2]) / 255.0
                let a = CGFloat(bytes[pixelInfo+3]) / 255.0
                
                // 透明度が低いピクセルは無視
                guard a > 0.9 else { continue }
                
                colorSet.add(UIColor(red: r, green: g, blue: b, alpha: a))
            }
        }
        
        // 最も頻度の高い色をソートして取得
        let sortedColors = colorSet.allObjects
            .compactMap { $0 as? UIColor }
            .sorted { colorSet.count(for: $0) > colorSet.count(for: $1) }
        
        // 色の多様性を確保するため、似すぎている色を除外する
        var finalColors = [UIColor]()
        for color in sortedColors {
            // 既に選ばれた色と似すぎていないかチェック
            let isSimilar = finalColors.contains { $0.isSimilar(to: color, threshold: 0.2) }
            if !isSimilar {
                finalColors.append(color)
            }
            // 必要な数だけ集まったら終了
            if finalColors.count >= maxCount {
                break
            }
        }
        
        return finalColors
    }
}

// 色の明るさを判定するための拡張
extension UIColor {
    var isLight: Bool {
        guard let components = cgColor.components, components.count >= 3 else {
            return false
        }
        let brightness = ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000
        return brightness > 0.5
    }

    // 2つの色が似ているかを判定するヘルパー関数
    func isSimilar(to otherColor: UIColor, threshold: CGFloat = 0.1) -> Bool {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        otherColor.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        let distance = sqrt(pow(r1 - r2, 2) + pow(g1 - g2, 2) + pow(b1 - b2, 2))
        return distance < threshold
    }
}

// アスペクト比を保ったままCGRectを計算するための拡張
extension CGRect {
    static func makeRect(aspectRatio: CGSize, insideRect rect: CGRect) -> CGRect {
        let viewRatio = rect.width / rect.height
        let imageRatio = aspectRatio.width / aspectRatio.height
        let touchesHorizontal = (imageRatio > viewRatio)

        var x: CGFloat = 0, y: CGFloat = 0, width: CGFloat = 0, height: CGFloat = 0

        if touchesHorizontal {
            height = rect.height
            width = height * imageRatio
            x = (rect.width - width) / 2
            y = 0
        } else {
            width = rect.width
            height = width / imageRatio
            x = 0
            y = (rect.height - height) / 2
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}


#Preview {
    ContentView()
}
