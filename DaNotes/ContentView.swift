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
    @State private var showView: Bool = true
    @State private var showClearConfirmation: Bool = false
    @AppStorage("SuppressClearConfirmation") private var suppressClearConfirmation: Bool = false
    
    var body: some View {
        NavigationStack {
            HStack {
                if showEditor {
                    TextEditor(text: $text)
                        .font(.system(size: 20))
                }
                
                if showEditor && showView {
                    Divider().padding(.horizontal)
                }
                
                if showView {
                    ScrollView {
                        Markdown(text)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .markdownTextStyle() {
                                FontSize(20)
                            }
                            .markdownTextStyle(\.emphasis) {
                                BackgroundColor(.yellow.opacity(0.25))
                            }
                            .markdownTextStyle(\.code) {
                                FontFamilyVariant(.monospaced)
                                BackgroundColor(.secondary.opacity(0.25))
                            }
                    }
                }
            }
            .padding(.horizontal)
            #if os(macOS)
            .background(Color(NSColor.textBackgroundColor))
            #else
            .background(Color(UIColor.systemBackground))
            #endif
            .toolbar {
                ToolbarItemGroup {
                    Toggle(.showEditor, systemImage: "pencil.circle", isOn: $showEditor)
                        .keyboardShortcut("e", modifiers: .command)
                        .disabled(!showView)
                    Toggle(.showView, systemImage: "text.page", isOn: $showView)
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(!showEditor)
                }
                ToolbarSpacer()
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
            }
        }
    }
}

#Preview {
    ContentView()
}
