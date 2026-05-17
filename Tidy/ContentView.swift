//
//  ContentView.swift
//  Tidy
//
//  Created by Azhar Amir on 17/05/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "textformat")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Tidy")
                .font(.title.weight(.semibold))
            Text("A menu bar companion for grammar correction and clipboard history.")
                .foregroundStyle(.secondary)
        }
        .frame(width: 420, height: 180)
        .padding(24)
    }
}

#Preview {
    ContentView()
}
