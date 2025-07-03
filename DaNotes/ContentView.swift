//
//  ContentView.swift
//  DaNotes
//
//  Created by Renorari on 2025/07/03.
//

import SwiftUI

struct ContentView: View {
    @State private var text: String = ""
    
    var body: some View {
        TextEditor(text: $text)
            .padding()
            .font(.system(size: 20))
    }
}

#Preview {
    ContentView()
}
