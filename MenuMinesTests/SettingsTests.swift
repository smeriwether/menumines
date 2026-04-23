import Foundation
import Testing
@testable import MenuMines

// .serialized required since tests manipulate shared UserDefaults state
@Suite("Settings Tests", .serialized)
struct SettingsTests {

    // MARK: - Menu Bar Indicators Setting

    @Test("Menu bar indicators key is properly namespaced")
    func testMenuBarIndicatorsKeyIsNamespaced() {
        #expect(Constants.SettingsKeys.showMenuBarIndicators == "com.menumines.showMenuBarIndicators")
    }

    // MARK: - Confirm Before Reset Setting

    @Test("Confirm before reset key is properly namespaced")
    func testConfirmBeforeResetKeyIsNamespaced() {
        #expect(Constants.SettingsKeys.confirmBeforeReset == "com.menumines.confirmBeforeReset")
    }

    @Test("Confirm before reset can be toggled via UserDefaults")
    func testConfirmBeforeResetCanBeToggled() {
        let key = Constants.SettingsKeys.confirmBeforeReset

        // Save initial state to restore after test
        let initialValue = UserDefaults.standard.object(forKey: key)

        // Test setting to true
        UserDefaults.standard.set(true, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == true)

        // Test setting to false
        UserDefaults.standard.set(false, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == false)

        // Restore initial state
        if let initial = initialValue {
            UserDefaults.standard.set(initial, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @Test("Confirm before reset defaults to false when not set")
    func testConfirmBeforeResetDefaultsToFalse() {
        let key = Constants.SettingsKeys.confirmBeforeReset

        // Save initial state
        let initialValue = UserDefaults.standard.object(forKey: key)

        // Remove value to test default behavior
        UserDefaults.standard.removeObject(forKey: key)

        // bool(forKey:) returns false when key is not set
        #expect(UserDefaults.standard.bool(forKey: key) == false)

        // Restore initial state
        if let initial = initialValue {
            UserDefaults.standard.set(initial, forKey: key)
        }
    }

    // MARK: - Streaks Setting

    @Test("Show streaks key is properly namespaced")
    func testShowStreaksKeyIsNamespaced() {
        #expect(Constants.SettingsKeys.showStreaks == "com.menumines.showStreaks")
    }

    @Test("Show streaks can be toggled via UserDefaults")
    func testShowStreaksCanBeToggled() {
        let key = Constants.SettingsKeys.showStreaks
        // Save initial state to restore after test
        let initialValue = UserDefaults.standard.object(forKey: key)

        // Test setting to false
        UserDefaults.standard.set(false, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == false)

        // Test setting to true
        UserDefaults.standard.set(true, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == true)

        // Restore initial state
        if let initial = initialValue {
            UserDefaults.standard.set(initial, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Continuous Play Setting

    @Test("Continuous play key is properly namespaced")
    func testContinuousPlayKeyIsNamespaced() {
        #expect(Constants.SettingsKeys.continuousPlay == "com.menumines.continuousPlay")
    }

    @Test("Continuous play can be toggled via UserDefaults")
    func testContinuousPlayCanBeToggled() {
        let key = Constants.SettingsKeys.continuousPlay

        // Save initial state to restore after test
        let initialValue = UserDefaults.standard.object(forKey: key)

        // Test setting to false
        UserDefaults.standard.set(false, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == false)

        // Test setting to true
        UserDefaults.standard.set(true, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == true)

        // Restore initial state
        if let initial = initialValue {
            UserDefaults.standard.set(initial, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    @Test("Menu bar indicators can be toggled via UserDefaults")
    func testMenuBarIndicatorsCanBeToggled() {
        let key = Constants.SettingsKeys.showMenuBarIndicators

        // Save initial state to restore after test
        let initialValue = UserDefaults.standard.object(forKey: key)

        // Test setting to false
        UserDefaults.standard.set(false, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == false)

        // Test setting to true
        UserDefaults.standard.set(true, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == true)

        // Restore initial state
        if let initial = initialValue {
            UserDefaults.standard.set(initial, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Icon State Logic

    @Test("menuBarIconState function returns expected states")
    func testMenuBarIconStateFunctionLogic() {
        // Verify the pure menuBarIconState function returns correct states
        let lostState = menuBarIconState(gameStatus: .lost, isPaused: false, isDailyComplete: false)
        let pausedState = menuBarIconState(gameStatus: .playing, isPaused: true, isDailyComplete: false)
        let incompleteState = menuBarIconState(gameStatus: .notStarted, isPaused: false, isDailyComplete: false)
        let completeState = menuBarIconState(gameStatus: .won, isPaused: false, isDailyComplete: true)

        #expect(lostState == .lost)
        #expect(pausedState == .paused)
        #expect(incompleteState == .incomplete)
        #expect(completeState == .complete)
    }

    @Test("Icon state respects showMenuBarIndicators setting when disabled")
    func testIconStateRespectsSettingWhenDisabled() {
        let key = Constants.SettingsKeys.showMenuBarIndicators

        // Save initial state
        let initialValue = UserDefaults.standard.object(forKey: key)

        // Simulate showMenuBarIndicators = false
        UserDefaults.standard.set(false, forKey: key)
        let showIndicators = UserDefaults.standard.bool(forKey: key)

        // Simulate the currentIconState logic from MenuMinesApp
        let iconStateWhenLost: MenuBarIconState
        if showIndicators {
            iconStateWhenLost = menuBarIconState(gameStatus: .lost, isPaused: false, isDailyComplete: false)
        } else {
            iconStateWhenLost = .normal
        }

        // When setting is disabled, icon should be .normal regardless of game state
        #expect(iconStateWhenLost == .normal)

        // Simulate showMenuBarIndicators = true
        UserDefaults.standard.set(true, forKey: key)
        let showIndicatorsEnabled = UserDefaults.standard.bool(forKey: key)

        let iconStateWhenLostEnabled: MenuBarIconState
        if showIndicatorsEnabled {
            iconStateWhenLostEnabled = menuBarIconState(gameStatus: .lost, isPaused: false, isDailyComplete: false)
        } else {
            iconStateWhenLostEnabled = .normal
        }

        // When setting is enabled, icon should reflect actual game state
        #expect(iconStateWhenLostEnabled == .lost)

        // Restore initial state
        if let initial = initialValue {
            UserDefaults.standard.set(initial, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
