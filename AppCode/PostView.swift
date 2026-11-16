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
        GeometryReader { geometry in
        ScrollViewReader { proxy in
        VStack(spacing: 0) {
            HStack {
                if !isOnboarding {
                    Button(action: onCancel) {
                        Text("閉じる").font(.system(size: 15, weight: .bold)).foregroundColor(.white.opacity(0.75))
                    }
                }
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
                        .background(Theme.hotPink.opacity(canSubmit ? 1 : 0.35))
                        .cornerRadius(20)
                        .neonShadow(color: !canSubmit ? .clear : Theme.hotPink, radius: 8)
                }
                .disabled(!canSubmit)
                .homeGuideTarget(.postSubmit)
            }
            .overlay {
                Text("NEW POST").font(.system(size: 16, weight: .black))
                    .foregroundColor(Theme.hotPink).tracking(2)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(isOnboarding ? Theme.bgDeepBlack : Color.clear)
            
            ScrollView {
                VStack(spacing: 24) {
                    HStack(alignment: .top, spacing: 14) {
                        Group {
                            if let data = appState.userAvatarData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage).resizable().scaledToFill()
                            } else {
                                Image(Theme.defaultAvatarAsset).resizable().scaledToFill()
                            }
                        }
                        .modifier(FeedAvatarFrame(size: 46, stroke: Theme.hotPink.opacity(0.75),
                                                  accent: Theme.hotPink, lineWidth: 1.5, enabled: true))

                        TextEditor(text: $text)
                            .focused($isFocused)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .foregroundColor(.white)
                            .tint(Theme.hotPink)
                            .font(.system(size: 20, weight: .medium))
                            .accessibilityLabel(appState.text("投稿内容", "Post content"))
                    }
                    .padding(18)
                    .frame(height: max(210, min(460, geometry.size.height - 210)), alignment: .top)
                    .background {
                        FeedCardSurface(fill: Theme.aiCardBackground.opacity(0.92), accent: Theme.hotPink,
                                        border: Theme.lavender.opacity(0.44), cornerRadius: 22)
                    }
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
                                .foregroundColor(Theme.lavender)
                                .background {
                                    FeedCardSurface(fill: Theme.deepPurple.opacity(0.7), accent: Theme.lavender,
                                                    border: Theme.lavender.opacity(0.25), cornerRadius: 16,
                                                    showsAccent: false)
                                }
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
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange.opacity(0.7))
                Text("個人情報（本名・住所・電話番号など）は入力しないでください")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
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
                isFocused = (!DesignPreview.isActive || DesignPreview.argument("--ui-keyboard") == "true")
                    && guide?.isPresenting != true
            }
        }
        .homeGuideViewport()
        }
        }
    }
}
