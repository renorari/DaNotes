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
    @State private var showClearConfirmation: Bool = false
    @AppStorage("SuppressClearConfirmation") private var suppressClearConfirmation: Bool = false
    
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
        #if os(macOS)
        .background(Color(NSColor.textBackgroundColor))
        #else
        .background(Color(UIColor.systemBackground))
        #endif
        .toolbar(content: {
            ToolbarItem() {
                Toggle(.showEditor, systemImage: "pencil.circle", isOn: $showEditor)
                    .keyboardShortcut("e", modifiers: .command)
            }
            ToolbarItem() {
                Button(.clearButton, systemImage: "trash") {
                    if suppressClearConfirmation || text.isEmpty {
                        text = ""
                    } else {
                        showClearConfirmation = true
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .confirmationDialog(.clearConfirm, isPresented: $showClearConfirmation) {
                    Button(.clearButton, role: .destructive) {
                        text = ""
                    }
                }
                .dialogIcon(Image(systemName: "trash.circle.fill"))
                .dialogSuppressionToggle(isSuppressed: $suppressClearConfirmation)
            }
        })
    }
}

#Preview {
    ContentView()
}
