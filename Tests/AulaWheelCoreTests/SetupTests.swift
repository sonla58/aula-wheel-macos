import Testing
@testable import AulaWheelCore

@Suite struct SetupTests {
    func status(_ accessibility: Bool, _ inputMonitoring: Bool) -> SetupStatus {
        SetupStatus(accessibility: accessibility, inputMonitoring: inputMonitoring)
    }

    @Test func firstLaunchStartsAtWelcome() {
        #expect(SetupFlow.launchStep(completed: false, status: status(false, false)) == .welcome)
    }

    @Test func unfinishedSetupResumesWherePermissionsLeftIt() {
        #expect(SetupFlow.launchStep(completed: false, status: status(true, false)) == .permissions)
        #expect(SetupFlow.launchStep(completed: false, status: status(false, true)) == .permissions)
        #expect(SetupFlow.launchStep(completed: false, status: status(true, true)) == .keyboard)
    }

    @Test func finishedSetupStaysClosedUnlessAPermissionIsMissing() {
        #expect(SetupFlow.launchStep(completed: true, status: status(true, true)) == nil)
        #expect(SetupFlow.launchStep(completed: true, status: status(false, true)) == .permissions)
        #expect(SetupFlow.launchStep(completed: true, status: status(true, false)) == .permissions)
    }

    @Test func permissionsMustBeGrantedToContinue() {
        #expect(SetupFlow.canContinue(from: .welcome, status: status(false, false)))
        #expect(!SetupFlow.canContinue(from: .permissions, status: status(true, false)))
        #expect(!SetupFlow.canContinue(from: .permissions, status: status(false, true)))
        #expect(SetupFlow.canContinue(from: .permissions, status: status(true, true)))
        #expect(!SetupFlow.canSkip(.permissions))
    }

    @Test func keyboardContinuesOnceConnectedAndCanBeSkipped() {
        var connected = status(true, true)
        #expect(!SetupFlow.canContinue(from: .keyboard, status: connected))
        connected.keyboardConnected = true
        #expect(SetupFlow.canContinue(from: .keyboard, status: connected))
        #expect(SetupFlow.canSkip(.keyboard))
        #expect(!SetupFlow.canSkip(.welcome))
        #expect(!SetupFlow.canSkip(.tryIt))
    }

    @Test func practiceCountsRotationAndPress() {
        var practice = KnobPractice()
        practice.record(.rotate(clockwise: false, modifiers: [], time: 1))
        #expect(practice.done == [.rotate])
        practice.record(.press([]))
        #expect(practice.done == [.rotate, .press])
        practice.record(.doublePress([]))
        #expect(practice.done == [.rotate, .press])
    }

    @Test func practiceCountsPickerOpenAndModePick() {
        let modes = AppConfig.defaultModes
        var practice = KnobPractice()
        practice.record([.showPicker(modes: modes, highlighted: 0)])
        #expect(practice.done == [.openPicker])
        practice.record([.closePicker, .showRGB])
        #expect(practice.done == [.openPicker])
        practice.record([.closePicker, .stateChanged, .showMode(modes[1])])
        #expect(practice.done == [.openPicker, .pickMode])
        #expect(!practice.isComplete)
        practice.record(.rotate(clockwise: true, modifiers: [], time: 2))
        practice.record(.press([]))
        #expect(practice.isComplete)
    }

    @Test func modeChangeOutsideThePickerIsNotAPick() {
        var practice = KnobPractice()
        practice.record([.stateChanged, .showMode(AppConfig.defaultModes[0])])
        #expect(practice.done.isEmpty)
    }
}
