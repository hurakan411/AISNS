import SwiftUI
import StoreKit

class StoreManager: ObservableObject {
    @Published var isAdsRemoved: Bool = UserDefaults.standard.bool(forKey: "isAdsRemoved") {
        didSet { UserDefaults.standard.set(isAdsRemoved, forKey: "isAdsRemoved") }
    }
    
    // Using a generic product ID, the user can replace this in App Store Connect
    let removeAdsProductID = "com.upme.removeads"
    
    @Published var products: [Product] = []
    
    init() {
        Task {
            await fetchProducts()
            await updatePurchasedStatus()
        }
    }
    
    func fetchProducts() async {
        do {
            let storeProducts = try await Product.products(for: [removeAdsProductID])
            DispatchQueue.main.async {
                self.products = storeProducts
            }
        } catch {
            print("Failed to fetch products: \(error)")
        }
    }
    
    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                switch verificationResult {
                case .verified(let transaction):
                    DispatchQueue.main.async {
                        self.isAdsRemoved = true
                    }
                    await transaction.finish()
                case .unverified(_, _):
                    break
                }
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }
    
    func updatePurchasedStatus() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == removeAdsProductID {
                    DispatchQueue.main.async {
                        self.isAdsRemoved = true
                    }
                }
            }
        }
    }
    
    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            print("Failed to restore purchases: \(error)")
        }
    }
}
