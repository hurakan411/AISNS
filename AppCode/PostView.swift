import SwiftUI
import PhotosUI

struct PostView: View {
    @EnvironmentObject var appState: AppState
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var attachedImageData: Data? = nil
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
                        appState.submitPost(text: text, imageData: attachedImageData)
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
                        if let data = appState.userAvatarData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.purple, lineWidth: 2))
                        } else {
                            AsyncImage(url: URL(string: Theme.myAvatar)) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color.purple)
                            }
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.purple, lineWidth: 2))
                        }
                        
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
                    if let data = attachedImageData, let uiImage = UIImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxHeight: 240)
                                .clipped()
                                .cornerRadius(16)
                            
                            Button(action: {
                                attachedImageData = nil
                                selectedItem = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                            .padding(8)
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Toolbar for media
                    if attachedImageData == nil {
                        HStack {
                            Spacer()
                            PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 16, weight: .bold))
                                    Text("画像を添付")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.08))
                                .foregroundColor(Theme.cyan)
                                .cornerRadius(24)
                                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            }
                            .onChange(of: selectedItem) { newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                        DispatchQueue.main.async {
                                            if let uiImage = UIImage(data: data), let compressed = uiImage.jpegData(compressionQuality: 0.5) {
                                                attachedImageData = compressed
                                            } else {
                                                attachedImageData = data
                                            }
                                        }
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    }
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
