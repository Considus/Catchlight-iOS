import UIKit
import CatchlightCore

/// Callbacks the self-scrolling editor raises to its SwiftUI coordinator.
/// Milestone 1+: text-changed, focus-moved, Return (list command), and
/// backspace-on-empty (merge/exit) hooks land here.
protocol BlockEditorViewControllerDelegate: AnyObject {
    // Intentionally empty for the skeleton — filled per milestone.
}

/// Self-scrolling list of block-rows (Milestone 1: prose rows; M2: check rows).
///
/// The KEY property: the LIST scrolls, so keeping the active caret above the
/// keyboard is native — `scrollRectToVisible` on the caret rect plus a keyboard
/// `contentInset`. That is exactly the behaviour `DailiesView.pinCaret`
/// reproduced by hand (and re-broke four times); here it comes for free.
///
/// STATUS: skeleton only.
final class BlockEditorViewController: UIViewController {
    weak var delegate: BlockEditorViewControllerDelegate?

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.separatorStyle = .none
        tv.backgroundColor = .clear
        tv.keyboardDismissMode = .interactive
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        // Milestone 1: a diffable data source of block-rows keyed on block id,
        // with self-sizing text cells; keyboard-inset + scroll-to-caret wiring.
    }

    /// Called from the representable on every SwiftUI update: diff `blocks`
    /// into the list and drive first-responder from `focusedBlockID`.
    /// Milestone 1: implement the diff + focus.
    func apply(blocks: [TakeBlock], focusedBlockID: UUID?) {
        _ = blocks
        _ = focusedBlockID
    }
}
