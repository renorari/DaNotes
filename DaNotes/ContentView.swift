//
//  ContentView.swift
//  DaNotes
//
//  Created by Renorari on 2025/07/03.
//

import SwiftUI
import MarkdownUI

struct ContentView: View {
    @AppStorage("text") private var text: String = ""
    
    var body: some View {
        HStack {
            TextEditor(text: $text)
                .font(.system(size: 20))
                .padding()
            
            Divider()
            
            Markdown(text)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .markdownTextStyle() {
                  FontSize(20)
                }
        }
    }
}

#Preview {
    ContentView()
}
