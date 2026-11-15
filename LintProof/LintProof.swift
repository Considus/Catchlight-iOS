import SwiftUI
import UIKit

struct LintProof: View {
    var body: some View {
        VStack {
            Text(verbatim: "Hello")
            Text(AttributedString("Hello"))
                .onTapGesture { }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { EmptyView() }
        }
        .navigationBarHidden(true)
    }
    func width() -> CGFloat { UIScreen.main.bounds.width }
    func quiet() {
        _ = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/x"))
        // swiftlint:disable:next try_optional
        let a = 1
        // SHORTCUT: skip validation for now.
        _ = a
        // SHORTCUT: fine, held to one screen. Revisit when two screens share it.
        // a comment mentioning try? or UIScreen.main must not fire
        _ = "try? onTapGesture in a string must not fire"
    }
}
