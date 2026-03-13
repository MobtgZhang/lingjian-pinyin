#include "lingjian.h"

#include <fcitx-utils/key.h>
#include <fcitx-utils/keysymgen.h>
#include <fcitx-utils/standardpath.h>
#include <fcitx-utils/log.h>
#include <fcitx/candidatelist.h>
#include <fcitx/inputpanel.h>
#include <fcitx/text.h>

#include <fstream>

namespace lingjian {

// ─── CandidateWord ──────────────────────────────────────────────

class LingJianCandidateWord : public fcitx::CandidateWord {
public:
    LingJianCandidateWord(LingJianState *state, std::string text, int index)
        : fcitx::CandidateWord(fcitx::Text(text)),
          state_(state),
          index_(index) {}

    void select(fcitx::InputContext * /*ic*/) const override {
        state_->commitCandidate(index_);
    }

private:
    LingJianState *state_;
    int index_;
};

// ─── LingJianState ──────────────────────────────────────────────

LingJianState::LingJianState(LingJianEngine *engine, fcitx::InputContext *ic)
    : engine_(engine), ic_(ic) {
    const auto &dictPath = engine_->dictPath();
    if (!dictPath.empty()) {
        ctx_.loadDictionary(dictPath);
    }
}

void LingJianState::keyEvent(fcitx::KeyEvent &event) {
    if (event.isRelease()) {
        return;
    }

    auto key = event.key();
    auto sym = key.sym();

    if (key.check(FcitxKey_Escape)) {
        if (ctx_.isComposing()) {
            ctx_.handleEscape();
            updateUI();
            event.filterAndAccept();
        }
        return;
    }

    if (key.check(FcitxKey_BackSpace)) {
        if (ctx_.isComposing()) {
            ctx_.handleBackspace();
            updateUI();
            event.filterAndAccept();
        }
        return;
    }

    if (key.check(FcitxKey_Return) || key.check(FcitxKey_KP_Enter)) {
        if (ctx_.isComposing()) {
            auto r = ctx_.handleEnter();
            if (r == core::InputContext::KeyResult::Committed) {
                ic_->commitString(ctx_.committedText());
                ctx_.clearCommitted();
            }
            updateUI();
            event.filterAndAccept();
        }
        return;
    }

    if (key.check(FcitxKey_space)) {
        if (ctx_.isComposing()) {
            auto r = ctx_.handleKey(' ');
            if (r == core::InputContext::KeyResult::Committed) {
                ic_->commitString(ctx_.committedText());
                ctx_.clearCommitted();
            }
            updateUI();
            event.filterAndAccept();
        }
        return;
    }

    if (key.check(FcitxKey_minus) || key.check(FcitxKey_Page_Up)) {
        if (ctx_.isComposing()) {
            handlePageNavigation(true);
            event.filterAndAccept();
        }
        return;
    }

    if (key.check(FcitxKey_equal) || key.check(FcitxKey_Page_Down)) {
        if (ctx_.isComposing()) {
            handlePageNavigation(false);
            event.filterAndAccept();
        }
        return;
    }

    // 1-9 candidate selection
    if (ctx_.isComposing() && sym >= FcitxKey_1 && sym <= FcitxKey_9 &&
        key.check(sym)) {
        int idx = static_cast<int>(sym - FcitxKey_1);
        auto list = ic_->inputPanel().candidateList();
        if (list && idx < list->size()) {
            list->candidate(idx).select(ic_);
        }
        event.filterAndAccept();
        return;
    }

    // a-z letter input (no modifiers)
    if (sym >= FcitxKey_a && sym <= FcitxKey_z && key.check(sym)) {
        char ch = static_cast<char>(sym - FcitxKey_a + 'a');
        ctx_.handleKey(ch);
        updateUI();
        event.filterAndAccept();
        return;
    }

    // A-Z with Shift → treat as lowercase
    if (sym >= FcitxKey_A && sym <= FcitxKey_Z &&
        key.check(sym, fcitx::KeyState::Shift)) {
        char ch = static_cast<char>(sym - FcitxKey_A + 'a');
        ctx_.handleKey(ch);
        updateUI();
        event.filterAndAccept();
        return;
    }
}

void LingJianState::reset() {
    if (ctx_.isComposing()) {
        ctx_.handleEscape();
    }
    updateUI();
}

void LingJianState::updateUI() {
    auto &panel = ic_->inputPanel();
    panel.reset();

    if (!ctx_.isComposing()) {
        ic_->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
        ic_->updatePreedit();
        return;
    }

    fcitx::Text preedit;
    auto segmented = ctx_.segmentedPreedit();
    if (!segmented.empty()) {
        preedit.append(segmented);
    } else {
        preedit.append(ctx_.preeditText());
    }
    preedit.setCursor(preedit.textLength());

    if (ic_->capabilityFlags().test(fcitx::CapabilityFlag::Preedit)) {
        panel.setClientPreedit(preedit);
    } else {
        panel.setPreedit(preedit);
    }

    auto allCandidates = ctx_.candidates();
    if (!allCandidates.empty()) {
        auto candidateList =
            std::make_unique<fcitx::CommonCandidateList>();
        candidateList->setPageSize(ctx_.pageSize());
        candidateList->setCursorPositionAfterPaging(
            fcitx::CursorPositionAfterPaging::ResetToFirst);

        fcitx::KeyList selKeys;
        for (int i = 1; i <= ctx_.pageSize(); ++i) {
            selKeys.emplace_back(
                static_cast<fcitx::KeySym>(FcitxKey_1 + i - 1));
        }
        candidateList->setSelectionKey(selKeys);

        for (size_t i = 0; i < allCandidates.size(); ++i) {
            candidateList->append<LingJianCandidateWord>(
                this, allCandidates[i].text, static_cast<int>(i));
        }

        panel.setCandidateList(std::move(candidateList));
    }

    ic_->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
    ic_->updatePreedit();
}

void LingJianState::commitCandidate(int index) {
    auto r = ctx_.selectCandidate(static_cast<size_t>(index));
    if (r == core::InputContext::KeyResult::Committed) {
        ic_->commitString(ctx_.committedText());
        ctx_.clearCommitted();
    }
    updateUI();
}

void LingJianState::handlePageNavigation(bool prev) {
    auto list = ic_->inputPanel().candidateList();
    if (!list) {
        return;
    }
    auto *pageable = list->toPageable();
    if (!pageable) {
        return;
    }
    if (prev && pageable->hasPrev()) {
        pageable->prev();
    } else if (!prev && pageable->hasNext()) {
        pageable->next();
    }
    ic_->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
}

// ─── LingJianEngine ─────────────────────────────────────────────

LingJianEngine::LingJianEngine(fcitx::Instance *instance)
    : instance_(instance) {
    dictPath_ = findDictPath();
    if (dictPath_.empty()) {
        FCITX_WARN() << "LingJian: pinyin_dict.txt not found";
    } else {
        FCITX_INFO() << "LingJian: dict loaded from " << dictPath_;
    }
    instance_->inputContextManager().registerProperty("lingjianState",
                                                      &factory_);
}

void LingJianEngine::keyEvent(const fcitx::InputMethodEntry & /*entry*/,
                              fcitx::KeyEvent &keyEvent) {
    auto *ic = keyEvent.inputContext();
    auto *state = ic->propertyFor(&factory_);
    state->keyEvent(keyEvent);
}

void LingJianEngine::activate(const fcitx::InputMethodEntry & /*entry*/,
                              fcitx::InputContextEvent &event) {
    auto *ic = event.inputContext();
    auto *state = ic->propertyFor(&factory_);
    state->reset();
}

void LingJianEngine::deactivate(const fcitx::InputMethodEntry & /*entry*/,
                                fcitx::InputContextEvent &event) {
    auto *ic = event.inputContext();
    auto *state = ic->propertyFor(&factory_);
    if (state->engine()) {
        state->reset();
    }
    ic->inputPanel().reset();
    ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
    ic->updatePreedit();
}

void LingJianEngine::reset(const fcitx::InputMethodEntry & /*entry*/,
                           fcitx::InputContextEvent &event) {
    auto *ic = event.inputContext();
    auto *state = ic->propertyFor(&factory_);
    state->reset();
}

std::string LingJianEngine::findDictPath() const {
    auto path = fcitx::StandardPath::global().locate(
        fcitx::StandardPath::Type::PkgData, "lingjian/pinyin_dict.txt");
    if (!path.empty()) {
        return path;
    }

    const std::vector<std::string> fallbacks = {
#ifdef LINGJIAN_PKGDATADIR
        std::string(LINGJIAN_PKGDATADIR) + "/pinyin_dict.txt",
#endif
        "/usr/share/fcitx5/lingjian/pinyin_dict.txt",
        "/usr/local/share/fcitx5/lingjian/pinyin_dict.txt",
        "/usr/share/lingjian-pinyin/data/pinyin_dict.txt",
    };

    for (const auto &p : fallbacks) {
        std::ifstream f(p);
        if (f.good()) {
            return p;
        }
    }

    return {};
}

} // namespace lingjian

FCITX_ADDON_FACTORY(lingjian::LingJianAddonFactory);
