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
    @State private var showEditor: Bool = true
    
    var body: some View {
        HStack {
            if showEditor {
                TextEditor(text: $text)
                    .font(.system(size: 20))
                    .padding()
                
                Divider()
            }
            
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
        .toolbar(content: {
            ToolbarItem() {
                Toggle("Show editor", systemImage: "pencil.circle", isOn: $showEditor)
                    .keyboardShortcut("e", modifiers: .command)
            }
            ToolbarItem() {
                Button("clear", systemImage: "trash") {
                    text = ""
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
        })
    }
}

#Preview {
    ContentView()
}
