#pragma once

#include <fcitx/addonfactory.h>
#include <fcitx/addonmanager.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputcontextproperty.h>
#include <fcitx/inputpanel.h>
#include <fcitx/candidatelist.h>
#include <fcitx/instance.h>

#include <memory>
#include <string>

#include "context.h"

namespace lingjian {

class LingJianEngine;

class LingJianState : public fcitx::InputContextProperty {
public:
    LingJianState(LingJianEngine *engine, fcitx::InputContext *ic);

    void keyEvent(fcitx::KeyEvent &event);
    void reset();
    void updateUI();
    void commitCandidate(int index);

    LingJianEngine *engine() const { return engine_; }

private:
    void handlePageNavigation(bool prev);

    LingJianEngine *engine_;
    fcitx::InputContext *ic_;
    core::InputContext ctx_;
};

class LingJianEngine : public fcitx::InputMethodEngine {
public:
    LingJianEngine(fcitx::Instance *instance);

    void keyEvent(const fcitx::InputMethodEntry &entry,
                  fcitx::KeyEvent &keyEvent) override;
    void activate(const fcitx::InputMethodEntry &entry,
                  fcitx::InputContextEvent &event) override;
    void deactivate(const fcitx::InputMethodEntry &entry,
                    fcitx::InputContextEvent &event) override;
    void reset(const fcitx::InputMethodEntry &entry,
               fcitx::InputContextEvent &event) override;

    fcitx::FactoryFor<LingJianState> &factory() { return factory_; }
    const std::string &dictPath() const { return dictPath_; }
    fcitx::Instance *instance() const { return instance_; }

private:
    std::string findDictPath() const;

    fcitx::Instance *instance_;
    fcitx::FactoryFor<LingJianState> factory_{
        [this](fcitx::InputContext &ic) {
            return new LingJianState(this, &ic);
        }};
    std::string dictPath_;
};

class LingJianAddonFactory : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *
    create(fcitx::AddonManager *manager) override {
        return new LingJianEngine(manager->instance());
    }
};

} // namespace lingjian
