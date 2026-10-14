# Writing and proving tests

How to write a test here and prove a change with it. The commands are in [`AGENTS.md`](../AGENTS.md), under Test.

## Writing a test

- **Agree the seams first.** Name the public interface each new test will cross, and confirm it before writing the test. Never test private methods, the database behind a store's back or a mocked internal collaborator: a test that breaks on a refactor that changed no behaviour was testing the implementation.
- **Take an expected value from outside the code under test:** a known-good literal, a worked example, the spec, or a fixture captured from a real run. An assertion that recomputes the answer the way the code does passes by construction.
- **One slice at a time.** One test, the least code that passes it, then the next; watch each new test fail before making it pass. Writing every test first tests an imagined shape.

## UI tests

- **Accessibility identifiers are a contract with XCUITest.** Renaming or removing one breaks a test that queries it. An identifier on a container is not exposed on iOS 17. Query type-agnostically, not through a concrete element type.
- **Keyboard entry and search are device-only.** A test that depends on either can't be trusted from the simulator; CI turns the simulator's hardware keyboard off for this reason.
- **The `--uitesting` fixture is not how the app is used.** It starts at the default text size, with the "Created on" stamp off, no notice strips and two short Takes. Before trusting a layout result, set the condition the change is about:

  | Condition | Launch argument |
  |---|---|
  | Text size | `-UIPreferredContentSizeCategoryName <category>` |
  | "Created on" stamp | `-catchlight.creationStamp editor\|always` |
  | A notice strip above the page | `--uitesting-notice` |
  | The cloud-copy review sheet | `--uitesting-unverified` |
  | A conflict whose other side became a Script | `--uitesting-converted` |

- **A new simulator shows iOS's one-time "slide to type" introduction over the first keyboard.** `dismissKeyboardIntroductionIfPresent` in `CatchlightUITests/UITestSupport.swift` handles it, so raise the keyboard through `tapUntil` or `typeWhenReady`.
- **Run a UI test you add or change on both CI simulators before pushing:** iPhone 16 on the iOS 18 runtime and on the latest. Their screens and keyboards differ, and a layout fix proven on one has failed on the other.

## Evidence

Capture the **before** while you are still reproducing the problem, when it is cheapest, and the **after** once the change works. For a visible change that is a simulator screenshot: seed the screen, then `xcrun simctl io <udid> screenshot`. Pin the destination explicitly: a rotted simulator device is a known failure here and reads as a code failure.
