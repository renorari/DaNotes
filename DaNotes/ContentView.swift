//
//  ContentView.swift
//  DaNotes
//
//  Created by Renorari on 2025/07/03.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("text") private var text: String = ""
    
    var body: some View {
        HStack {
            TextEditor(text: $text)
                .font(.system(size: 20))
                .padding()
            
            Divider()
            
            Text(.init(text))
                .font(.system(size: 20))
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

#Preview {
    ContentView()
}
