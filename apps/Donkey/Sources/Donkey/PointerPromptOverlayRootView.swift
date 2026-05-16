import DonkeyContracts
import DonkeyUI
import SwiftUI

struct PointerPromptOverlayRootView: View {
    @ObservedObject var model: PointerPromptOverlayModel

    var body: some View {
        PointerPromptStageView(
            state: model.promptState,
            messageText: $model.messageText,
            inputTextHeight: model.inputTextHeight,
            isInputExpanded: model.isInputExpanded,
            placement: model.placement,
            intentSink: model
        )
        .frame(
            width: PointerPromptLayout.contentSize(
                inputTextHeight: model.inputTextHeight,
                isExpanded: model.isInputExpanded
            ).width,
            height: PointerPromptLayout.contentSize(
                inputTextHeight: model.inputTextHeight,
                isExpanded: model.isInputExpanded
            ).height
        )
    }
}
