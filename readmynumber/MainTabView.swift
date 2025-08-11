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
            
            ResidentTabView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Resident")
                }
        }
    }
}

struct ResidentTabView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                
                VStack(spacing: 20) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("Resident")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("この画面は住民情報機能用に予約されています。")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
            }
            .navigationTitle("Resident")
        }
    }
}

#Preview {
    MainTabView()
}

#Preview {
    ResidentTabView()
}