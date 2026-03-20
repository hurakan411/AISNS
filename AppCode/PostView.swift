import SwiftUI

struct PostView: View {
    @EnvironmentObject var appState: AppState
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    var onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Text("閉じる").font(.system(size: 15, weight: .bold)).foregroundColor(.gray)
                }
                Spacer()
                Text("NEW POST").font(.system(size: 16, weight: .black)).foregroundColor(Theme.hotPink).tracking(2)
                Spacer()
                Button(action: {
                    if !text.isEmpty {
                        appState.submitPost(text: text)
                        onCancel()
                    }
                }) {
                    Text("投稿")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(text.isEmpty ? Color.gray.opacity(0.2) : Theme.hotPink)
                        .cornerRadius(20)
                        .neonShadow(color: text.isEmpty ? .clear : Theme.hotPink, radius: 8)
                }
                .disabled(text.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Theme.bgDeepBlack)
            
            ScrollView {
                VStack(spacing: 24) {
                    HStack(alignment: .top, spacing: 16) {
                        AsyncImage(url: URL(string: Theme.myAvatar)) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.purple)
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.purple, lineWidth: 2))
                        
                        if #available(iOS 16.0, *) {
                            TextEditor(text: $text)
                                .focused($isFocused)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .foregroundColor(.white)
                                .font(.system(size: 22, weight: .bold))
                                .frame(minHeight: 180)
                        } else {
                            TextEditor(text: $text)
                                .focused($isFocused)
                                .background(Color.clear)
                                .foregroundColor(.white)
                                .font(.system(size: 22, weight: .bold))
                                .frame(minHeight: 180)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    // Attached Image preview
                    ZStack {
                        AsyncImage(url: URL(string: Theme.fallbackImg)) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Color.gray.opacity(0.2))
                        }
                        .frame(height: 240)
                        .clipped()
                        .cornerRadius(32)
                        .overlay(
                            LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottom, endPoint: .top)
                        )
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFocused = true
            }
        }
    }
}
