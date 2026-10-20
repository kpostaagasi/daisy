// Daisy — conversion task state shown in the progress overlay.
import Foundation

final class ConversionTaskStore: ObservableObject {
    @Published var isBusy = false
    @Published var lastResult: String = ""
    @Published var succeeded = true
}
