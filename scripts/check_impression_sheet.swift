// Prepend RegularImpressionSheetLayout from SecondaryViews.swift and run with swift.
import Foundation

precondition(RegularImpressionSheetLayout.height(for: 385) == 385)
precondition(RegularImpressionSheetLayout.height(for: 385.2) == 386)
precondition(RegularImpressionSheetLayout.height(for: 150) == 240)
precondition(RegularImpressionSheetLayout.height(for: 1400) == 600)
precondition(RegularImpressionSheetLayout.height(for: 0) == 520)
precondition(RegularImpressionSheetLayout.height(for: .nan) == 520)
precondition(RegularImpressionSheetLayout.height(for: .infinity) == 520)
print("Impression sheet checks passed: content fit, rounding, minimum, scrolling cap, invalid measurements")
