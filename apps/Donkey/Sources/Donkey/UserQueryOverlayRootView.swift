import DonkeyContracts
import DonkeyUI
import SwiftUI

struct UserQueryOverlayRootView: View {
    @ObservedObject var model: UserQueryOverlayModel
    var voiceInputRequested: @MainActor () -> Void = {}
    var voiceInputFinished: @MainActor () -> Void = {}

    var body: some View {
        UserQueryStageView(
            state: model.promptState,
            messageText: $model.messageText,
            inputTextHeight: model.inputTextHeight,
            isInputExpanded: model.isInputExpanded,
            placement: model.placement,
            intentSink: model,
            voiceInputRequested: voiceInputRequested,
            voiceInputFinished: voiceInputFinished
        )
        .frame(
            width: contentSize.width,
            height: contentSize.height
        )
    }

    private var contentSize: CGSize {
        UserQueryLayout.contentSize(
            inputTextHeight: model.inputTextHeight,
            isExpanded: model.isInputExpanded
        )
    }
}
