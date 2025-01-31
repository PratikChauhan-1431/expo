/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ABI45_0_0RCTScheduler.h"

#import <ABI45_0_0React/ABI45_0_0renderer/animations/LayoutAnimationDriver.h>
#import <ABI45_0_0React/ABI45_0_0renderer/componentregistry/ComponentDescriptorFactory.h>
#import <ABI45_0_0React/ABI45_0_0renderer/debug/SystraceSection.h>
#import <ABI45_0_0React/ABI45_0_0renderer/scheduler/Scheduler.h>
#import <ABI45_0_0React/ABI45_0_0renderer/scheduler/SchedulerDelegate.h>
#include <ABI45_0_0React/ABI45_0_0utils/RunLoopObserver.h>

#import <ABI45_0_0React/ABI45_0_0RCTFollyConvert.h>

#import "ABI45_0_0RCTConversions.h"

using namespace ABI45_0_0facebook::ABI45_0_0React;

class SchedulerDelegateProxy : public SchedulerDelegate {
 public:
  SchedulerDelegateProxy(void *scheduler) : scheduler_(scheduler) {}

  void schedulerDidFinishTransaction(MountingCoordinator::Shared const &mountingCoordinator) override
  {
    ABI45_0_0RCTScheduler *scheduler = (__bridge ABI45_0_0RCTScheduler *)scheduler_;
    [scheduler.delegate schedulerDidFinishTransaction:mountingCoordinator];
  }

  void schedulerDidRequestPreliminaryViewAllocation(SurfaceId surfaceId, const ShadowNode &shadowNode) override
  {
    // Does nothing.
    // This delegate method is not currently used on iOS.
  }

  void schedulerDidCloneShadowNode(
      SurfaceId surfaceId,
      const ShadowNode &oldShadowNode,
      const ShadowNode &newShadowNode) override
  {
    // Does nothing.
    // This delegate method is not currently used on iOS.
  }

  void schedulerDidDispatchCommand(
      const ShadowView &shadowView,
      const std::string &commandName,
      const folly::dynamic &args) override
  {
    ABI45_0_0RCTScheduler *scheduler = (__bridge ABI45_0_0RCTScheduler *)scheduler_;
    [scheduler.delegate schedulerDidDispatchCommand:shadowView commandName:commandName args:args];
  }

  void schedulerDidSetIsJSResponder(ShadowView const &shadowView, bool isJSResponder, bool blockNativeResponder)
      override
  {
    ABI45_0_0RCTScheduler *scheduler = (__bridge ABI45_0_0RCTScheduler *)scheduler_;
    [scheduler.delegate schedulerDidSetIsJSResponder:isJSResponder
                                blockNativeResponder:blockNativeResponder
                                       forShadowView:shadowView];
  }

  void schedulerDidSendAccessibilityEvent(const ShadowView &shadowView, std::string const &eventType) override
  {
    ABI45_0_0RCTScheduler *scheduler = (__bridge ABI45_0_0RCTScheduler *)scheduler_;
    [scheduler.delegate schedulerDidSendAccessibilityEvent:shadowView eventType:eventType];
  }

 private:
  void *scheduler_;
};

class LayoutAnimationDelegateProxy : public LayoutAnimationStatusDelegate, public RunLoopObserver::Delegate {
 public:
  LayoutAnimationDelegateProxy(void *scheduler) : scheduler_(scheduler) {}
  virtual ~LayoutAnimationDelegateProxy() {}

  void onAnimationStarted() override
  {
    ABI45_0_0RCTScheduler *scheduler = (__bridge ABI45_0_0RCTScheduler *)scheduler_;
    [scheduler onAnimationStarted];
  }

  /**
   * Called when the LayoutAnimation engine completes all pending animations.
   */
  void onAllAnimationsComplete() override
  {
    ABI45_0_0RCTScheduler *scheduler = (__bridge ABI45_0_0RCTScheduler *)scheduler_;
    [scheduler onAllAnimationsComplete];
  }

  void activityDidChange(RunLoopObserver::Delegate const *delegate, RunLoopObserver::Activity activity)
      const noexcept override
  {
    ABI45_0_0RCTScheduler *scheduler = (__bridge ABI45_0_0RCTScheduler *)scheduler_;
    [scheduler animationTick];
  }

 private:
  void *scheduler_;
};

@implementation ABI45_0_0RCTScheduler {
  std::unique_ptr<Scheduler> _scheduler;
  std::shared_ptr<LayoutAnimationDriver> _animationDriver;
  std::shared_ptr<SchedulerDelegateProxy> _delegateProxy;
  std::shared_ptr<LayoutAnimationDelegateProxy> _layoutAnimationDelegateProxy;
  RunLoopObserver::Unique _uiRunLoopObserver;
}

- (instancetype)initWithToolbox:(SchedulerToolbox)toolbox
{
  if (self = [super init]) {
    auto ABI45_0_0ReactNativeConfig =
        toolbox.contextContainer->at<std::shared_ptr<const ABI45_0_0ReactNativeConfig>>("ABI45_0_0ReactNativeConfig");

    _delegateProxy = std::make_shared<SchedulerDelegateProxy>((__bridge void *)self);

    if (ABI45_0_0ReactNativeConfig->getBool("ABI45_0_0React_fabric:enabled_layout_animations_ios")) {
      _layoutAnimationDelegateProxy = std::make_shared<LayoutAnimationDelegateProxy>((__bridge void *)self);
      _animationDriver = std::make_shared<LayoutAnimationDriver>(
          toolbox.runtimeExecutor, toolbox.contextContainer, _layoutAnimationDelegateProxy.get());
      if (ABI45_0_0ReactNativeConfig->getBool("ABI45_0_0React_fabric:enabled_skip_invalidated_key_frames_ios")) {
        _animationDriver->enableSkipInvalidatedKeyFrames();
      }
      if (ABI45_0_0ReactNativeConfig->getBool("ABI45_0_0React_fabric:enable_crash_on_missing_component_descriptor")) {
        _animationDriver->enableCrashOnMissingComponentDescriptor();
      }
      if (ABI45_0_0ReactNativeConfig->getBool("ABI45_0_0React_fabric:enable_simulate_image_props_memory_access")) {
        _animationDriver->enableSimulateImagePropsMemoryAccess();
      }
      _uiRunLoopObserver =
          toolbox.mainRunLoopObserverFactory(RunLoopObserver::Activity::BeforeWaiting, _layoutAnimationDelegateProxy);
      _uiRunLoopObserver->setDelegate(_layoutAnimationDelegateProxy.get());
    }

    _scheduler = std::make_unique<Scheduler>(
        toolbox, (_animationDriver ? _animationDriver.get() : nullptr), _delegateProxy.get());
  }

  return self;
}

- (void)animationTick
{
  _scheduler->animationTick();
}

- (void)dealloc
{
  if (_animationDriver) {
    _animationDriver->setLayoutAnimationStatusDelegate(nullptr);
  }

  _scheduler->setDelegate(nullptr);
}

- (void)registerSurface:(ABI45_0_0facebook::ABI45_0_0React::SurfaceHandler const &)surfaceHandler
{
  _scheduler->registerSurface(surfaceHandler);
}

- (void)unregisterSurface:(ABI45_0_0facebook::ABI45_0_0React::SurfaceHandler const &)surfaceHandler
{
  _scheduler->unregisterSurface(surfaceHandler);
}

- (ComponentDescriptor const *)findComponentDescriptorByHandle_DO_NOT_USE_THIS_IS_BROKEN:(ComponentHandle)handle
{
  return _scheduler->findComponentDescriptorByHandle_DO_NOT_USE_THIS_IS_BROKEN(handle);
}

- (void)setupAnimationDriver:(ABI45_0_0facebook::ABI45_0_0React::SurfaceHandler const &)surfaceHandler
{
  surfaceHandler.getMountingCoordinator()->setMountingOverrideDelegate(_animationDriver);
}

- (void)onAnimationStarted
{
  if (_uiRunLoopObserver) {
    _uiRunLoopObserver->enable();
  }
}

- (void)onAllAnimationsComplete
{
  if (_uiRunLoopObserver) {
    _uiRunLoopObserver->disable();
  }
}

@end
