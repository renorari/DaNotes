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
                .toolbar(content: {
                    ToolbarItem() {
                        Button("clear", systemImage: "trash") {
                            text = ""
                        }
                        .keyboardShortcut(.delete, modifiers: .command)
                    }
                })
            
            Divider()
            
            ScrollView {
                Markdown(text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .markdownTextStyle() {
                        FontSize(20)
                    }
            }
            .padding()
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

#Preview {
    ContentView()
}
