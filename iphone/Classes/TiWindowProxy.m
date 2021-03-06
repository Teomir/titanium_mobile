/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2013 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "TiWindowProxy.h"
#import "TiUIWindow.h"
#import "TiApp.h"
#import "TiErrorController.h"
#import "TiTransitionAnimation+Friend.h"
#import "TiTransitionAnimationStep.h"

@interface TiWindowProxy(Private)
-(void)openOnUIThread:(id)args;
-(void)closeOnUIThread:(id)args;
-(void)rootViewDidForceFrame:(NSNotification *)notification;
@end

@implementation TiWindowProxy
{
    BOOL readyToBeLayout;
}

@synthesize tab = tab;
@synthesize isManaged;

-(id)init
{
	if ((self = [super init]))
	{
        [self setDefaultReadyToCreateView:YES];
        opening = NO;
        opened = NO;
        readyToBeLayout = NO;
	}
	return self;
}

-(void) dealloc {
    
#ifdef USE_TI_UIIOSTRANSITIONANIMATION
    if(transitionProxy != nil)
    {
        [self forgetProxy:transitionProxy];
        RELEASE_TO_NIL(transitionProxy)
    }
#endif
    [super dealloc];
}

-(void)_destroy {
    [super _destroy];
}

-(void)_configure
{
    [self replaceValue:nil forKey:@"orientationModes" notification:NO];
    [super _configure];
}

-(NSString*)apiName
{
    return @"Ti.Window";
}

-(void)rootViewDidForceFrame:(NSNotification *)notification
{
    if (focussed && opened) {
        if ( (controller == nil) || ([controller navigationController] == nil) ) {
            return;
        }
        UINavigationController* nc = [controller navigationController];
        BOOL isHidden = [nc isNavigationBarHidden];
        [nc setNavigationBarHidden:!isHidden animated:NO];
        [nc setNavigationBarHidden:isHidden animated:NO];
        [[nc view] setNeedsLayout];
    }
}

-(TiUIView*)newView
{
	TiUIWindow * win = (TiUIWindow*)[super newView];
    win.frame =[TiUtils appFrame];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rootViewDidForceFrame:) name:kTiFrameAdjustNotification object:nil];
	return win;
}

-(void)refreshViewIfNeeded
{
	if (!readyToBeLayout) return;
    [super refreshViewIfNeeded];
}

-(BOOL)relayout
{
    if (!readyToBeLayout) {
        //in case where the window was actually added as a child we want to make sure we are good
        readyToBeLayout = YES;
    }
    [super relayout];
}

-(void)setSandboxBounds:(CGRect)rect
{
    if (!readyToBeLayout) {
        //in case where the window was actually added as a child we want to make sure we are good
        readyToBeLayout = YES;
    }
    [super setSandboxBounds:rect];
}

#pragma mark - Utility Methods
-(void)windowWillOpen
{
    if (!opened){
        opening = YES;
    }
    [super windowWillOpen];
//    [self viewWillAppear:false];
    if (tab == nil && (self.isManaged == NO) && controller == nil) {
        [[[[TiApp app] controller] topContainerController] willOpenWindow:self];
    }
}

-(void)windowDidOpen
{
    opening = NO;
    opened = YES;
//    if (!readyToBeLayout)
//    {
//        [self viewWillAppear:false];
//        [self viewDidAppear:false];
//    }
//    [self viewDidAppear:false];
    [self fireEvent:@"open" propagate:NO];
    if (focussed && [self handleFocusEvents]) {
        [self fireEvent:@"focus" propagate:NO];
    }
    [super windowDidOpen];
    [self forgetProxy:openAnimation];
    RELEASE_TO_NIL(openAnimation);
    if (tab == nil && (self.isManaged == NO) && controller == nil) {
        [[[[TiApp app] controller] topContainerController] didOpenWindow:self];
    }
}

-(void) windowWillClose
{
//    [self viewWillDisappear:false];
    if (tab == nil && (self.isManaged == NO) && controller == nil) {
        [[[[TiApp app] controller] topContainerController] willCloseWindow:self];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super windowWillClose];
}

-(void) windowDidClose
{
    opened = NO;
    closing = NO;
//    [self viewDidDisappear:false];
    [self fireEvent:@"close" propagate:NO];
    [self forgetProxy:closeAnimation];
    [[NSNotificationCenter defaultCenter] removeObserver:self]; //just to be sure
    RELEASE_TO_NIL(closeAnimation);
    if (tab == nil && (self.isManaged == NO) && controller == nil) {
        [[[[TiApp app] controller] topContainerController] didCloseWindow:self];
    }
    tab = nil;
    self.isManaged = NO;
    
    [super windowDidClose];
    [self forgetSelf];
}

-(void)attachViewToTopContainerController
{
    UIViewController<TiControllerContainment>* topContainerController = [[[TiApp app] controller] topContainerController];
    UIView *rootView = [topContainerController view];
    TiUIView* theView = [self view];
    [rootView addSubview:theView];
    [rootView bringSubviewToFront:theView];
    [[TiViewProxy class] reorderViewsInParent:rootView]; //make sure views are ordered along zindex
}

-(BOOL)argOrWindowPropertyExists:(NSString*)key args:(id)args
{
    id value = [self valueForUndefinedKey:key];
    if (!IS_NULL_OR_NIL(value)) {
        return YES;
    }
    if (([args count] > 0) && [[args objectAtIndex:0] isKindOfClass:[NSDictionary class]]) {
        value = [[args objectAtIndex:0] objectForKey:key];
        if (!IS_NULL_OR_NIL(value)) {
            return YES;
        }
    }
    return NO;
}

-(BOOL)argOrWindowProperty:(NSString*)key args:(id)args
{
    if ([TiUtils boolValue:[self valueForUndefinedKey:key]]) {
        return YES;
    }
    if (([args count] > 0) && [[args objectAtIndex:0] isKindOfClass:[NSDictionary class]]) {
        return [TiUtils boolValue:key properties:[args objectAtIndex:0] def:NO];
    }
    return NO;
}

-(BOOL)isRootViewLoaded
{
    return [[[TiApp app] controller] isViewLoaded];
}

-(BOOL)isRootViewAttached
{
    //When a modal window is up, just return yes
    if ([[[TiApp app] controller] presentedViewController] != nil) {
        return YES;
    }
    return ([[[[TiApp app] controller] view] superview]!=nil);
}

#pragma mark - TiWindowProtocol Base Methods
-(void)open:(id)args
{
    //If an error is up, Go away
    if ([[[[TiApp app] controller] topPresentedController] isKindOfClass:[TiErrorController class]]) {
        DebugLog(@"[ERROR] ErrorController is up. ABORTING open");
        return;
    }
    
    //I am already open or will be soon. Go Away
    if (opening || opened) {
        return;
    }
    
    //Lets keep ourselves safe
    [self rememberSelf];

    //Make sure our RootView Controller is attached
    if (![self isRootViewLoaded]) {
        DebugLog(@"[WARN] ROOT VIEW NOT LOADED. WAITING");
        [self performSelector:@selector(open:) withObject:args afterDelay:0.1];
        return;
    }
    if (![self isRootViewAttached]) {
        DebugLog(@"[WARN] ROOT VIEW NOT ATTACHED. WAITING");
        [self performSelector:@selector(open:) withObject:args afterDelay:0.1];
        return;
    }
    
    opening = YES;
    
    isModal = (tab == nil && !self.isManaged) ? [self argOrWindowProperty:@"modal" args:args] : NO;
    
    if ([self argOrWindowProperty:@"fullscreen" args:args]) {
        hidesStatusBar = YES;
    } else {
        if ([self argOrWindowPropertyExists:@"fullscreen" args:args]) {
            hidesStatusBar = NO;
        } else {
            hidesStatusBar = [[[TiApp app] controller] statusBarInitiallyHidden];
        }
    }

    
    if (!isModal && (tab==nil)) {
        openAnimation = [[TiAnimation animationFromArg:args context:[self pageContext] create:NO] retain];
        [self rememberProxy:openAnimation];
    }
    [self updateOrientationModes];
    
    //GO ahead and call open on the UI thread
    TiThreadPerformOnMainThread(^{
        [self openOnUIThread:args];
    }, YES);
    
}

-(void)updateOrientationModes
{
    //TODO Argument Processing
    id object = [self valueForUndefinedKey:@"orientationModes"];
    _supportedOrientations = [TiUtils TiOrientationFlagsFromObject:object];
}

-(void)setStatusBarStyle:(id)style
{
    int theStyle = [TiUtils intValue:style def:[[[TiApp app] controller] defaultStatusBarStyle]];
    switch (theStyle){
        case UIStatusBarStyleDefault:
            barStyle = UIStatusBarStyleDefault;
            break;
        case UIStatusBarStyleBlackOpaque:
        case UIStatusBarStyleBlackTranslucent: //This will also catch UIStatusBarStyleLightContent
            if ([TiUtils isIOS7OrGreater]) {
                barStyle = 1;//UIStatusBarStyleLightContent;
            } else {
                barStyle = theStyle;
            }
            break;
        default:
            barStyle = UIStatusBarStyleDefault;
    }
    [self setValue:NUMINT(barStyle) forUndefinedKey:@"statusBarStyle"];
    if(focussed) {
        TiThreadPerformOnMainThread(^{
            [(TiRootViewController*)[[TiApp app] controller] updateStatusBar];
        }, YES); 
    }
}

-(void)close:(id)args
{
    //I am not open. Go Away
    if (opening) {
        DebugLog(@"Window is opening. Ignoring this close call");
        return;
    }
    
    if (!opened) {
        DebugLog(@"Window is not open. Ignoring this close call");
        return;
    }
    
    if (closing) {
        DebugLog(@"Window is already closing. Ignoring this close call.");
        return;
    }
    
    if (tab != nil) {
        if ([args count] > 0) {
            args = [NSArray arrayWithObjects:self, [args objectAtIndex:0], nil];
        } else {
            args = [NSArray arrayWithObject:self];
        }
        [tab closeWindow:args];
        return;
    }
    
    closing = YES;
    
    //TODO Argument Processing
    closeAnimation = [[TiAnimation animationFromArg:args context:[self pageContext] create:NO] retain];
    [self rememberProxy:closeAnimation];

    //GO ahead and call close on UI thread
    TiThreadPerformOnMainThread(^{
        [self closeOnUIThread:args];
    }, YES);
    
}

-(BOOL)_handleOpen:(id)args
{
    TiRootViewController* theController = [[TiApp app] controller];
    if (isModal || (tab != nil) || self.isManaged) {
        [self forgetProxy:openAnimation];
        RELEASE_TO_NIL(openAnimation);
    }
    
    if ( (!self.isManaged) && (!isModal) && (openAnimation != nil) && ([theController topPresentedController] != [theController topContainerController]) ){
        DeveloperLog(@"[WARN] The top View controller is not a container controller. This window will open behind the presented controller without animations.")
        [self forgetProxy:openAnimation];
        RELEASE_TO_NIL(openAnimation);
    }
    
    return YES;
}

-(BOOL)_handleClose:(id)args
{
    TiRootViewController* theController = [[TiApp app] controller];
    if (isModal || (tab != nil) || self.isManaged) {
        [self forgetProxy:closeAnimation];
        RELEASE_TO_NIL(closeAnimation);
    }
    if ( (!self.isManaged) && (!isModal) && (closeAnimation != nil) && ([theController topPresentedController] != [theController topContainerController]) ){
        DeveloperLog(@"[WARN] The top View controller is not a container controller. This window will close behind the presented controller without animations.")
        [self forgetProxy:closeAnimation];
        RELEASE_TO_NIL(closeAnimation);
    }
    return YES;
}

-(BOOL)opening
{
    return opening;
}

-(BOOL)closing
{
    return closing;
}

-(void)setModal:(id)val
{
    [self replaceValue:val forKey:@"modal" notification:NO];
}

-(BOOL)isModal
{
    return isModal;
}

-(BOOL)hidesStatusBar
{
    return hidesStatusBar;
}

-(UIStatusBarStyle)preferredStatusBarStyle;
{
    return barStyle;
}

-(BOOL)handleFocusEvents
{
	return YES;
}

-(void)gainFocus
{
    if (focussed == NO) {
        focussed = YES;
        if ([self handleFocusEvents] && opened) {
            [self fireEvent:@"focus" propagate:NO];
        }
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
        [[self view] setAccessibilityElementsHidden:NO];
    }
    if ([TiUtils isIOS7OrGreater]) {
        TiThreadPerformOnMainThread(^{
            [self forceNavBarFrame];
        }, NO);
    }

}

-(void)resignFocus
{
    if (focussed == YES) {
        focussed = NO;
        if ([self handleFocusEvents]) {
            [self fireEvent:@"blur" propagate:NO];
        }
        [[self view] setAccessibilityElementsHidden:YES];
    }
}

-(TiProxy *)topWindow
{
    return self;
}

-(TiProxy *)parentForBubbling
{
    if (parent) return parent;
    else return tab;
}

#pragma mark - Private Methods
-(TiProxy*)tabGroup
{
    return [tab tabGroup];
}

-(NSNumber*)orientation
{
	return NUMINT([UIApplication sharedApplication].statusBarOrientation);
}

-(void)forceNavBarFrame
{
    if (!focussed) {
        return;
    }
    if ( (controller == nil) || ([controller navigationController] == nil) ) {
        return;
    }
    
    if (![[[TiApp app] controller] statusBarVisibilityChanged]) {
        return;
    }
    
    UINavigationController* nc = [controller navigationController];
    BOOL isHidden = [nc isNavigationBarHidden];
    [nc setNavigationBarHidden:!isHidden animated:NO];
    [nc setNavigationBarHidden:isHidden animated:NO];
    [[nc view] setNeedsLayout];
}


-(void)openOnUIThread:(NSArray*)args
{
    if ([self _handleOpen:args]) {
        [self parentWillShow];
        if (tab != nil) {
            if ([args count] > 0) {
                args = [NSArray arrayWithObjects:self, [args objectAtIndex:0], nil];
            } else {
                args = [NSArray arrayWithObject:self];
            }
            [tab openWindow:args];
        } else if (isModal) {
            UIViewController* theController = [self hostingController];
            [self windowWillOpen];
            NSDictionary *dict = [args count] > 0 ? [args objectAtIndex:0] : nil;
            int style = [TiUtils intValue:@"modalTransitionStyle" properties:dict def:-1];
            if (style != -1) {
                [theController setModalTransitionStyle:style];
            }
            style = [TiUtils intValue:@"modalStyle" properties:dict def:-1];
            if (style != -1) {
				// modal transition style page curl must be done only in fullscreen
				// so only allow if not page curl
				if ([theController modalTransitionStyle]!=UIModalTransitionStylePartialCurl)
				{
					[theController setModalPresentationStyle:style];
				}
            }
            BOOL animated = [TiUtils boolValue:@"animated" properties:dict def:YES];
            [[TiApp app] showModalController:theController animated:animated];
        } else {
            [self windowWillOpen];
            [self view];
            if ((self.isManaged == NO) && ((openAnimation == nil) || (![openAnimation isTransitionAnimation]))){
                [self attachViewToTopContainerController];
            }
            if (openAnimation != nil) {
                [self animate:openAnimation];
            } else {
                [self windowDidOpen];
            }
        }
    } else {
        DebugLog(@"[WARN] OPEN ABORTED. _handleOpen returned NO");
        opening = NO;
        opened = NO;
        [self forgetProxy:openAnimation];
        RELEASE_TO_NIL(openAnimation);
    }
}

-(void)closeOnUIThread:(NSArray *)args
{
    if ([self _handleClose:args]) {
        [self windowWillClose];
        if (isModal) {
            NSDictionary *dict = [args count] > 0 ? [args objectAtIndex:0] : nil;
            BOOL animated = [TiUtils boolValue:@"animated" properties:dict def:YES];
            [[TiApp app] hideModalController:controller animated:animated];
        } else {
            if (closeAnimation != nil) {
                [closeAnimation setDelegate:self];
                [self animate:closeAnimation];
            } else {
                [self windowDidClose];
            }
        }
        
    } else {
        DebugLog(@"[WARN] CLOSE ABORTED. _handleClose returned NO");
        closing = NO;
        RELEASE_TO_NIL(closeAnimation);
    }
}

#pragma mark - TiOrientationController
-(void)childOrientationControllerChangedFlags:(id<TiOrientationController>) orientationController;
{
    [parentController childOrientationControllerChangedFlags:self];
}

-(void)setParentOrientationController:(id <TiOrientationController>)newParent
{
    parentController = newParent;
}

-(id)parentOrientationController
{
	return parentController;
}

-(TiOrientationFlags) orientationFlags
{
    if ([self isModal]) {
        return (_supportedOrientations==TiOrientationNone) ? [[[TiApp app] controller] getDefaultOrientations] : _supportedOrientations;
    }
    return _supportedOrientations;
}

#pragma mark - Appearance and Rotation Callbacks. For subclasses to override.
//Containing controller will call these callbacks(appearance/rotation) on contained windows when it receives them.
-(void)viewWillAppear:(BOOL)animated
{
    readyToBeLayout = YES;
    [super viewWillAppear:animated];
}
-(void)viewWillDisappear:(BOOL)animated
{
    if (controller != nil) {
        [self resignFocus];
    }
    [super viewWillDisappear:animated];
}
-(void)viewDidAppear:(BOOL)animated
{
    if (isModal && opening) {
        [self windowDidOpen];
    }
    if (controller != nil && !self.isManaged) {
        [self gainFocus];
    }
}
-(void)viewDidDisappear:(BOOL)animated
{
    if (isModal && closing) {
        [self windowDidClose];
    }
}

-(void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [self refreshViewIfNeeded];
}

-(void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [self setFakeAnimationOfDuration:duration andCurve:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
}
-(void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [self removeFakeAnimation];
}

#pragma mark - TiAnimation Delegate Methods

-(HLSAnimation*)animationForAnimation:(TiAnimation*)animation
{
    if (animation.isTransitionAnimation && (animation == openAnimation || animation == closeAnimation)) {
        
        TiTransitionAnimation * hlsAnimation = [TiTransitionAnimation animation];
        UIView* hostingView = nil;
        if (animation == openAnimation) {
            hostingView = [[[[TiApp app] controller] topContainerController] view];
            hlsAnimation.openTransition = YES;
        } else {
            hostingView = [[self getOrCreateView] superview];
            hlsAnimation.closeTransition = YES;
        }
        hlsAnimation.animatedProxy = self;
        hlsAnimation.animationProxy = animation;
        hlsAnimation.transition = animation.transition;
        hlsAnimation.transitionViewProxy = self;
        TiTransitionAnimationStep* step = [TiTransitionAnimationStep animationStep];
        step.duration = [animation getAnimationDuration];
        [step addTransitionAnimation:hlsAnimation insideHolder:hostingView];
        return [HLSAnimation animationWithAnimationStep:step];
    }
    else {
        return [super animationForAnimation:animation];
    }
}

-(void)animationDidComplete:(TiAnimation *)sender
{
    [super animationDidComplete:sender];
    if (sender == openAnimation) {
        if (animatedOver != nil) {
            if ([animatedOver isKindOfClass:[TiUIView class]]) {
                TiViewProxy* theProxy = (TiViewProxy*)[(TiUIView*)animatedOver proxy];
                if ([theProxy viewAttached]) {
                    [[[self view] superview] insertSubview:animatedOver belowSubview:[self view]];
                    LayoutConstraint* layoutProps = [theProxy layoutProperties];
                    ApplyConstraintToViewWithBounds(layoutProps, &layoutProperties, (TiUIView*)animatedOver, [[animatedOver superview] bounds]);
                    [theProxy layoutChildren:NO];
                    RELEASE_TO_NIL(animatedOver);
                }
            } else {
                [[[self view] superview] insertSubview:animatedOver belowSubview:[self view]];
            }
        }
        [self windowDidOpen];
    } else if (sender == closeAnimation) {
        [self windowDidClose];
    }
}
#ifdef USE_TI_UIIOSTRANSITIONANIMATION
-(TiUIiOSTransitionAnimationProxy*)transitionAnimation
{
    return transitionProxy;
}

-(void)setTransitionAnimation:(id)args
{
    ENSURE_SINGLE_ARG_OR_NIL(args, TiUIiOSTransitionAnimationProxy)
    if(transitionProxy != nil) {
        [self forgetProxy:transitionProxy];
        RELEASE_TO_NIL(transitionProxy)
    }
    transitionProxy = [args retain];
    [self rememberProxy:transitionProxy];
}
#endif

@end
