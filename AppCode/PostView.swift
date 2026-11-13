import SwiftUI
import PhotosUI

struct PostView: View {
    @EnvironmentObject var appState: AppState
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var attachedImageData: Data? = nil
    @State private var isLoadingImage = false
    private var canSubmit: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoadingImage }
    var onCancel: () -> Void
    var guide: HomeGuideCoordinator? = nil
    var onOnboardingSubmit: ((String) -> Void)? = nil
    var isOnboarding: Bool = false
    
    var body: some View {
        ScrollViewReader { proxy in
        VStack(spacing: 0) {
            HStack {
                if isOnboarding {
                    Text("").frame(width: 50)
                } else {
                    Button(action: onCancel) {
                        Text("閉じる").font(.system(size: 15, weight: .bold)).foregroundColor(.gray)
                    }
                }
                Spacer()
                Text("NEW POST").font(.system(size: 16, weight: .black)).foregroundColor(Theme.hotPink).tracking(2)
                Spacer()
                Button(action: {
                    if canSubmit {
                        if isOnboarding {
                            onOnboardingSubmit?(text)
                        } else {
                            appState.submitPost(text: text, imageData: attachedImageData)
                            onCancel()
                        }
                    }
                }) {
                    Text("投稿")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(!canSubmit ? Color.gray.opacity(0.2) : Theme.hotPink)
                        .cornerRadius(20)
                        .neonShadow(color: !canSubmit ? .clear : Theme.hotPink, radius: 8)
                }
                .disabled(!canSubmit)
                .homeGuideTarget(.postSubmit)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Theme.bgDeepBlack)
            .overlay(Rectangle().fill(Theme.subtleBorder).frame(height: 1), alignment: .bottom)
            
            ScrollView {
                VStack(spacing: 24) {
                    HStack(alignment: .top, spacing: 16) {
                        if let data = appState.userAvatarData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Theme.hotPink.opacity(0.75), lineWidth: 2))
                        } else {
                            Image(Theme.defaultAvatarAsset)
                                .resizable()
                                .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.hotPink.opacity(0.75), lineWidth: 2))
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
                    .padding(18)
                    .background(Theme.cardBackground)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.subtleBorder, lineWidth: 1))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .homeGuideTarget(.postEditor)
                    
                    // Attached Image preview
                    if let data = attachedImageData, let uiImage = UIImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            PostAttachmentImage(image: uiImage, height: 240, cornerRadius: 16)
                            
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
                                .background(Theme.deepPurple)
                                .foregroundColor(Theme.cyan)
                                .cornerRadius(16)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.subtleBorder, lineWidth: 1))
                            }
                            .disabled(isLoadingImage)
                            .homeGuideTarget(.postImage)
                            .onChange(of: selectedItem) { _, newItem in
                                guard let newItem else { return }
                                isLoadingImage = true
                                Task { @MainActor in
                                    defer { isLoadingImage = false }
                                    if let data = try? await newItem.loadTransferable(type: Data.self), selectedItem == newItem {
                                        attachedImageData = UIImage(data: data)?.jpegData(compressionQuality: 0.5) ?? data
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

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange.opacity(0.7))
                Text("個人情報（本名・住所・電話番号など）は入力しないでください")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .task(id: guide?.activeStep) {
            guard let step = guide?.activeStep, step.screen == .post else { return }
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(step, anchor: .center) }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                isFocused = !DesignPreview.isActive && guide?.isPresenting != true
            }
        }
        .homeGuideViewport()
        }
    }
}
