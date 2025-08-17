//
//  MainTabView.swift
//  readmynumber
//
//  Created by Claude Code on 2025/08/11.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Image(systemName: "creditcard.fill")
                    Text("マイナンバー")
                }
            
            ResidentTabView()
                .tabItem {
                    Image(systemName: "person.text.rectangle.fill")
                    Text("在留カード")
                }
            
            MDocView()
                .tabItem {
                    Image(systemName: "doc.text.viewfinder")
                    Text("M-Doc")
                }
        }
    }
}

struct ResidentTabView: View {
    @State private var cardNumber: String = ""
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showingSample = false
    @StateObject private var residenceCardReader = ResidenceCardReader()
    @StateObject private var dataManager = ResidenceCardDataManager.shared
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
                            Image(systemName: "person.text.rectangle.fill")
                                .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.13, weight: .regular))
                                .foregroundColor(.green)
                                .symbolRenderingMode(.hierarchical)

                            Text("在留カードの読み取り")
                                .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.06, weight: .bold))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, geometry.size.height * 0.006)
                        .padding(.bottom, geometry.size.height * 0.03)

                        // Card Number Input Section
                        VStack(alignment: .leading, spacing: geometry.size.height * 0.02) {
                            HStack {
                                Text("在留カード番号入力")
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Spacer()
                                
                                Button(action: {
                                    showingSample = true
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "questionmark.circle")
                                        Text("サンプル")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                }

                                Image(systemName: "creditcard")
                                    .font(.title2)
                                    .foregroundColor(.green)
                            }

                            Text("在留カードに記載されている12文字の英数字を入力してください（例: AA1234567899）")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Card Number Input Field
                            TextField("在留カード番号（12文字）", text: $cardNumber)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)
                                .font(.monospaced(.body)())
                                .onChange(of: cardNumber) { newValue in
                                    // 12文字に制限
                                    if newValue.count > 12 {
                                        cardNumber = String(newValue.prefix(12))
                                    }
                                }

                            Button(action: {
                                startResidenceCardReading()
                            }) {
                                HStack {
                                    Spacer()
                                    Text("在留カードを読み取る")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Spacer()

                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.headline)
                                }
                                .padding()
                                .background(isValidCardNumber() ? Color.green : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(!isValidCardNumber())
                            .shadow(color: Color.green.opacity(colorScheme == .dark ? 0.5 : 0.3), radius: 5, x: 0, y: 3)
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

                    if residenceCardReader.isReadingInProgress {
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)
                        ProgressView("在留カード読み取り中...")
                            .padding()
                            .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                            .cornerRadius(10)
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .navigationDestination(isPresented: $dataManager.shouldNavigateToDetail) {
                if let cardData = dataManager.cardData {
                    ResidenceCardDetailView(cardData: cardData)
                }
            }
            .sheet(isPresented: $showingSample) {
                ResidenceCardSampleView()
            }
        }
        .onAppear {
            // 画面表示時にデータをクリア
            dataManager.clearData()
            cardNumber = ""
        }
    }
    
    private func isValidCardNumber() -> Bool {
        return cardNumber.count == 12 && !cardNumber.isEmpty
    }
    
    private func startResidenceCardReading() {
        guard isValidCardNumber() else {
            showError(title: "エラー", message: "正しい12文字の在留カード番号を入力してください")
            return
        }
        
        residenceCardReader.startReading(cardNumber: cardNumber.uppercased()) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let cardData):
                    self.dataManager.setCardData(cardData)
                case .failure(let error):
                    self.showError(title: "読み取りエラー", message: error.localizedDescription)
                }
            }
        }
    }
    
    private func showError(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.showAlert = true
    }
}

#Preview {
    MainTabView()
}

#Preview {
    ResidentTabView()
}