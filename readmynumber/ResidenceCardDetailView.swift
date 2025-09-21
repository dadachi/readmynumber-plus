import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

struct ResidenceCardDetailView: View {
    let cardData: ResidenceCardData
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @State private var showingExportSheet = false
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @StateObject private var dataManager = ResidenceCardDataManager.shared
    @State private var frontImageJPEG: UIImage?
    @State private var faceImageJPEG: UIImage?
    @State private var compositeImageWithTransparency: UIImage?
    @State private var showingRawDataExportSheet = false
    @State private var testModeEnabled = false

    var body: some View {
        ZStack {
            // 背景グラデーション
            LinearGradient(
                gradient: Gradient(colors: [Color.white, Color(UIColor.systemGray6)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // メインのスクロール可能な領域
            ScrollView {
                VStack(spacing: 20) {
                    // タイトル
                    Text("在留カード情報")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top, 20)

                    // 基本情報カード
                    VStack(spacing: 12) {
                        // ヘッダー部分
                        HStack {
                            Image(systemName: "person.text.rectangle.fill")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundColor(Color.green)
                                .symbolRenderingMode(.hierarchical)

                            Text("基本情報")
                                .font(.headline)
                                .fontWeight(.bold)

                            Spacer()

                            Text("在留カード")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .padding(.bottom, 8)

                        Divider()
                            .background(Color.green.opacity(0.3))

                        // 共通データ要素
                        if let versionData = cardData.parseTLV(data: cardData.commonData, tag: 0xC0),
                           let version = String(data: versionData, encoding: .utf8) {
                            InfoCardView(title: "仕様バージョン", value: version, systemImage: "info.circle")
                        }

                        // カード種別
                        let cardType = parseCardTypeString(from: cardData.cardType)
                        InfoCardView(title: "カード種別", value: cardType, systemImage: "creditcard")

                        // 住所関連情報
                        // 追記書き込み年月日
                        if let updateDate = parseAddressUpdateDate(from: cardData.address) {
                            InfoCardView(title: "住所更新日", value: updateDate, systemImage: "calendar")
                        }
                        
                        // 市町村コード
                        if let municipalityCode = parseMunicipalityCode(from: cardData.address) {
                            InfoCardView(title: "市町村コード", value: municipalityCode, systemImage: "building.2")
                        }
                        
                        // 住居地
                        if let addressString = parseAddressData(from: cardData.address) {
                            InfoCardView(title: "住所", value: addressString, systemImage: "location.fill", isFullWidth: true)
                        }

                        // 在留カード特有の追加情報
                        if let additionalData = cardData.additionalData {
                            if let permission = parsePermissionData(from: additionalData.comprehensivePermission) {
                                InfoCardView(title: "包括的活動許可", value: permission, systemImage: "checkmark.circle", isFullWidth: true)
                            }
                            
                            if let individual = parsePermissionData(from: additionalData.individualPermission) {
                                InfoCardView(title: "個別許可", value: individual, systemImage: "person.circle", isFullWidth: true)
                            }
                        }
                    }
                    .padding()
                    .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                    .cornerRadius(16)
                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)

                    // 画像データ表示エリア
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("画像データ")
                                .font(.headline)
                                .fontWeight(.bold)

                            Spacer()

                            // Toggle for test mode
                            Button(action: { testModeEnabled.toggle() }) {
                                HStack {
                                    Image(systemName: testModeEnabled ? "testtube.2" : "testtube.2")
                                    Text("テスト")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(testModeEnabled ? Color.orange : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            
                            Button(action: exportImages) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("エクスポート")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            
                            Button(action: shareRawData) {
                                HStack {
                                    Image(systemName: "doc.zipper")
                                    Text("生データ")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            
                            Button(action: createCompositeImage) {
                                HStack {
                                    Image(systemName: "rectangle.stack")
                                    Text("合成・透明化")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }

                        // 券面画像表示
                        if let frontImage = frontImageJPEG {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("券面画像")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Image(uiImage: frontImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 200)
                                    .cornerRadius(8)
                                    .shadow(radius: 2)
                            }
                        }
                        
                        // 顔写真表示
                        if let faceImage = faceImageJPEG {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("顔写真")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Image(uiImage: faceImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 150)
                                    .cornerRadius(8)
                                    .shadow(radius: 2)
                            }
                        }

                        // 合成画像（透明背景）表示
                        if let compositeImage = compositeImageWithTransparency {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("合成画像（透明背景）")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                ZStack {
                                    // チェッカーボード背景で透明度を可視化
                                    CheckerboardPattern()
                                        .frame(height: 200)
                                        .cornerRadius(8)
                                    
                                    Image(uiImage: compositeImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 200)
                                        .cornerRadius(8)
                                }
                            }
                        }
                        
                        // 画像情報
                        VStack(alignment: .leading, spacing: 8) {
                            Text("券面画像: \(cardData.frontImage.count) bytes (元: TIFF)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("顔写真: \(cardData.faceImage.count) bytes (元: JPEG2000)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if compositeImageWithTransparency != nil {
                                Text("合成画像: 透明背景付きPNG")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding()
                        .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color.white)
                        .cornerRadius(8)
                    }
                    .padding()
                    .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                    .cornerRadius(16)
                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)

                    // 電子署名表示エリア
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("電子署名データ")
                                .font(.headline)
                                .fontWeight(.bold)

                            Spacer()

                            Menu {
                                Button(action: {
                                    copyCheckCode()
                                }) {
                                    Label("チェックコードをコピー", systemImage: "checkmark.circle")
                                }
                                
                                Button(action: {
                                    copyCertificatePEM()
                                }) {
                                    Label("証明書(PEM)をコピー", systemImage: "doc.text")
                                }
                                
                                Button(action: {
                                    copySignatureData()
                                }) {
                                    Label("全データ(HEX)をコピー", systemImage: "doc.on.doc")
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("コピー")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                        
                        // 署名検証ステータス
                        if let verificationResult = cardData.signatureVerificationResult {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: verificationResult.isValid ? "checkmark.seal.fill" : "xmark.seal.fill")
                                        .foregroundColor(verificationResult.isValid ? .green : .red)
                                        .font(.system(size: 16))
                                    
                                    Text("署名検証: \(verificationResult.isValid ? "有効" : "無効")")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(verificationResult.isValid ? .green : .red)
                                }
                                
                                if let error = verificationResult.error {
                                    Text("エラー: \(error.localizedDescription)")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                                
                                if let details = verificationResult.details {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let checkCodeHash = details.checkCodeHash {
                                            Text("復号ハッシュ: \(String(checkCodeHash.prefix(16)))...")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        if let calculatedHash = details.calculatedHash {
                                            Text("計算ハッシュ: \(String(calculatedHash.prefix(16)))...")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        if let subject = details.certificateSubject {
                                            Text("証明書主体: \(subject)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .background(verificationResult.isValid ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(verificationResult.isValid ? Color.green : Color.red, lineWidth: 1)
                            )
                        } else {
                            HStack {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.orange)
                                Text("署名検証: 未実行")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange, lineWidth: 1)
                            )
                        }

                        // チェックコード表示
                        VStack(alignment: .leading, spacing: 8) {
                            Label("チェックコード (\(cardData.checkCode.count) bytes)", systemImage: "checkmark.seal")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            let checkCodeHex = cardData.checkCode.map { String(format: "%02X", $0) }.joined()
                            Text(String(checkCodeHex.prefix(64)) + "...")
                                .font(.system(.caption2, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                                .cornerRadius(6)
                        }
                        
                        // 公開鍵証明書表示
                        VStack(alignment: .leading, spacing: 8) {
                            Label("公開鍵証明書 (X.509, \(cardData.certificate.count) bytes)", systemImage: "key.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            let certificatePEM = formatCertificatePEM(cardData.certificate)
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(certificatePEM.prefix(200) + "...")
                                    .font(.system(.caption2, design: .monospaced))
                                    .padding(8)
                                    .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                                    .cornerRadius(6)
                            }
                        }

                        // 署名データのサマリー表示
                        Text("署名データ合計: \(cardData.checkCode.count + cardData.certificate.count) bytes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                    .cornerRadius(16)
                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)

                    // 操作ボタン
                    VStack(spacing: 12) {
                        // 戻るボタン
                        Button(action: {
                            // データをクリアしてから画面を閉じる
                            dataManager.clearData()
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            HStack {
                                Spacer()
                                Text("メイン画面に戻る")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()

                                Image(systemName: "arrow.left.circle.fill")
                                    .font(.headline)
                            }
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .shadow(color: Color.green.opacity(colorScheme == .dark ? 0.5 : 0.3), radius: 5, x: 0, y: 3)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            convertImages()
        }
        .sheet(isPresented: $showingExportSheet) {
            if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let frontImageURL = documentsDirectory.appendingPathComponent("residence_card_front.jpg")
                let faceImageURL = documentsDirectory.appendingPathComponent("residence_card_face.jpg")
                ShareSheet(activityItems: [frontImageURL, faceImageURL])
            }
        }
        .sheet(isPresented: $showingRawDataExportSheet) {
            if let fileURLs = getRawDataFileURL() {
                ShareSheet(activityItems: fileURLs)
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    // 画像変換処理
    private func convertImages() {
        let convertedImages = ImageConverter.convertResidenceCardImages(cardData: cardData)
        frontImageJPEG = convertedImages.front
        faceImageJPEG = convertedImages.face
    }
    
    // 画像エクスポート処理
    private func exportImages() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            showError(title: "エラー", message: "ドキュメントディレクトリにアクセスできません")
            return
        }
        
        var exportedFiles: [URL] = []
        
        do {
            // 券面画像をJPEGとして保存
            if let frontImage = frontImageJPEG,
               let jpegData = frontImage.jpegData(compressionQuality: 0.9) {
                let frontImageURL = documentsDirectory.appendingPathComponent("residence_card_front.jpg")
                try jpegData.write(to: frontImageURL)
                exportedFiles.append(frontImageURL)
            } else {
                // 変換に失敗した場合は元のTIFFを保存
                let frontImageURL = documentsDirectory.appendingPathComponent("residence_card_front.tiff")
                try cardData.frontImage.write(to: frontImageURL)
                exportedFiles.append(frontImageURL)
            }
            
            // 顔写真をJPEGとして保存
            if let faceImage = faceImageJPEG,
               let jpegData = faceImage.jpegData(compressionQuality: 0.9) {
                let faceImageURL = documentsDirectory.appendingPathComponent("residence_card_face.jpg")
                try jpegData.write(to: faceImageURL)
                exportedFiles.append(faceImageURL)
            } else {
                // 変換に失敗した場合は元のJPEG2000を保存
                let faceImageURL = documentsDirectory.appendingPathComponent("residence_card_face.jp2")
                try cardData.faceImage.write(to: faceImageURL)
                exportedFiles.append(faceImageURL)
            }
            
            // 合成画像（透明背景）をPNGとして保存
            if let compositeImage = compositeImageWithTransparency,
               let pngData = ImageProcessor.saveCompositeAsTransparentPNG(compositeImage) {
                let compositeImageURL = documentsDirectory.appendingPathComponent("residence_card_composite_transparent.png")
                try pngData.write(to: compositeImageURL)
                exportedFiles.append(compositeImageURL)
            }
            
            showingExportSheet = true
        } catch {
            showError(title: "エクスポートエラー", message: "画像の保存に失敗しました: \(error.localizedDescription)")
        }
    }
    
    // 署名データをコピー
    private func copySignatureData() {
        let checkCodeHex = cardData.checkCode.map { String(format: "%02X", $0) }.joined(separator: " ")
        let certificateHex = cardData.certificate.map { String(format: "%02X", $0) }.joined(separator: " ")
        let signatureHex = "CheckCode:\n" + checkCodeHex + "\n\nCertificate:\n" + certificateHex
        UIPasteboard.general.string = signatureHex
        showError(title: "コピー完了", message: "電子署名データをクリップボードにコピーしました")
    }
    
    // チェックコードをコピー
    private func copyCheckCode() {
        let checkCodeHex = cardData.checkCode.map { String(format: "%02X", $0) }.joined()
        UIPasteboard.general.string = checkCodeHex
        showError(title: "コピー完了", message: "チェックコードをクリップボードにコピーしました")
    }
    
    // 公開鍵証明書をPEM形式でコピー
    private func copyCertificatePEM() {
        let certificatePEM = formatCertificatePEM(cardData.certificate)
        UIPasteboard.general.string = certificatePEM
        showError(title: "コピー完了", message: "公開鍵証明書(PEM形式)をクリップボードにコピーしました")
    }

    // Format certificate data as PEM
    private func formatCertificatePEM(_ certData: Data) -> String {
        let base64String = certData.base64EncodedString()
        // 64文字ごとに改行を入れる（PEM形式の標準）
        var formattedString = ""
        var index = base64String.startIndex
        while index < base64String.endIndex {
            let endIndex = base64String.index(index, offsetBy: 64, limitedBy: base64String.endIndex) ?? base64String.endIndex
            formattedString += base64String[index..<endIndex]
            if endIndex < base64String.endIndex {
                formattedString += "\n"
            }
            index = endIndex
        }
        return "-----BEGIN CERTIFICATE-----\n\(formattedString)\n-----END CERTIFICATE-----"
    }
    
    // カード種別文字列を解析
    private func parseCardTypeString(from data: Data) -> String {
        if let typeValue = cardData.parseTLV(data: data, tag: 0xC1),
           let typeString = String(data: typeValue, encoding: .utf8) {
            switch typeString {
            case "1":
                return "在留カード"
            case "2":
                return "特別永住者証明書"
            default:
                return "不明なカード種別: \(typeString)"
            }
        }
        return "カード種別情報なし"
    }
    
    // 住所データを解析
    private func parseAddressData(from data: Data) -> String? {
        // TLVから住居地データを取得 (Tag 0xD4)
        if let addressData = cardData.parseTLV(data: data, tag: 0xD4),
           let addressString = String(data: addressData, encoding: .utf8) {
            // Null値を除去してトリミング
            let trimmedAddress = addressString.trimmingCharacters(in: .controlCharacters).trimmingCharacters(in: .whitespaces)
            return trimmedAddress.isEmpty ? nil : trimmedAddress
        }
        return nil
    }
    
    // 追記書き込み年月日を解析
    private func parseAddressUpdateDate(from data: Data) -> String? {
        // TLVから追記書き込み年月日を取得 (Tag 0xD2)
        if let dateData = cardData.parseTLV(data: data, tag: 0xD2),
           let dateString = String(data: dateData, encoding: .ascii) {
            // YYYYMMDDフォーマットを年/月/日に変換
            if dateString.count == 8 {
                let year = String(dateString.prefix(4))
                let month = String(dateString.dropFirst(4).prefix(2))
                let day = String(dateString.suffix(2))
                return "\(year)年\(month)月\(day)日"
            }
            return dateString
        }
        return nil
    }
    
    // 市町村コードを解析
    private func parseMunicipalityCode(from data: Data) -> String? {
        // TLVから市町村コードを取得 (Tag 0xD3)
        if let codeData = cardData.parseTLV(data: data, tag: 0xD3),
           let codeString = String(data: codeData, encoding: .ascii) {
            return codeString
        }
        return nil
    }
    
    // 許可データを解析
    private func parsePermissionData(from data: Data) -> String? {
        // TLVから許可データを取得
        if let permissionData = cardData.parseTLV(data: data, tag: 0x12),
           let permissionString = String(data: permissionData, encoding: .utf8) {
            return permissionString
        }
        return nil
    }
    
    // チェックコードを解析
    private func parseCheckCode(from data: Data) -> String? {
        // TLVからチェックコードを取得 (Tag 0xDA)
        if let checkCodeData = cardData.parseTLV(data: data, tag: 0xDA) {
            // バイナリデータを16進数文字列に変換
            return checkCodeData.map { String(format: "%02X", $0) }.joined()
        }
        return nil
    }
    
    // 公開鍵証明書を解析
    private func parsePublicKeyCertificate(from data: Data) -> String? {
        // TLVから公開鍵証明書を取得 (Tag 0xDB)
        if let certData = cardData.parseTLV(data: data, tag: 0xDB) {
            // X.509証明書をBase64エンコード（PEM形式）
            let base64String = certData.base64EncodedString()
            // 64文字ごとに改行を入れる（PEM形式の標準）
            var formattedString = ""
            var index = base64String.startIndex
            while index < base64String.endIndex {
                let endIndex = base64String.index(index, offsetBy: 64, limitedBy: base64String.endIndex) ?? base64String.endIndex
                formattedString += base64String[index..<endIndex]
                if endIndex < base64String.endIndex {
                    formattedString += "\n"
                }
                index = endIndex
            }
            return "-----BEGIN CERTIFICATE-----\n\(formattedString)\n-----END CERTIFICATE-----"
        }
        return nil
    }
    
    // 公開鍵証明書を解析（16進数文字列として）
    private func parsePublicKeyCertificateAsHex(from data: Data) -> String? {
        // TLVから公開鍵証明書を取得 (Tag 0xDB)
        if let certData = cardData.parseTLV(data: data, tag: 0xDB) {
            // バイナリデータを16進数文字列に変換
            return certData.map { String(format: "%02X", $0) }.joined()
        }
        return nil
    }
    
    // 合成画像作成処理
    private func createCompositeImage() {
        // Create composite image with transparent background
        if let compositeImage = ImageProcessor.createCompositeResidenceCard(from: cardData, tolerance: 0.08) {
            compositeImageWithTransparency = compositeImage
            showError(title: "成功", message: "合成画像を作成しました。白い背景が透明になり、顔写真が正しい位置に配置されています。")
        } else {
            showError(title: "エラー", message: "合成画像の作成に失敗しました。")
        }
    }
    
    private func showError(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.showAlert = true
    }
    
    // Share raw data functionality
    private func shareRawData() {
        let reader = ResidenceCardReader()
        
        let dataToShare: ResidenceCardData
        if testModeEnabled {
            // Use test data with specified sizes
            dataToShare = reader.createTestResidenceCardData()
            showError(title: "テストモード", message: "テストデータを生成しました。フロント画像: 7000バイト, 顔画像: 3000バイト")
        } else {
            // Use actual card data
            dataToShare = cardData
        }
        
        // Generate the raw image files
        if let _ = reader.saveRawImagesToFiles(dataToShare) {
            showingRawDataExportSheet = true
        } else {
            showError(title: "エラー", message: "生データファイルの作成に失敗しました")
        }
    }
    
    // Get the raw image URLs for sharing
    private func getRawDataFileURL() -> [URL]? {
        let reader = ResidenceCardReader()
        return reader.getLastExportedImageURLs()
    }
}


// MARK: - Preview Helper Functions
private func loadImageDataFromAssetCatalog(imageName: String) -> Data? {
    // Load image from Asset Catalog
    if let uiImage = UIImage(named: imageName) {
        // Try to get original data representation first (for TIFF/JP2)
        if let cgImage = uiImage.cgImage {
            let bitmap = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(bitmap as CFMutableData, UTType.tiff.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, cgImage, nil)
                if CGImageDestinationFinalize(destination) {
                    print("Successfully loaded \(imageName) from Asset Catalog: \(bitmap.length) bytes")
                    return bitmap as Data
                }
            }
        }
        
        // Fallback to JPEG representation
        if let jpegData = uiImage.jpegData(compressionQuality: 1.0) {
            print("Successfully loaded \(imageName) as JPEG from Asset Catalog: \(jpegData.count) bytes")
            return jpegData
        }
    }
    
    print("Could not find image in Asset Catalog: \(imageName)")
    return nil
}

private func loadFrontImageData() -> Data {
    // Try to load front_image_mmr from Asset Catalog
    if let data = loadImageDataFromAssetCatalog(imageName: "front_image_mmr") {
        return data
    }
    
    // Fallback to dummy TIFF data if image not found
    print("Using fallback dummy data for front image")
    // Create a simple valid TIFF header
    var tiffHeader = Data()
    tiffHeader.append(contentsOf: [0x4D, 0x4D]) // Big-endian
    tiffHeader.append(contentsOf: [0x00, 0x2A]) // TIFF magic number
    tiffHeader.append(contentsOf: [0x00, 0x00, 0x00, 0x08]) // IFD offset
    tiffHeader.append(contentsOf: [0x00, 0x00]) // No IFD entries
    return tiffHeader
}

private func loadFaceImageData() -> Data {
    // Try to load face_image (which contains face_image_jp2_80.jp2) from Asset Catalog
    if let data = loadImageDataFromAssetCatalog(imageName: "face_image") {
        return data
    }
    
    // Fallback to dummy JPEG data if image not found
    print("Using fallback dummy data for face image")
    // Create a simple valid JPEG header
    var jpegHeader = Data()
    jpegHeader.append(contentsOf: [0xFF, 0xD8, 0xFF, 0xE0]) // JPEG SOI and APP0
    jpegHeader.append(contentsOf: [0x00, 0x10]) // APP0 length
    jpegHeader.append(contentsOf: [0x4A, 0x46, 0x49, 0x46, 0x00]) // "JFIF\0"
    jpegHeader.append(contentsOf: [0x01, 0x01]) // Version
    jpegHeader.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x01]) // Density
    jpegHeader.append(contentsOf: [0x00, 0x00]) // Thumbnails
    jpegHeader.append(contentsOf: [0xFF, 0xD9]) // EOI
    return jpegHeader
}

#Preview {
    // サンプルデータでプレビュー（実際の画像ファイルを使用）
    let sampleData = ResidenceCardData(
        commonData: Data([0xC0, 0x04, 0x01, 0x02, 0x03, 0x04]), // サンプル共通データ
        cardType: Data([0xC1, 0x01, 0x31]), // "1" = 在留カード
        frontImage: loadFrontImageData(), // front_image_mmr.tif を使用
        faceImage: loadFaceImageData(),   // face_image_jp2_80.jp2 を使用
        address: Data([0x11, 0x10, 0x6A, 0x65, 0x6E, 0x6B, 0x69, 0x6E, 0x73, 0x20, 0x61, 0x64, 0x64, 0x72, 0x65, 0x73, 0x73]), // サンプル住所
        additionalData: ResidenceCardData.AdditionalData(
            comprehensivePermission: Data([0x12, 0x04, 0x70, 0x65, 0x72, 0x6D]), // "perm"
            individualPermission: Data([0x12, 0x04, 0x69, 0x6E, 0x64, 0x76]), // "indv"
            extensionApplication: Data([0x12, 0x04, 0x65, 0x78, 0x74, 0x6E])  // "extn"
        ),
        checkCode: Data(repeating: 0xFF, count: 256), // サンプルチェックコード
        certificate: Data(repeating: 0xAA, count: 1200), // サンプル証明書
        signatureVerificationResult: nil
    )
    
    ResidenceCardDetailView(cardData: sampleData)
}

// MARK: - CheckerboardPattern for transparency visualization
struct CheckerboardPattern: View {
    let checkSize: CGFloat = 10
    
    var body: some View {
        GeometryReader { geometry in
            let numX = Int(ceil(geometry.size.width / checkSize))
            let numY = Int(ceil(geometry.size.height / checkSize))
            
            VStack(spacing: 0) {
                ForEach(0..<numY, id: \.self) { y in
                    HStack(spacing: 0) {
                        ForEach(0..<numX, id: \.self) { x in
                            Rectangle()
                                .fill(checkColor(x: x, y: y))
                                .frame(width: checkSize, height: checkSize)
                        }
                    }
                }
            }
        }
    }
    
    private func checkColor(x: Int, y: Int) -> Color {
        let isEvenX = x % 2 == 0
        let isEvenY = y % 2 == 0
        let useLight = (isEvenX && isEvenY) || (!isEvenX && !isEvenY)
        return useLight ? Color.gray.opacity(0.2) : Color.gray.opacity(0.4)
    }
}