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
                    Text("証明書読み取り")
                }
            
            SecondTabView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("設定")
                }
        }
    }
}

struct SecondTabView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                
                VStack(spacing: 20) {
                    Image(systemName: "gear")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("設定")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("この画面は将来の設定機能用に予約されています。")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
            }
            .navigationTitle("設定")
        }
    }
}

#Preview {
    MainTabView()
}

#Preview {
    SecondTabView()
}