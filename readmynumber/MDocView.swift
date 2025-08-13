//
//  MDocView.swift
//  readmynumber
//

import SwiftUI
import CoreNFC

struct MDocView: View {
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var isScanning: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(gradient: Gradient(colors: [Color.white, Color(UIColor.systemGray6)]),
                                   startPoint: .top,
                                   endPoint: .bottom)
                        .ignoresSafeArea()

                    VStack(spacing: geometry.size.height * 0.03) {
                        // Logo and Title
                        VStack(spacing: geometry.size.height * 0.015) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.13, weight: .regular))
                                .foregroundColor(.purple)
                                .symbolRenderingMode(.hierarchical)

                            Text("M-Doc読み取り")
                                .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.06, weight: .bold))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, geometry.size.height * 0.006)
                        .padding(.bottom, geometry.size.height * 0.03)

                        // M-Doc Information Section
                        VStack(alignment: .leading, spacing: geometry.size.height * 0.02) {
                            HStack {
                                Text("Mobile Document (M-Doc)")
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Spacer()

                                Image(systemName: "qrcode.viewfinder")
                                    .font(.title2)
                                    .foregroundColor(.purple)
                            }

                            Text("ISO/IEC 18013-5準拠のモバイル文書フォーマットに対応しています。デジタル身分証明書やモバイル運転免許証などを読み取ることができます。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Supported Standards
                            VStack(alignment: .leading, spacing: 8) {
                                Label("ISO/IEC 18013-5 (mDL)", systemImage: "checkmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundColor(.green)
                                
                                Label("ISO/IEC 23220 (モバイルeID)", systemImage: "checkmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundColor(.green)
                                
                                Label("NFC & QRコード両対応", systemImage: "checkmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundColor(.green)
                            }
                            .padding()
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)

                            Button(action: {
                                startMDocReading()
                            }) {
                                HStack {
                                    Spacer()
                                    Text("M-Docを読み取る")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Spacer()

                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.headline)
                                }
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .shadow(color: Color.purple.opacity(colorScheme == .dark ? 0.5 : 0.3), radius: 5, x: 0, y: 3)
                        }
                        .padding(min(geometry.size.width, geometry.size.height) * 0.05)
                        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                        .cornerRadius(16)
                        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .frame(width: geometry.size.width * 0.9)

                        // Information Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("対応文書タイプ")
                                .font(.headline)
                                .padding(.bottom, 5)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "car.fill")
                                        .foregroundColor(.blue)
                                    Text("モバイル運転免許証 (mDL)")
                                        .font(.subheadline)
                                }
                                
                                HStack {
                                    Image(systemName: "person.text.rectangle")
                                        .foregroundColor(.green)
                                    Text("デジタル身分証明書")
                                        .font(.subheadline)
                                }
                                
                                HStack {
                                    Image(systemName: "building.2.fill")
                                        .foregroundColor(.orange)
                                    Text("デジタル社員証")
                                        .font(.subheadline)
                                }
                            }
                        }
                        .padding(min(geometry.size.width, geometry.size.height) * 0.05)
                        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                        .cornerRadius(16)
                        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .frame(width: geometry.size.width * 0.9)

                        // Footer
                        Text("© 2025 Meikenn")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, geometry.size.height * 0.01)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)

                    if isScanning {
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)
                        ProgressView("M-Doc読み取り中...")
                            .padding()
                            .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                            .cornerRadius(10)
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    private func startMDocReading() {
        // M-Doc読み取り機能の実装
        // 現時点では開発中のメッセージを表示
        showError(title: "機能開発中", message: "M-Doc読み取り機能は現在開発中です。今後のアップデートでご利用いただけるようになります。")
    }
    
    private func showError(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.showAlert = true
    }
}

#Preview {
    MDocView()
}