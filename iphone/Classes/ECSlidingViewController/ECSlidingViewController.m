//
//  ECSlidingViewController.m
//  ECSlidingViewController
//
//  Created by Michael Enriquez on 1/23/12.
//  Copyright (c) 2012 EdgeCase. All rights reserved.
//

#import "ECSlidingViewController.h"

NSString *const ECSlidingViewUnderRightWillAppear    = @"ECSlidingViewUnderRightWillAppear";
NSString *const ECSlidingViewUnderLeftWillAppear     = @"ECSlidingViewUnderLeftWillAppear";
NSString *const ECSlidingViewUnderLeftWillDisappear  = @"ECSlidingViewUnderLeftWillDisappear";
NSString *const ECSlidingViewUnderRightWillDisappear = @"ECSlidingViewUnderRightWillDisappear";
NSString *const ECSlidingViewTopDidAnchorLeft        = @"ECSlidingViewTopDidAnchorLeft";
NSString *const ECSlidingViewTopDidAnchorRight       = @"ECSlidingViewTopDidAnchorRight";
NSString *const ECSlidingViewTopWillReset            = @"ECSlidingViewTopWillReset";
NSString *const ECSlidingViewTopDidReset             = @"ECSlidingViewTopDidReset";

@interface ECSlidingViewController()

@property (nonatomic, strong) UIView *topViewSnapshot;
@property (nonatomic, assign) CGFloat initialTouchPositionX;
@property (nonatomic, assign) CGFloat initialHorizontalCenter;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong) UITapGestureRecognizer *resetTapGesture;
@property (nonatomic, strong) UIPanGestureRecognizer *topViewSnapshotPanGesture;
@property (nonatomic, assign) BOOL underLeftShowing;
@property (nonatomic, assign) BOOL underRightShowing;
@property (nonatomic, assign) BOOL topViewIsOffScreen;

- (NSUInteger)autoResizeToFillScreen;
- (UIView *)topView;
- (UIView *)underLeftView;
- (UIView *)underRightView;
- (void)adjustLayout;
- (void)updateTopViewHorizontalCenterWithRecognizer:(UIPanGestureRecognizer *)recognizer;
- (void)updateTopViewHorizontalCenter:(CGFloat)newHorizontalCenter;
- (void)topViewHorizontalCenterWillChange:(CGFloat)newHorizontalCenter;
- (void)topViewHorizontalCenterDidChange:(CGFloat)newHorizontalCenter;
- (void)addTopViewSnapshot;
- (void)removeTopViewSnapshot;
- (CGFloat)anchorRightTopViewCenter;
- (CGFloat)anchorLeftTopViewCenter;
- (CGFloat)resettedCenter;
- (void)underLeftWillAppear;
- (void)underRightWillAppear;
- (void)topDidReset;
- (BOOL)topViewHasFocus;
- (void)updateUnderLeftLayout;
- (void)updateUnderRightLayout;

@end

@implementation UIViewController(SlidingViewExtension)

- (ECSlidingViewController *)slidingViewController
{
  UIViewController *viewController = self.parentViewController;
  while (!(viewController == nil || [viewController isKindOfClass:[ECSlidingViewController class]])) {
    viewController = viewController.parentViewController;
  }
  
  return (ECSlidingViewController *)viewController;
}

@end

@implementation ECSlidingViewController

// public properties
@synthesize underLeftViewController  = _underLeftViewController;
@synthesize underRightViewController = _underRightViewController;
@synthesize topViewController        = _topViewController;
@synthesize anchorLeftPeekAmount;
@synthesize anchorRightPeekAmount;
@synthesize anchorLeftRevealAmount;
@synthesize anchorRightRevealAmount;
@synthesize underRightWidthLayout = _underRightWidthLayout;
@synthesize underLeftWidthLayout  = _underLeftWidthLayout;
@synthesize shouldAllowPanningPastAnchor;
@synthesize shouldAllowUserInteractionsWhenAnchored;
@synthesize shouldAddPanGestureRecognizerToTopViewSnapshot;
@synthesize resetStrategy = _resetStrategy;
@synthesize grabbableBorderAmount;
@synthesize animationDuration;
@synthesize delegate;

// category properties
@synthesize topViewSnapshot;
@synthesize initialTouchPositionX;
@synthesize initialHorizontalCenter;
@synthesize disableOnScrollView;
@synthesize panGesture = _panGesture;
@synthesize resetTapGesture;
@synthesize underLeftShowing   = _underLeftShowing;
@synthesize underRightShowing  = _underRightShowing;
@synthesize topViewIsOffScreen = _topViewIsOffScreen;
@synthesize topViewSnapshotPanGesture = _topViewSnapshotPanGesture;

- (void)setTopViewController:(UIViewController *)theTopViewController
{
  CGRect topViewFrame = _topViewController ? _topViewController.view.frame : self.view.bounds;
  
  [self removeTopViewSnapshot];
  [_topViewController.view removeFromSuperview];
  [_topViewController willMoveToParentViewController:nil];
  [_topViewController removeFromParentViewController];
  
  _topViewController = theTopViewController;
  
  [self addChildViewController:self.topViewController];
  [self.topViewController didMoveToParentViewController:self];
  
  [_topViewController.view setAutoresizingMask:self.autoResizeToFillScreen];
  [_topViewController.view setFrame:topViewFrame];
  _topViewController.view.layer.shadowOffset = CGSizeZero;
  _topViewController.view.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.view.layer.bounds].CGPath;
  
  [self.view addSubview:_topViewController.view];
  self.topViewSnapshot.frame = self.topView.bounds;
}

- (void)setUnderLeftViewController:(UIViewController *)theUnderLeftViewController
{
  [_underLeftViewController.view removeFromSuperview];
  [_underLeftViewController willMoveToParentViewController:nil];
  [_underLeftViewController removeFromParentViewController];
  
  _underLeftViewController = theUnderLeftViewController;
  
  if (_underLeftViewController) {
    [self addChildViewController:self.underLeftViewController];
    [self.underLeftViewController didMoveToParentViewController:self];
    
    [self updateUnderLeftLayout];
  }
}

- (void)setUnderRightViewController:(UIViewController *)theUnderRightViewController
{
  [_underRightViewController.view removeFromSuperview];
  [_underRightViewController willMoveToParentViewController:nil];
  [_underRightViewController removeFromParentViewController];
  
  _underRightViewController = theUnderRightViewController;
  
  if (_underRightViewController) {
    [self addChildViewController:self.underRightViewController];
    [self.underRightViewController didMoveToParentViewController:self];
    
    [self updateUnderRightLayout];
  }
}

- (void)setUnderLeftWidthLayout:(ECViewWidthLayout)underLeftWidthLayout
{
  if (underLeftWidthLayout == ECVariableRevealWidth && self.anchorRightPeekAmount <= 0) {
    [NSException raise:@"Invalid Width Layout" format:@"anchorRightPeekAmount must be set"];
  } else if (underLeftWidthLayout == ECFixedRevealWidth && self.anchorRightRevealAmount <= 0) {
    [NSException raise:@"Invalid Width Layout" format:@"anchorRightRevealAmount must be set"];
  }
  
  _underLeftWidthLayout = underLeftWidthLayout;
}

- (void)setUnderRightWidthLayout:(ECViewWidthLayout)underRightWidthLayout
{
  if (underRightWidthLayout == ECVariableRevealWidth && self.anchorLeftPeekAmount <= 0) {
    [NSException raise:@"Invalid Width Layout" format:@"anchorLeftPeekAmount must be set"];
  } else if (underRightWidthLayout == ECFixedRevealWidth && self.anchorLeftRevealAmount <= 0) {
    [NSException raise:@"Invalid Width Layout" format:@"anchorLeftRevealAmount must be set"];
  }
  
  _underRightWidthLayout = underRightWidthLayout;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.shouldAllowPanningPastAnchor = YES;
  self.shouldAllowUserInteractionsWhenAnchored = NO;
  self.shouldAddPanGestureRecognizerToTopViewSnapshot = NO;
  self.resetTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(resetTopView)];
  _panGesture          = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(updateTopViewHorizontalCenterWithRecognizer:)];
  self.resetTapGesture.enabled = NO;
  self.resetStrategy = ECTapping | ECPanning;
  self.panningVelocityXThreshold = 100;
  self.disableOnScrollView = NO;
  
  self.topViewSnapshot = [[UIView alloc] initWithFrame:self.topView.bounds];
  [self.topViewSnapshot setAutoresizingMask:self.autoResizeToFillScreen];
  [self.topViewSnapshot addGestureRecognizer:self.resetTapGesture];
  self.grabbableBorderAmount = -1;
  self.animationDuration = 0.25f;
  panning = NO;
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];
  self.topView.layer.shadowOffset = CGSizeZero;
  self.topView.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.view.layer.bounds].CGPath;
  [self adjustLayout];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
  self.topView.layer.shadowPath = nil;
  self.topView.layer.shouldRasterize = YES;
  
  if(![self topViewHasFocus]){
    [self removeTopViewSnapshot];
  }
  
  [self adjustLayout];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation{
  self.topView.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.view.layer.bounds].CGPath;
  self.topView.layer.shouldRasterize = NO;
  
  if(![self topViewHasFocus]){
    [self addTopViewSnapshot];
  }
}

- (void)setResetStrategy:(ECResetStrategy)theResetStrategy
{
  _resetStrategy = theResetStrategy;
  if (_resetStrategy & ECTapping) {
    self.resetTapGesture.enabled = YES;
  } else {
    self.resetTapGesture.enabled = NO;
  }
}

- (void)adjustLayout
{
  self.topViewSnapshot.frame = self.topView.bounds;
  
  if ([self underRightShowing] && ![self topViewIsOffScreen]) {
    [self updateUnderRightLayout];
    [self updateTopViewHorizontalCenter:self.anchorLeftTopViewCenter];
  } else if ([self underRightShowing] && [self topViewIsOffScreen]) {
    [self updateUnderRightLayout];
    [self updateTopViewHorizontalCenter:-self.resettedCenter];
  } else if ([self underLeftShowing] && ![self topViewIsOffScreen]) {
    [self updateUnderLeftLayout];
    [self updateTopViewHorizontalCenter:self.anchorRightTopViewCenter];
  } else if ([self underLeftShowing] && [self topViewIsOffScreen]) {
    [self updateUnderLeftLayout];
    [self updateTopViewHorizontalCenter:self.view.bounds.size.width + self.resettedCenter];
  }
}

-(BOOL)HasScrollViewChild:(UIView*)view atPosition:(CGPoint)point
{
    if (CGRectContainsPoint(view.frame, point)) {
        if ([view isKindOfClass:[UIScrollView class]]) {
            return true;
        }
       for (UIView *v in view.subviews) {
           CGPoint pointInViewCoords = [v convertPoint:point fromView:view];
           if ([self HasScrollViewChild:v atPosition:pointInViewCoords])
               return true;
        }
    }
    return false;
}

- (void)updateTopViewHorizontalCenterWithRecognizer:(UIPanGestureRecognizer *)recognizer
{
  CGPoint currentTouchPoint     = [recognizer locationInView:self.view];
  CGPoint controllerPoint     = [recognizer locationInView:recognizer.view];
  CGFloat currentTouchPositionX = currentTouchPoint.x;
  if (recognizer.state == UIGestureRecognizerStateBegan) {
      if (self.grabbableBorderAmount < 0 || currentTouchPositionX < self.grabbableBorderAmount || currentTouchPositionX > (self.view.frame.size.width-self.grabbableBorderAmount) || (disableOnScrollView && [self HasScrollViewChild:recognizer.view atPosition:controllerPoint])) {
      self.initialTouchPositionX = currentTouchPositionX;
      self.initialHorizontalCenter = self.topView.center.x;
    }
    else {
      recognizer.enabled = NO;
      recognizer.enabled = YES;
    }
  } else if (recognizer.state == UIGestureRecognizerStateChanged) {
    CGFloat panAmount = self.initialTouchPositionX - currentTouchPositionX;
    CGFloat newCenterPosition = self.initialHorizontalCenter - panAmount;
    
    if ((newCenterPosition < self.resettedCenter && (self.anchorLeftTopViewCenter == NSNotFound || self.underRightViewController == nil)) ||
        (newCenterPosition > self.resettedCenter && (self.anchorRightTopViewCenter == NSNotFound || self.underLeftViewController == nil))) {
      newCenterPosition = self.resettedCenter;
    }
    
    CGFloat offset = self.resettedCenter - newCenterPosition;
    if (offset != 0){
      if (!panning) {
        panning = YES;
        if (delegate && [delegate respondsToSelector:@selector(panStarted:)]) {
          [delegate panStarted:-offset];
        }
      }
      
      BOOL newCenterPositionIsOutsideAnchor = newCenterPosition < self.anchorLeftTopViewCenter || self.anchorRightTopViewCenter < newCenterPosition;
      
      if ((newCenterPositionIsOutsideAnchor && self.shouldAllowPanningPastAnchor) || !newCenterPositionIsOutsideAnchor) {
        [self topViewHorizontalCenterWillChange:newCenterPosition];
        [self updateTopViewHorizontalCenter:newCenterPosition];
        [self topViewHorizontalCenterDidChange:newCenterPosition];
      }

      if (delegate && [delegate respondsToSelector:@selector(panChanged:)]) {
        [delegate panChanged:-offset];
      }
    }
    
  } else if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled) {
    CGPoint currentVelocityPoint = [recognizer velocityInView:self.view];
    CGFloat currentVelocityX     = currentVelocityPoint.x;
    
    if (panning) {
      panning = NO;
      if (delegate && [delegate respondsToSelector:@selector(panEnded:)]) {
        CGFloat offset = self.resettedCenter - self.topView.layer.position.x;
        [delegate panEnded:-offset];
      }
      
      if ([self underLeftShowing] && (currentVelocityX > self.panningVelocityXThreshold || self.topView.layer.position.x >= self.anchorRightTopViewCenter)) {
        [self anchorTopViewTo:ECRight];
      } else if ([self underRightShowing] && (currentVelocityX < self.panningVelocityXThreshold || self.topView.layer.position.x <= self.anchorLeftTopViewCenter)) {
        [self anchorTopViewTo:ECLeft];
      } else {
        [self resetTopView];
      }
    }
  }
}

- (UIPanGestureRecognizer *)panGesture
{
  return _panGesture;
}

- (void)anchorTopViewTo:(ECSide)side
{
  [self anchorTopViewTo:side animated:YES];
}

- (void)anchorTopViewTo:(ECSide)side animated:(BOOL)animated
{
  [self anchorTopViewTo:side animations:nil onComplete:nil animated:animated];
}

- (void)anchorTopViewTo:(ECSide)side animations:(void (^)())animations onComplete:(void (^)())complete
{
  [self anchorTopViewTo:side animations:nil onComplete:nil animated:YES];
}

- (void)anchorTopViewTo:(ECSide)side animations:(void (^)())animations onComplete:(void (^)())complete animated:(BOOL)animated
{
  CGFloat newCenter = self.topView.center.x;
    
  if (delegate && [delegate respondsToSelector:@selector(willAnchorTopTo:animated:)]) {
    [delegate willAnchorTopTo:side animated:animated];
  }

  if (side == ECLeft) {
    newCenter = self.anchorLeftTopViewCenter;
  } else if (side == ECRight) {
    newCenter = self.anchorRightTopViewCenter;
  }
    
  [self topViewHorizontalCenterWillChange:newCenter];
    
  void (^animationBlock)() = ^() {
    if (animations) {
      animations();
    }
    [self updateTopViewHorizontalCenter:newCenter];
  };
  void (^completeBlock)(BOOL finished) = ^(BOOL finished) {
    if (_resetStrategy & ECPanning) {
      self.panGesture.enabled = YES;
    } else {
      self.panGesture.enabled = NO;
    }
    if (complete) {
      complete();
    }
    _topViewIsOffScreen = NO;
    [self addTopViewSnapshot];
    dispatch_async(dispatch_get_main_queue(), ^{
      NSString *key = (side == ECLeft) ? ECSlidingViewTopDidAnchorLeft :ECSlidingViewTopDidAnchorRight;
      [[NSNotificationCenter defaultCenter] postNotificationName:key object:self userInfo:nil];
    });
  };

  
  if (!animated)
  {
    animationBlock();
    completeBlock(YES);
  }
  else
  {
    [UIView animateWithDuration:self.animationDuration animations:animationBlock completion:completeBlock];
  }
  
}

- (void)anchorTopViewOffScreenTo:(ECSide)side
{
  [self anchorTopViewOffScreenTo:side animated:YES];
}

- (void)anchorTopViewOffScreenTo:(ECSide)side animated:(BOOL)animated
{
  [self anchorTopViewOffScreenTo:side animations:nil onComplete:nil animated:animated];
}

- (void)anchorTopViewOffScreenTo:(ECSide)side animations:(void(^)())animations onComplete:(void(^)())complete
{
  [self anchorTopViewOffScreenTo:side animations:nil onComplete:nil animated:YES];
}

- (void)anchorTopViewOffScreenTo:(ECSide)side animations:(void(^)())animations onComplete:(void(^)())complete animated:(BOOL)animated
{
  CGFloat newCenter = self.topView.center.x;
  
  if (side == ECLeft) {
    newCenter = -self.resettedCenter;
  } else if (side == ECRight) {
    newCenter = self.view.bounds.size.width + self.resettedCenter;
  }
  
  [self topViewHorizontalCenterWillChange:newCenter];
  
  [UIView animateWithDuration:self.animationDuration animations:^{
    if (animations) {
      animations();
    }
    [self updateTopViewHorizontalCenter:newCenter];
  } completion:^(BOOL finished){
    if (complete) {
      complete();
    }
    _topViewIsOffScreen = YES;
    [self addTopViewSnapshot];
    dispatch_async(dispatch_get_main_queue(), ^{
      NSString *key = (side == ECLeft) ? ECSlidingViewTopDidAnchorLeft : ECSlidingViewTopDidAnchorRight;
      [[NSNotificationCenter defaultCenter] postNotificationName:key object:self userInfo:nil];
    });
  }];
}


- (void)resetTopView
{
  [self resetTopView:YES];
}

- (void)resetTopView:(BOOL)animated
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:ECSlidingViewTopWillReset object:self userInfo:nil];
  });
  [self resetTopViewWithAnimations:nil onComplete:nil animated:animated];
}

- (void)resetTopViewWithAnimations:(void(^)())animations onComplete:(void(^)())complete
{
  [self resetTopViewWithAnimations:nil onComplete:nil animated:YES];
}

- (void)resetTopViewWithAnimations:(void(^)())animations onComplete:(void(^)())complete animated:(BOOL)animated
{
  [self topViewHorizontalCenterWillChange:self.resettedCenter];
    
  if (delegate && [delegate respondsToSelector:@selector(willResetTopView:fromSide:)]) {
      [delegate willResetTopView:animated fromSide:([self underLeftShowing]?ECRight:ECLeft)];
  }
    
  void (^animationBlock)() = ^() {
    if (animations) {
      animations();
    }
    [self updateTopViewHorizontalCenter:self.resettedCenter];
  };
  void (^completeBlock)(BOOL finished) = ^(BOOL finished) {
    if (complete) {
      complete();
    }
    [self topViewHorizontalCenterDidChange:self.resettedCenter];
  };
    
  if (!animated)
  {
    animationBlock();
    completeBlock(YES);
  }
  else
  {
    [UIView animateWithDuration:self.animationDuration animations:animationBlock completion:completeBlock];
  }
}

- (NSUInteger)autoResizeToFillScreen
{
  return (UIViewAutoresizingFlexibleWidth |
          UIViewAutoresizingFlexibleHeight |
          UIViewAutoresizingFlexibleTopMargin |
          UIViewAutoresizingFlexibleBottomMargin |
          UIViewAutoresizingFlexibleLeftMargin |
          UIViewAutoresizingFlexibleRightMargin);
}

- (UIView *)topView
{
  return self.topViewController.view;
}

- (UIView *)underLeftView
{
  return self.underLeftViewController.view;
}

- (UIView *)underRightView
{
  return self.underRightViewController.view;
}

- (void)updateTopViewHorizontalCenter:(CGFloat)newHorizontalCenter
{
  CGPoint center = self.topView.center;
  center.x = newHorizontalCenter;
  self.topView.layer.position = center;
  if (self.topViewCenterMoved) self.topViewCenterMoved(newHorizontalCenter);
}

- (void)topViewHorizontalCenterWillChange:(CGFloat)newHorizontalCenter
{
  CGPoint center = self.topView.center;
  
	if (center.x >= self.resettedCenter && newHorizontalCenter == self.resettedCenter) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotificationName:ECSlidingViewUnderLeftWillDisappear object:self userInfo:nil];
		});
	}
	
	if (center.x <= self.resettedCenter && newHorizontalCenter == self.resettedCenter) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotificationName:ECSlidingViewUnderRightWillDisappear object:self userInfo:nil];
		});
	}
	
  if (center.x <= self.resettedCenter && newHorizontalCenter > self.resettedCenter) {
    [self underLeftWillAppear];
  } else if (center.x >= self.resettedCenter && newHorizontalCenter < self.resettedCenter) {
    [self underRightWillAppear];
  }  
}

- (void)topViewHorizontalCenterDidChange:(CGFloat)newHorizontalCenter
{
  if (newHorizontalCenter == self.resettedCenter) {
    [self topDidReset];
  }
}

- (void)addTopViewSnapshot
{
  if (!self.topViewSnapshot.superview && !self.shouldAllowUserInteractionsWhenAnchored) {
    //topViewSnapshot.layer.contents = (id)[UIImage imageWithUIView:self.topView].CGImage;
    [self.topView addSubview:self.topViewSnapshot];
    
    if (self.shouldAddPanGestureRecognizerToTopViewSnapshot && (_resetStrategy & ECPanning)) {
      if (!_topViewSnapshotPanGesture) {
        _topViewSnapshotPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(updateTopViewHorizontalCenterWithRecognizer:)];
      }
      [topViewSnapshot addGestureRecognizer:_topViewSnapshotPanGesture];
    }
    [self.topView addSubview:self.topViewSnapshot];
  }
}

- (void)removeTopViewSnapshot
{
  if (self.topViewSnapshot.superview) {
    [self.topViewSnapshot removeFromSuperview];
  }
}

- (CGFloat)anchorRightTopViewCenter
{
  if (self.underLeftWidthLayout == ECVariableRevealWidth) {
    return self.view.bounds.size.width + self.resettedCenter - self.anchorRightPeekAmount;
  } else if (self.underLeftWidthLayout == ECFixedRevealWidth) {
    return self.resettedCenter + self.anchorRightRevealAmount;
  } else {
    return NSNotFound;
  }
}

- (CGFloat)anchorLeftTopViewCenter
{
  if (self.underRightWidthLayout == ECVariableRevealWidth) {
    return -self.resettedCenter + self.anchorLeftPeekAmount;
  } else if (self.underRightWidthLayout == ECFixedRevealWidth) {
    return -self.resettedCenter + (self.view.bounds.size.width - self.anchorLeftRevealAmount);
  } else {
    return NSNotFound;
  }
}

- (CGFloat)resettedCenter
{
  return (self.view.bounds.size.width / 2);
}

- (void)underLeftWillAppear
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:ECSlidingViewUnderLeftWillAppear object:self userInfo:nil];
  });
  [self.underRightView removeFromSuperview];
  [self updateUnderLeftLayout];
  [self.view insertSubview:self.underLeftView belowSubview:self.topView];
  _underLeftShowing  = YES;
  _underRightShowing = NO;
}

- (void)underRightWillAppear
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:ECSlidingViewUnderRightWillAppear object:self userInfo:nil];
  });
  [self.underLeftView removeFromSuperview];
  [self updateUnderRightLayout];
  [self.view insertSubview:self.underRightView belowSubview:self.topView];
  _underLeftShowing  = NO;
  _underRightShowing = YES;
}

- (void)topDidReset
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:ECSlidingViewTopDidReset object:self userInfo:nil];
  });
  [self.topView removeGestureRecognizer:self.resetTapGesture];
  [self removeTopViewSnapshot];
  self.panGesture.enabled = YES;
  [self.underRightView removeFromSuperview];
  [self.underLeftView removeFromSuperview];
  _underLeftShowing   = NO;
  _underRightShowing  = NO;
  _topViewIsOffScreen = NO;
}

- (BOOL)topViewHasFocus
{
  return !_underLeftShowing && !_underRightShowing && !_topViewIsOffScreen;
}

- (void)updateUnderLeftLayout
{
  if (self.underLeftWidthLayout == ECFullWidth) {
    [self.underLeftView setAutoresizingMask:self.autoResizeToFillScreen];
    [self.underLeftView setFrame:self.view.bounds];
  } else if (self.underLeftWidthLayout == ECVariableRevealWidth && !self.topViewIsOffScreen) {
    CGRect frame = self.view.bounds;
    
    frame.size.width = frame.size.width - self.anchorRightPeekAmount;
    self.underLeftView.frame = frame;
  } else if (self.underLeftWidthLayout == ECFixedRevealWidth) {
    CGRect frame = self.view.bounds;
    
    frame.size.width = self.anchorRightRevealAmount;
    self.underLeftView.frame = frame;
  } else {
    [NSException raise:@"Invalid Width Layout" format:@"underLeftWidthLayout must be a valid ECViewWidthLayout"];
  }
}

- (void)updateUnderRightLayout
{
  if (self.underRightWidthLayout == ECFullWidth) {
    [self.underRightViewController.view setAutoresizingMask:self.autoResizeToFillScreen];
    self.underRightView.frame = self.view.bounds;
  } else if (self.underRightWidthLayout == ECVariableRevealWidth) {
    CGRect frame = self.view.bounds;
    
    CGFloat newLeftEdge;
    CGFloat newWidth = frame.size.width;
    
    if (self.topViewIsOffScreen) {
      newLeftEdge = 0;
    } else {
      newLeftEdge = self.anchorLeftPeekAmount;
      newWidth   -= self.anchorLeftPeekAmount;
    }
    
    frame.origin.x   = newLeftEdge;
    frame.size.width = newWidth;
    
    self.underRightView.frame = frame;
  } else if (self.underRightWidthLayout == ECFixedRevealWidth) {
    CGRect frame = self.view.bounds;
    
    CGFloat newLeftEdge = frame.size.width - self.anchorLeftRevealAmount;
    CGFloat newWidth = self.anchorLeftRevealAmount;
    
    frame.origin.x   = newLeftEdge;
    frame.size.width = newWidth;
    
    self.underRightView.frame = frame;
  } else {
    [NSException raise:@"Invalid Width Layout" format:@"underRightWidthLayout must be a valid ECViewWidthLayout"];
  }
}

- (CGFloat)getViewWidth:(ECSide)side
{
    if (side == ECLeft) {
        return fabs(self.resettedCenter - self.anchorRightTopViewCenter);
    }
    else
        return fabs(self.resettedCenter - self.anchorLeftTopViewCenter);
}

@end
