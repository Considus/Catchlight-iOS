//
//  TimelineFocusShiftTests.swift
//  CatchlightTests (app module)
//
//  While the Focus row is open on a Take, the timeline holds every card below it 22pt
//  lower. The shift has to survive whatever else redraws the timeline while the row is
//  open (a reconfigure, a layout pass) and must not stay on a cell after the row closes.
//

import XCTest
import CatchlightCore
@testable import Catchlight

@MainActor
final class TimelineFocusShiftTests: XCTestCase {

    private var window: UIWindow!
    private var vc: UIKitTimelineViewController!
    private var growth: FocusRowGrowth!
    private var takes: [Take] = []

    override func setUp() async throws {
        vc = UIKitTimelineViewController()
        growth = FocusRowGrowth()
        vc.focusGrowth = growth
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        takes = (0..<4).map { Take(blocks: [.textLine("Take \($0)")]) }
        vc.apply(groups: [TimelineMonthGroup(id: "2026-11", title: "November", takes: takes)])
        await settle()
    }

    override func tearDown() async throws {
        window.isHidden = true
        window = nil
        vc = nil
    }

    /// Lets the main queue run: the growth is applied one main-queue turn after it changes.
    private func settle() async {
        for _ in 0..<5 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            vc.view.layoutIfNeeded()
        }
    }

    private var collectionView: UICollectionView {
        vc.view.subviews.compactMap { $0 as? UICollectionView }.first!
    }

    /// The vertical shift of each visible row, in display order.
    private func shifts() -> [CGFloat] {
        collectionView.indexPathsForVisibleItems.sorted().compactMap {
            collectionView.cellForItem(at: $0)?.transform.ty
        }
    }

    func testCardsBelowTheGrownCard_moveDown() async {
        growth.set(true, for: takes[1].id, duration: nil)
        await settle()
        XCTAssertEqual(shifts(), [0, 0, 22, 22])
    }

    func testShift_survivesAReconfigureOfEveryRow() async {
        growth.set(true, for: takes[1].id, duration: nil)
        await settle()
        vc.isReorderable = true            // reconfigures every row
        await settle()
        XCTAssertEqual(shifts(), [0, 0, 22, 22])
    }

    func testShift_survivesALayoutPass() async {
        growth.set(true, for: takes[1].id, duration: nil)
        await settle()
        collectionView.collectionViewLayout.invalidateLayout()
        await settle()
        XCTAssertEqual(shifts(), [0, 0, 22, 22])
    }

    func testShift_survivesAChangedTake() async {
        growth.set(true, for: takes[1].id, duration: nil)
        await settle()
        var changed = takes
        changed[3].blocks = [.textLine("Take 3, edited elsewhere and synced\nwith a second line")]
        vc.apply(groups: [TimelineMonthGroup(id: "2026-11", title: "November", takes: changed)])
        await settle()
        XCTAssertEqual(shifts(), [0, 0, 22, 22])
    }

    func testClosing_returnsEveryCardToRest() async {
        growth.set(true, for: takes[1].id, duration: nil)
        await settle()
        growth.reset()
        await settle()
        XCTAssertEqual(shifts(), [0, 0, 0, 0])
    }

    /// Cells dequeued while the row is open take the shift, and cells reused after it closes
    /// come back at rest.
    func testShift_followsCellsScrolledIntoView() async {
        takes = (0..<40).map { Take(blocks: [.textLine("Take \($0)")]) }
        vc.apply(groups: [TimelineMonthGroup(id: "2026-11", title: "November", takes: takes)])
        await settle()
        growth.set(true, for: takes[0].id, duration: nil)
        await settle()
        let cv = collectionView
        cv.setContentOffset(CGPoint(x: 0, y: cv.contentSize.height - cv.bounds.height), animated: false)
        await settle()
        XCTAssertTrue(shifts().allSatisfy { $0 == 22 }, "Cells scrolled in while open: \(shifts())")
        growth.reset()
        await settle()
        cv.setContentOffset(CGPoint(x: 0, y: -cv.adjustedContentInset.top), animated: false)
        await settle()
        XCTAssertTrue(shifts().allSatisfy { $0 == 0 }, "Cells scrolled in after the close: \(shifts())")
    }
}
