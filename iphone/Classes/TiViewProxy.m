/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2014 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "TiViewProxy.h"
#import "LayoutConstraint.h"
#import "TiApp.h"
#import "TiBlob.h"
#import "TiLayoutQueue.h"
#import "TiAction.h"
#import "TiStylesheet.h"
#import "TiLocale.h"
#import "TiUIView.h"
#import "TiTransition.h"
#import "TiApp.h"
#import "TiViewAnimation+Friend.h"
#import "TiViewAnimationStep.h"
#import "TiTransitionAnimation+Friend.h"
#import "TiTransitionAnimationStep.h"

#import <QuartzCore/QuartzCore.h>
#import <libkern/OSAtomic.h>
#import <pthread.h>
#import "TiViewController.h"


@interface TiFakeAnimation : TiViewAnimationStep

@end

@implementation TiFakeAnimation

@end

@interface TiViewProxy()
{
    BOOL needsContentChange;
    BOOL allowContentChange;
	unsigned int animationDelayGuard;
    BOOL _transitioning;
    id _pendingTransition;
    int childrenCount;
}
@end

#define IGNORE_IF_NOT_OPENED if (!windowOpened||[self viewAttached]==NO) {dirtyflags=0;return;}

@implementation TiViewProxy

@synthesize eventOverrideDelegate = eventOverrideDelegate, controller = controller;

static NSArray* layoutProps = nil;
static NSSet* transferableProps = nil;

#pragma mark public API

@synthesize vzIndex, parentVisible;
-(void)setVzIndex:(int)newZindex
{
	if(newZindex == vzIndex)
	{
		return;
	}

	vzIndex = newZindex;
	[self replaceValue:NUMINT(vzIndex) forKey:@"vzIndex" notification:NO];
	[self willChangeZIndex];
}

@synthesize children;
-(NSArray*)children
{
    if (![NSThread isMainThread]) {
        __block NSArray* result = nil;
        TiThreadPerformOnMainThread(^{
            result = [[self children] retain];
        }, YES);
        return [result autorelease];
    }
    NSArray* copy = nil;
    
	pthread_rwlock_rdlock(&childrenLock);
	if (windowOpened==NO && children==nil && pendingAdds!=nil)
	{
		copy = [pendingAdds mutableCopy];
	}
    else {
        copy = [children mutableCopy];
    }
	pthread_rwlock_unlock(&childrenLock);
	return ((copy != nil) ? [copy autorelease] : [NSMutableArray array]);
}

-(NSString*)apiName
{
    return @"Ti.View";
}

-(void)runBlockOnMainThread:(void (^)(TiViewProxy* proxy))block onlyVisible:(BOOL)onlyVisible recursive:(BOOL)recursive
{
    if ([NSThread isMainThread])
	{
        [self runBlock:block onlyVisible:onlyVisible recursive:recursive];
    }
    else
    {
        TiThreadPerformOnMainThread(^{
            [self runBlock:block onlyVisible:onlyVisible recursive:recursive];
        }, NO);
    }
}

-(void)runBlock:(void (^)(TiViewProxy* proxy))block onlyVisible:(BOOL)onlyVisible recursive:(BOOL)recursive
{
    if (recursive)
    {
        pthread_rwlock_rdlock(&childrenLock);
        NSArray* subproxies = onlyVisible?[self visibleChildren]:[self children];
        for (TiViewProxy * thisChildProxy in subproxies)
        {
            block(thisChildProxy);
            [thisChildProxy runBlock:block onlyVisible:onlyVisible recursive:recursive];
        }
        pthread_rwlock_unlock(&childrenLock);
    }
//    block(self);
}

-(void)makeChildrenPerformSelector:(SEL)selector withObject:(id)object
{
    [[self children] makeObjectsPerformSelector:selector withObject:object];
}

-(void)makeVisibleChildrenPerformSelector:(SEL)selector withObject:(id)object
{
    [[self visibleChildren] makeObjectsPerformSelector:selector withObject:object];
}

-(NSArray*)visibleChildren
{
    NSArray* copy = nil;
    
	pthread_rwlock_rdlock(&childrenLock);
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"isHidden = FALSE"];
    if (windowOpened==NO && children==nil && pendingAdds!=nil)
	{
        
		copy = [pendingAdds filteredArrayUsingPredicate:pred];
	}
    else {
        copy = [children filteredArrayUsingPredicate:pred];
    }
	pthread_rwlock_unlock(&childrenLock);
	return ((copy != nil) ? copy : [NSMutableArray array]);
}

-(void)setVisible:(NSNumber *)newVisible
{
	[self setHidden:![TiUtils boolValue:newVisible def:YES] withArgs:nil];
	[self replaceValue:newVisible forKey:@"visible" notification:YES];
}

-(void)setTempProperty:(id)propVal forKey:(id)propName {
    if (layoutPropDictionary == nil) {
        layoutPropDictionary = [[NSMutableDictionary alloc] init];
    }
    
    if (propVal != nil && propName != nil) {
        [layoutPropDictionary setObject:propVal forKey:propName];
    }
}

-(void)setProxyObserver:(id)arg
{
    observer = arg;
}

-(void)processTempProperties:(NSDictionary*)arg
{
    //arg will be non nil when called from updateLayout
    if (arg != nil) {
        NSEnumerator *enumerator = [arg keyEnumerator];
        id key;
        while ((key = [enumerator nextObject])) {
            [self setTempProperty:[arg objectForKey:key] forKey:key];
        }
    }
    
    if (layoutPropDictionary != nil) {
        [self setValuesForKeysWithDictionary:layoutPropDictionary];
        RELEASE_TO_NIL(layoutPropDictionary);
    }
}

-(void)applyProperties:(id)args
{
    TiThreadPerformOnMainThread(^{
        [self configurationStart];
        [super applyProperties:args];
        [self configurationSet];
        [self refreshViewOrParent];
    }, YES);
}

-(void)startLayout:(id)arg
{
    DebugLog(@"startLayout() method is deprecated since 3.0.0 .");
    updateStarted = YES;
    allowLayoutUpdate = NO;
}
-(void)finishLayout:(id)arg
{
    DebugLog(@"finishLayout() method is deprecated since 3.0.0 .");
    updateStarted = NO;
    allowLayoutUpdate = YES;
    [self processTempProperties:nil];
    allowLayoutUpdate = NO;
}
-(void)updateLayout:(id)arg
{
    DebugLog(@"updateLayout() method is deprecated since 3.0.0, use applyProperties() instead.");
    id val = nil;
    if ([arg isKindOfClass:[NSArray class]]) {
        val = [arg objectAtIndex:0];
    }
    else
    {
        val = arg;
    }
    updateStarted = NO;
    allowLayoutUpdate = YES;
    ENSURE_TYPE_OR_NIL(val, NSDictionary);
    [self processTempProperties:val];
    allowLayoutUpdate = NO;
    
}

-(BOOL) belongsToContext:(id<TiEvaluator>) context
{
    id<TiEvaluator> myContext = ([self executionContext]==nil)?[self pageContext]:[self executionContext];
    return (context == myContext);
}

-(void)add:(id)arg
{
    [self addInternal:arg shouldRelayout:YES];
}

-(void)addInternal:(id)arg shouldRelayout:(BOOL)shouldRelayout
{
	// allow either an array of arrays or an array of single proxy
	if ([arg isKindOfClass:[NSArray class]])
	{
		for (id a in arg)
		{
			[self add:a];
		}
		return;
	}
    if ([arg isKindOfClass:[NSDictionary class]]) {
        id<TiEvaluator> context = self.executionContext;
        if (context == nil) {
            context = self.pageContext;
        }
        TiViewProxy *child = [[self class] unarchiveFromDictionary:arg rootProxy:self inContext:context];
        [context.krollContext invokeBlockOnThread:^{
            [self rememberProxy:child];
            [child forgetSelf];
        }];
        [self add:child];
        return;
    }
	
//    if ([arg conformsToProtocol:@protocol(TiWindowProtocol)]) {
//        DebugLog(@"Can not add a window as a child of a view. Returning");
//        return;
//    }
    
	if ([NSThread isMainThread])
	{
        if (readyToCreateView)
            [arg setReadyToCreateView:YES]; //tableview magic not to create view on proxy creation
		pthread_rwlock_wrlock(&childrenLock);
		if (children==nil)
		{
			children = [[NSMutableArray alloc] initWithObjects:arg,nil];
		}		
		else 
		{
			[children addObject:arg];
		}
        childrenCount = [children count];
		pthread_rwlock_unlock(&childrenLock);
		[arg setParent:self];
        
        if (!readyToCreateView || [arg isHidden]) return;
        [arg performBlockWithoutLayout:^{
            [arg getOrCreateView];
        }];
        if (!shouldRelayout) return;

        [self contentsWillChange];
        if(parentVisible && !hidden)
        {
            [arg parentWillShow];
        }
        
        //If layout is non absolute push this into the layout queue
        //else just layout the child with current bounds
        if (![self absoluteLayout]) {
            [self contentsWillChange];
        }
        else {
            [self layoutChild:arg optimize:NO withMeasuredBounds:[[self view] bounds]];
        }
		
	}
	else
	{
		[self rememberProxy:arg];
		if (windowOpened && shouldRelayout)
		{
			TiThreadPerformOnMainThread(^{[self add:arg];}, NO);
			return;
		}
        else {
            pthread_rwlock_wrlock(&childrenLock);
            if (children==nil)
            {
                children = [[NSMutableArray alloc] initWithObjects:arg,nil];
            }
            else
            {
                [children addObject:arg];
            }
            childrenCount = [children count];
            pthread_rwlock_unlock(&childrenLock);
        }
		[arg setParent:self];
	}
}

-(void)remove:(id)arg
{
	ENSURE_SINGLE_ARG(arg,TiViewProxy);
	ENSURE_UI_THREAD_1_ARG(arg);

	pthread_rwlock_wrlock(&childrenLock);
	if ([children containsObject:arg])
	{
		[children removeObject:arg];
	}
	else if ([pendingAdds containsObject:arg])
	{
		[pendingAdds removeObject:arg];
	}
	else
	{
		pthread_rwlock_unlock(&childrenLock);
		DebugLog(@"[WARN] Called remove for %@ on %@, but %@ isn't a child or has already been removed.",arg,self,arg);
		return;
	}

	[self contentsWillChange];
	if(parentVisible && !hidden)
	{
		[arg parentWillHide];
	}

    childrenCount = [children count];
	if ([children count]==0)
	{
		RELEASE_TO_NIL(children);
	}
	pthread_rwlock_unlock(&childrenLock);
		
	[arg setParent:nil];
    
    [(TiViewProxy *)arg detachView];
    BOOL layoutNeedsRearranging = ![self absoluteLayout];
    if (layoutNeedsRearranging)
    {
        [self layoutChildren:NO];
    }
//	
//	if (view!=nil)
//	{
//		TiUIView *childView = [(TiViewProxy *)arg view];
//		BOOL layoutNeedsRearranging = !TiLayoutRuleIsAbsolute(layoutProperties.layoutStyle);
//		if ([NSThread isMainThread])
//		{
//			[childView removeFromSuperview];
//			if (layoutNeedsRearranging)
//			{
//				[self layoutChildren:NO];
//			}
//		}
//		else
//		{
//			TiThreadPerformOnMainThread(^{
//				[childView removeFromSuperview];
//				if (layoutNeedsRearranging)
//				{
//					[self layoutChildren:NO];
//				}
//			}, NO);
//		}
//	}
	//Yes, we're being really lazy about letting this go. This is intentional.
	[self forgetProxy:arg];
}

-(void)removeFromParent:(id)arg
{
    if (parent)
        [parent remove:self];
}

-(void)removeAllChildren:(id)arg
{
	ENSURE_UI_THREAD_1_ARG(arg);
    
    
	if (children != nil) {
		pthread_rwlock_wrlock(&childrenLock);

		for (TiViewProxy* child in children)
		{
			if ([pendingAdds containsObject:child])
			{
				[pendingAdds removeObject:child];
			}

			[child setParent:nil];
			[self forgetProxy:child];

			if (view!=nil)
			{
				TiUIView *childView = [(TiViewProxy *)child view];
                [childView removeFromSuperview];
			}
			[child parentWillHide];
		}

		[children removeAllObjects];
        childrenCount = 0;
		RELEASE_TO_NIL(children);

		pthread_rwlock_unlock(&childrenLock);

		if (view!=nil)
		{
            if (![self absoluteLayout])
            {
                [self layoutChildren:NO];
            }
		}
	}
}

-(void)show:(id)arg
{
	TiThreadPerformOnMainThread(^{
        [self setHidden:NO withArgs:arg];
        [self replaceValue:NUMBOOL(YES) forKey:@"visible" notification:YES];
    }, NO);
}
 
-(void)hide:(id)arg
{
    TiThreadPerformOnMainThread(^{
        [self setHidden:YES withArgs:arg];
        [self replaceValue:NUMBOOL(NO) forKey:@"visible" notification:YES];
    }, NO);
}

#pragma Animations

-(id)animationDelegate
{
    if (parent)
        return [parent animationDelegate];
    return nil;
}

-(void)handlePendingAnimation
{
    if (![self viewInitialized] || !allowContentChange)return;
    [super handlePendingAnimation];
}

-(void)handlePendingAnimation:(TiAnimation*)pendingAnimation
{
    if ([self viewReady]==NO &&  ![pendingAnimation isTransitionAnimation])
	{
		DebugLog(@"[DEBUG] Ti.UI.View.animate() called before view %@ was ready: Will re-attempt", self);
		if (animationDelayGuard++ > 5)
		{
			DebugLog(@"[DEBUG] Animation guard triggered, exceeded timeout to perform animation.");
            [pendingAnimation simulateFinish:self];
            [self handlePendingAnimation];
            animationDelayGuard = 0;
			return;
		}
        dispatch_async(dispatch_get_main_queue(), ^{
            [self performSelector:@selector(handlePendingAnimation:) withObject:pendingAnimation afterDelay:0.01];
        });
		return;
	}
	animationDelayGuard = 0;
    [super handlePendingAnimation:pendingAnimation];
}

-(void)aboutToBeAnimated
{
    if ([view superview]==nil)
    {
        VerboseLog(@"Entering animation without a superview Parent is %@, props are %@",parent,dynprops);
        [self windowWillOpen]; // we need to manually attach the window if you're animating
        [parent childWillResize:self];
    }
    
}

-(HLSAnimation*)animationForAnimation:(TiAnimation*)animation
{
    TiHLSAnimationStep* step;
    if (animation.isTransitionAnimation) {
        TiTransitionAnimation * hlsAnimation = [TiTransitionAnimation animation];
        hlsAnimation.animatedProxy = self;
        hlsAnimation.animationProxy = animation;
        hlsAnimation.transition = animation.transition;
        hlsAnimation.transitionViewProxy = animation.view;
        step = [TiTransitionAnimationStep animationStep];
        step.duration = [animation getAnimationDuration];
        step.curve = [animation curve];
        [(TiTransitionAnimationStep*)step addTransitionAnimation:hlsAnimation insideHolder:[self getOrCreateView]];
    }
    else {
        TiViewAnimation * hlsAnimation = [TiViewAnimation animation];
        hlsAnimation.animatedProxy = self;
        hlsAnimation.tiViewProxy = self;
        hlsAnimation.animationProxy = animation;
        step = [TiViewAnimationStep animationStep];
        step.duration = [animation getAnimationDuration];
        step.curve = [animation curve];
       [(TiViewAnimationStep*)step addViewAnimation:hlsAnimation forView:self.view];
    }
    
    return [HLSAnimation animationWithAnimationStep:step];
}

-(void)playAnimation:(HLSAnimation*)animation withRepeatCount:(NSUInteger)repeatCount afterDelay:(double)delay
{
    TiThreadPerformOnMainThread(^{
        [self aboutToBeAnimated];
        [animation playWithRepeatCount:repeatCount afterDelay:delay];
	}, NO);
}

//override
-(void)animationDidComplete:(TiAnimation *)animation
{
	OSAtomicTestAndClearBarrier(TiRefreshViewEnqueued, &dirtyflags);
	[self willEnqueue];
    [super animationDidComplete:animation];
}

-(void)resetProxyPropertiesForAnimation:(TiAnimation*)animation
{
    TiThreadPerformOnMainThread(^{
        [super resetProxyPropertiesForAnimation:animation];
		[parent layoutChildren:NO];
    }, YES);
}

#define CHECK_LAYOUT_UPDATE(layoutName,value) \
if (ENFORCE_BATCH_UPDATE) { \
    if (updateStarted) { \
        [self setTempProperty:value forKey:@#layoutName]; \
        return; \
    } \
    else if(!allowLayoutUpdate){ \
        return; \
    } \
}

#define LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(methodName,layoutName,converter,postaction)	\
-(void)methodName:(id)value	\
{	\
    CHECK_LAYOUT_UPDATE(layoutName,value) \
    TiDimension result = converter(value);\
    if ( TiDimensionIsDip(result) || TiDimensionIsPercent(result) ) {\
        layoutProperties.layoutName = result;\
    }\
    else {\
        if (!TiDimensionIsUndefined(result)) {\
            DebugLog(@"[WARN] Invalid value %@ specified for property %@",[TiUtils stringValue:value],@#layoutName); \
        } \
        layoutProperties.layoutName = TiDimensionUndefined;\
    }\
    [self replaceValue:value forKey:@#layoutName notification:YES];	\
    postaction; \
}

#define LAYOUTPROPERTIES_SETTER(methodName,layoutName,converter,postaction)	\
-(void)methodName:(id)value	\
{	\
    CHECK_LAYOUT_UPDATE(layoutName,value) \
    layoutProperties.layoutName = converter(value);	\
    [self replaceValue:value forKey:@#layoutName notification:YES];	\
    postaction; \
}

#define LAYOUTFLAGS_SETTER(methodName,layoutName,flagName,postaction)	\
-(void)methodName:(id)value	\
{	\
	CHECK_LAYOUT_UPDATE(layoutName,value) \
	layoutProperties.layoutFlags.flagName = [TiUtils boolValue:value];	\
	[self replaceValue:value forKey:@#layoutName notification:NO];	\
	postaction; \
}

LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(setTop,top,TiDimensionFromObject,[self willChangePosition])
LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(setBottom,bottom,TiDimensionFromObject,[self willChangePosition])

LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(setLeft,left,TiDimensionFromObject,[self willChangePosition])
LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(setRight,right,TiDimensionFromObject,[self willChangePosition])

LAYOUTPROPERTIES_SETTER(setWidth,width,TiDimensionFromObject,[self willChangeSize])
LAYOUTPROPERTIES_SETTER(setHeight,height,TiDimensionFromObject,[self willChangeSize])

-(void)setFullscreen:(id)value
{
    CHECK_LAYOUT_UPDATE(layoutName,value)
    layoutProperties.fullscreen = [TiUtils boolValue:value def:NO];
    [self willChangeSize];
    [self willChangePosition];
}

-(id)getFullscreen
{
    return NUMBOOL(layoutProperties.fullscreen);
}

+(NSArray*)layoutProperties
{
    if (layoutProps == nil) {
        layoutProps = [[NSArray alloc] initWithObjects:@"left", @"right", @"top", @"bottom", @"width", @"height", @"fullscreen", @"minWidth", @"minHeight", @"maxWidth", @"maxHeight", nil];
    }
    return layoutProps;
}

+(NSSet*)transferableProperties
{
    if (transferableProps == nil) {
        transferableProps = [[NSSet alloc] initWithObjects:@"imageCap",@"visible", @"backgroundImage", @"backgroundGradient", @"backgroundColor", @"backgroundSelectedImage", @"backgroundSelectedGradient", @"backgroundSelectedColor", @"backgroundDisabledImage", @"backgroundDisabledGradient", @"backgroundDisabledColor", @"backgroundRepeat",@"focusable", @"touchEnabled", @"viewShadow", @"viewMask", @"accessibilityLabel", @"accessibilityValue", @"accessibilityHint", @"accessibilityHidden",
            @"opacity", @"borderWidth", @"borderColor", @"borderRadius", @"tileBackground",
            @"transform", @"center", @"anchorPoint", @"clipChildren", @"touchPassThrough", @"transform", nil];
    }
    return transferableProps;
}

-(NSArray *)keySequence
{
	static NSArray *keySequence = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		keySequence = [@[@"visible", @"clipChildren"] retain];
	});
	return keySequence;
}

// See below for how we handle setLayout
//LAYOUTPROPERTIES_SETTER(setLayout,layoutStyle,TiLayoutRuleFromObject,[self willChangeLayout])

LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(setMinWidth,minimumWidth,TiDimensionFromObject,[self willChangeSize])
LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(setMinHeight,minimumHeight,TiDimensionFromObject,[self willChangeSize])
LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(setMaxWidth,maximumWidth,TiDimensionFromObject,[self willChangeSize])
LAYOUTPROPERTIES_SETTER_IGNORES_AUTO(setMaxHeight,maximumHeight,TiDimensionFromObject,[self willChangeSize])

LAYOUTFLAGS_SETTER(setHorizontalWrap,horizontalWrap,horizontalWrap,[self willChangeLayout])

// Special handling to try and avoid Apple's detection of private API 'layout'
-(void)setValue:(id)value forUndefinedKey:(NSString *)key
{
    if ([key isEqualToString:[@"lay" stringByAppendingString:@"out"]]) {
        //CAN NOT USE THE MACRO 
        if (ENFORCE_BATCH_UPDATE) {
            if (updateStarted) {
                [self setTempProperty:value forKey:key]; \
                return;
            }
            else if(!allowLayoutUpdate){
                return;
            }
        }
        layoutProperties.layoutStyle = TiLayoutRuleFromObject(value);
        [self replaceValue:value forKey:[@"lay" stringByAppendingString:@"out"] notification:YES];
        
        [self willChangeLayout];
        return;
    }
    [super setValue:value forUndefinedKey:key];
}

-(TiRect*)size
{
	TiRect *rect = [[TiRect alloc] init];
    if ([self viewAttached]) {
        [self makeViewPerformSelector:@selector(fillBoundsToRect:) withObject:rect createIfNeeded:YES waitUntilDone:YES];
        id defaultUnit = [[TiApp tiAppProperties] objectForKey:@"ti.ui.defaultunit"];
        if ([defaultUnit isKindOfClass:[NSString class]]) {
            [rect convertToUnit:defaultUnit];
        }
    }
    else {
        [rect setRect:CGRectZero];
    }
    
    return [rect autorelease];
}

-(id)rect
{
    TiRect *rect = [[TiRect alloc] init];
	if ([self viewAttached]) {
        __block CGRect viewRect;
        __block CGPoint viewPosition;
        __block CGAffineTransform viewTransform;
        __block CGPoint viewAnchor;
        TiThreadPerformOnMainThread(^{
            TiUIView * ourView = [self view];
            viewRect = [ourView bounds];
            viewPosition = [ourView center];
            viewTransform = [ourView transform];
            viewAnchor = [[ourView layer] anchorPoint];
        }, YES);
        viewRect.origin = CGPointMake(-viewAnchor.x*viewRect.size.width, -viewAnchor.y*viewRect.size.height);
        viewRect = CGRectApplyAffineTransform(viewRect, viewTransform);
        viewRect.origin.x += viewPosition.x;
        viewRect.origin.y += viewPosition.y;
        [rect setRect:viewRect];
        
        id defaultUnit = [[TiApp tiAppProperties] objectForKey:@"ti.ui.defaultunit"];
        if ([defaultUnit isKindOfClass:[NSString class]]) {
            [rect convertToUnit:defaultUnit];
        }       
    }
    else {
        [rect setRect:CGRectZero];
    }
    NSDictionary* result = [rect toJSON];
    [rect release];
    return result;
}

-(id)absoluteRect
{
    TiRect *rect = [[TiRect alloc] init];
	if ([self viewAttached]) {
        __block CGRect viewRect;
        __block CGPoint viewPosition;
        __block CGAffineTransform viewTransform;
        __block CGPoint viewAnchor;
        TiThreadPerformOnMainThread(^{
            TiUIView * ourView = [self view];
            viewRect = [ourView bounds];
            viewPosition = [ourView center];
            viewTransform = [ourView transform];
            viewAnchor = [[ourView layer] anchorPoint];
            viewRect.origin = CGPointMake(-viewAnchor.x*viewRect.size.width, -viewAnchor.y*viewRect.size.height);
            viewRect = CGRectApplyAffineTransform(viewRect, viewTransform);
            viewRect.origin.x += viewPosition.x;
            viewRect.origin.y += viewPosition.y;
            viewRect.origin = [ourView convertPoint:CGPointZero toView:nil];
            if (![[UIApplication sharedApplication] isStatusBarHidden])
            {
                CGRect statusFrame = [[UIApplication sharedApplication] statusBarFrame];
                viewRect.origin.y -= statusFrame.size.height;
            }
            
        }, YES);
        [rect setRect:viewRect];
        
        id defaultUnit = [[TiApp tiAppProperties] objectForKey:@"ti.ui.defaultunit"];
        if ([defaultUnit isKindOfClass:[NSString class]]) {
            [rect convertToUnit:defaultUnit];
        }
    }
    else {
        [rect setRect:CGRectZero];
    }
    NSDictionary* result = [rect toJSON];
    [rect release];
    return result;
}

-(id)zIndex
{
    return [self valueForUndefinedKey:@"zindex_"];
}

-(void)setZIndex:(id)value
{
    CHECK_LAYOUT_UPDATE(zIndex, value);
    
    if ([value respondsToSelector:@selector(intValue)]) {
        [self setVzIndex:[TiUtils intValue:value]];
        [self replaceValue:value forKey:@"zindex_" notification:NO];
    }
}

-(NSMutableDictionary*)center
{
    NSMutableDictionary* result = [[[NSMutableDictionary alloc] init] autorelease];
    id xVal = [self valueForUndefinedKey:@"centerX_"];
    if (xVal != nil) {
        [result setObject:xVal forKey:@"x"];
    }
    id yVal = [self valueForUndefinedKey:@"centerY_"];
    if (yVal != nil) {
        [result setObject:yVal forKey:@"y"];
    }
    
    if ([[result allKeys] count] > 0) {
        return result;
    }
    return nil;
}

-(void)setCenter:(id)value
{
    CHECK_LAYOUT_UPDATE(center, value);

    
	if ([value isKindOfClass:[NSDictionary class]])
	{
        TiDimension result;
        id obj = [value objectForKey:@"x"];
        if (obj != nil) {
            [self replaceValue:obj forKey:@"centerX_" notification:NO];
            result = TiDimensionFromObject(obj);
            if ( TiDimensionIsDip(result) || TiDimensionIsPercent(result) ) {
                layoutProperties.centerX = result;
            }
            else {
                layoutProperties.centerX = TiDimensionUndefined;
            }
        }
        obj = [value objectForKey:@"y"];
        if (obj != nil) {
            [self replaceValue:obj forKey:@"centerY_" notification:NO];
            result = TiDimensionFromObject(obj);
            if ( TiDimensionIsDip(result) || TiDimensionIsPercent(result) ) {
                layoutProperties.centerY = result;
            }
            else {
                layoutProperties.centerY = TiDimensionUndefined;
            }
        }
        
        

	} else if ([value isKindOfClass:[TiPoint class]]) {
        CGPoint p = [value point];
		layoutProperties.centerX = TiDimensionDip(p.x);
		layoutProperties.centerY = TiDimensionDip(p.y);
    } else {
		layoutProperties.centerX = TiDimensionUndefined;
		layoutProperties.centerY = TiDimensionUndefined;
	}

	[self willChangePosition];
}

-(id)animatedCenter
{
	if (![self viewAttached])
	{
		return nil;
	}
	__block CGPoint result;
	TiThreadPerformOnMainThread(^{
		UIView * ourView = view;
		CALayer * ourLayer = [ourView layer];
		CALayer * animatedLayer = [ourLayer presentationLayer];
	
		if (animatedLayer !=nil) {
			result = [animatedLayer position];
		}
		else {
			result = [ourLayer position];
		}
	}, YES);
	//TODO: Should this be a TiPoint? If so, the accessor fetcher might try to
	//hold onto the point, which is undesired.
	return [NSDictionary dictionaryWithObjectsAndKeys:NUMFLOAT(result.x),@"x",NUMFLOAT(result.y),@"y", nil];
}

-(void)setBackgroundGradient:(id)arg
{
	TiGradient * newGradient = [TiGradient gradientFromObject:arg proxy:self];
	[self replaceValue:newGradient forKey:@"backgroundGradient" notification:YES];
}

-(UIImage*)toImageWithScale:(CGFloat)scale
{
    TiUIView *myview = [self getOrCreateView];
    [self windowWillOpen];
    CGSize size = myview.bounds.size;
   
    if (CGSizeEqualToSize(size, CGSizeZero) || size.width==0 || size.height==0)
    {
        CGSize size = [self autoSizeForSize:CGSizeMake(1000,1000)];
        if (size.width==0 || size.height == 0)
        {
            size = [UIScreen mainScreen].bounds.size;
        }
        CGRect rect = CGRectMake(0, 0, size.width, size.height);
        [TiUtils setView:myview positionRect:rect];
    }
    if ([TiUtils isRetinaDisplay])
    {
        scale*=2;
        
    }
    UIGraphicsBeginImageContextWithOptions(size, [myview.layer isOpaque], scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    float oldOpacity = myview.alpha;
    myview.alpha = 1;
    [myview.layer renderInContext:context];
    myview.alpha = oldOpacity;
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

-(TiBlob*)toImage:(id)args
{
    KrollCallback *callback = nil;
    float scale = 1.0f;
    
    id obj = nil;
    if( [args count] > 0) {
        obj = [args objectAtIndex:0];
        
        if (obj == [NSNull null]) {
            obj = nil;
        }
        
        if( [args count] > 1) {
            scale = [TiUtils floatValue:[args objectAtIndex:1] def:1.0f];
        }
    }
	ENSURE_SINGLE_ARG_OR_NIL(obj,KrollCallback);
    callback = (KrollCallback*)obj;
	TiBlob *blob = [[[TiBlob alloc] init] autorelease];
	// we spin on the UI thread and have him convert and then add back to the blob
	// if you pass a callback function, we'll run the render asynchronously, if you
	// don't, we'll do it synchronously
	TiThreadPerformOnMainThread(^{
		UIImage *image = [self toImageWithScale:scale];
		[blob setImage:image];
        [blob setMimeType:@"image/png" type:TiBlobTypeImage];
		if (callback != nil)
		{
            NSDictionary *event = [NSDictionary dictionaryWithObject:blob forKey:@"image"];
            [self _fireEventToListener:@"toimage" withObject:event listener:callback thisObject:nil];
		}
	}, (callback==nil));
	
	return blob;
}

-(TiPoint*)convertPointToView:(id)args
{
    id arg1 = nil;
    TiViewProxy* arg2 = nil;
    ENSURE_ARG_AT_INDEX(arg1, args, 0, NSObject);
    ENSURE_ARG_AT_INDEX(arg2, args, 1, TiViewProxy);
    BOOL validPoint;
    CGPoint oldPoint = [TiUtils pointValue:arg1 valid:&validPoint];
    if (!validPoint) {
        [self throwException:TiExceptionInvalidType subreason:@"Parameter is not convertable to a TiPoint" location:CODELOCATION];
    }
    
    __block BOOL validView = NO;
    __block CGPoint p;
    dispatch_sync(dispatch_get_main_queue(), ^{
        if ([self viewAttached] && self.view.window && [arg2 viewAttached] && arg2.view.window) {
            validView = YES;
            p = [self.view convertPoint:oldPoint toView:arg2.view];
        }
    });
    if (!validView) {
        return (TiPoint*)[NSNull null];
    }
    return [[[TiPoint alloc] initWithPoint:p] autorelease];
}

#pragma mark nonpublic accessors not related to Housecleaning

@synthesize parent, barButtonItem;

-(void)setParent:(TiViewProxy*)parent_ checkForOpen:(BOOL)check
{
	parent = parent_;
	
	if (check && parent_!=nil && [parent windowHasOpened])
	{
		[self windowWillOpen];
	}
}

-(void)setParent:(TiViewProxy*)parent_
{
	parent = parent_;
	
	if (parent_!=nil && [parent windowHasOpened])
	{
		[self windowWillOpen];
	}
}

-(LayoutConstraint *)layoutProperties
{
	return &layoutProperties;
}

@synthesize sandboxBounds = sandboxBounds;

-(void)setSandboxBounds:(CGRect)rect
{
    if (!CGRectEqualToRect(rect, sandboxBounds))
    {
        sandboxBounds = rect;
//        [self dirtyItAll];
    }
}

-(void)setHidden:(BOOL)newHidden withArgs:(id)args
{
	hidden = newHidden;
}

-(BOOL)isHidden
{
    return hidden;
}

//-(CGSize)contentSizeForSize:(CGSize)size
//{
//    return CGSizeZero;
//}

-(CGSize)verifySize:(CGSize)size
{
    CGSize result = size;
    if([self respondsToSelector:@selector(verifyWidth:)])
	{
		result.width = [self verifyWidth:result.width];
	}
    if([self respondsToSelector:@selector(verifyHeight:)])
	{
		result.height = [self verifyHeight:result.height];
	}

    return result;
}

-(CGSize)autoSizeForSize:(CGSize)size
{
    CGSize contentSize = CGSizeMake(-1, -1);
    if ([self respondsToSelector:@selector(contentSizeForSize:)]) {
        contentSize = [self contentSizeForSize:size];
    }
    BOOL isAbsolute = [self absoluteLayout];
    CGSize result = CGSizeZero;
    
    CGRect bounds = CGRectZero;
    if (!isAbsolute) {
        bounds.size.width = size.width;
        bounds.size.height = size.height;
        verticalLayoutBoundary = 0;
        horizontalLayoutBoundary = 0;
        horizontalLayoutRowHeight = 0;
    }
	CGRect sandBox = CGRectZero;
    CGSize thisSize = CGSizeZero;
    
    if (childrenCount > 0)
    {
        pthread_rwlock_rdlock(&childrenLock);
        NSArray* childArray = [self visibleChildren];
        pthread_rwlock_unlock(&childrenLock);
        if (isAbsolute)
        {
            for (TiViewProxy* thisChildProxy in childArray)
            {
                thisSize = [thisChildProxy minimumParentSizeForSize:size];
                if(result.width<thisSize.width)
                {
                    result.width = thisSize.width;
                }
                if(result.height<thisSize.height)
                {
                    result.height = thisSize.height;
                }
            }
        }
        else {
            BOOL horizontal =  TiLayoutRuleIsHorizontal(layoutProperties.layoutStyle);
            BOOL vertical =  TiLayoutRuleIsVertical(layoutProperties.layoutStyle);
            BOOL horizontalNoWrap = horizontal && !TiLayoutFlagsHasHorizontalWrap(&layoutProperties);
            BOOL horizontalWrap = horizontal && TiLayoutFlagsHasHorizontalWrap(&layoutProperties);
            
            NSMutableArray * widthFillChildren = horizontal?[NSMutableArray array]:nil;
            NSMutableArray * heightFillChildren = (vertical || horizontalWrap)?[NSMutableArray array]:nil;
            CGFloat widthNonFill = 0;
            CGFloat heightNonFill = 0;
            
            //First measure the sandbox bounds
            for (TiViewProxy* thisChildProxy in childArray)
            {
                BOOL horizontalFill = [thisChildProxy wantsToFillHorizontalLayout];
                BOOL verticalFill = [thisChildProxy wantsToFillVerticalLayout];
                if (!horizontalWrap)
                {
                    if (widthFillChildren && horizontalFill)
                    {
                        [widthFillChildren addObject:thisChildProxy];
                        continue;
                    }
                    else if (heightFillChildren && verticalFill)
                    {
                        [heightFillChildren addObject:thisChildProxy];
                        continue;
                    }
                }
                sandBox = [self computeChildSandbox:thisChildProxy withBounds:bounds];
                thisSize = CGSizeMake(sandBox.origin.x + sandBox.size.width, sandBox.origin.y + sandBox.size.height);
                if(result.width<thisSize.width)
                {
                    result.width = thisSize.width;
                }
                if(result.height<thisSize.height)
                {
                    result.height = thisSize.height;
                }
            }
            
            int nbWidthAutoFill = [widthFillChildren count];
            if (nbWidthAutoFill > 0) {
                CGFloat usableWidth = floorf((size.width - result.width) / nbWidthAutoFill);
                CGRect usableRect = CGRectMake(0,0,usableWidth, size.height);
                for (TiViewProxy* thisChildProxy in widthFillChildren) {
                    sandBox = [self computeChildSandbox:thisChildProxy withBounds:usableRect];
                    thisSize = CGSizeMake(sandBox.origin.x + sandBox.size.width, sandBox.origin.y + sandBox.size.height);
                    if(result.width<thisSize.width)
                    {
                        result.width = thisSize.width;
                    }
                    if(result.height<thisSize.height)
                    {
                        result.height = thisSize.height;
                    }
                }
            }
            
            int nbHeightAutoFill = [heightFillChildren count];
            if (nbHeightAutoFill > 0) {
                CGFloat usableHeight = floorf((size.height - result.height) / nbHeightAutoFill);
                CGRect usableRect = CGRectMake(0,0,size.width, usableHeight);
                for (TiViewProxy* thisChildProxy in heightFillChildren) {
                    sandBox = [self computeChildSandbox:thisChildProxy withBounds:usableRect];
                    thisSize = CGSizeMake(sandBox.origin.x + sandBox.size.width, sandBox.origin.y + sandBox.size.height);
                    if(result.width<thisSize.width)
                    {
                        result.width = thisSize.width;
                    }
                    if(result.height<thisSize.height)
                    {
                        result.height = thisSize.height;
                    }
                }
            }
        }
    }
	
    if (result.width < contentSize.width) {
        result.width = contentSize.width;
    }
    if (result.height < contentSize.height) {
        result.height = contentSize.height;
    }
    result = minmaxSize(&layoutProperties, result, size);

	return [self verifySize:result];
}

-(CGSize)sizeForAutoSize:(CGSize)size
{
    if (layoutProperties.fullscreen == YES) return size;
    
    CGFloat suggestedWidth = size.width;
    BOOL followsFillHBehavior = TiDimensionIsAutoFill([self defaultAutoWidthBehavior:nil]);
    CGFloat suggestedHeight = size.height;
    BOOL followsFillWBehavior = TiDimensionIsAutoFill([self defaultAutoHeightBehavior:nil]);
    
    CGFloat offset = TiDimensionCalculateValue(layoutProperties.left, size.width)
    + TiDimensionCalculateValue(layoutProperties.right, size.width);

    CGFloat offset2 = TiDimensionCalculateValue(layoutProperties.top, suggestedHeight)
    + TiDimensionCalculateValue(layoutProperties.bottom, suggestedHeight);
    
    CGSize result = CGSizeZero;
    
    if (TiDimensionIsDip(layoutProperties.width) || TiDimensionIsPercent(layoutProperties.width))
    {
        result.width =  TiDimensionCalculateValue(layoutProperties.width, suggestedWidth);
    }
    else if (TiDimensionIsAutoFill(layoutProperties.width) || (TiDimensionIsAuto(layoutProperties.width) && followsFillWBehavior) )
    {
        result.width = size.width;
    }
    else if (TiDimensionIsUndefined(layoutProperties.width))
    {
        if (!TiDimensionIsUndefined(layoutProperties.left) && !TiDimensionIsUndefined(layoutProperties.centerX) ) {
            result.width = 2 * ( TiDimensionCalculateValue(layoutProperties.centerX, suggestedWidth) - TiDimensionCalculateValue(layoutProperties.left, suggestedWidth) );
        }
        else if (!TiDimensionIsUndefined(layoutProperties.left) && !TiDimensionIsUndefined(layoutProperties.right) ) {
            result.width = TiDimensionCalculateMargins(layoutProperties.left, layoutProperties.right, suggestedWidth);
        }
        else if (!TiDimensionIsUndefined(layoutProperties.centerX) && !TiDimensionIsUndefined(layoutProperties.right) ) {
            result.width = 2 * ( size.width - TiDimensionCalculateValue(layoutProperties.right, suggestedWidth) - TiDimensionCalculateValue(layoutProperties.centerX, suggestedWidth));
        }
        else {
            result.width = size.width;
        }
    }
    else
    {
        result.width = size.width;
    }
    
    if (TiDimensionIsDip(layoutProperties.height) || TiDimensionIsPercent(layoutProperties.height))        {
        result.height = TiDimensionCalculateValue(layoutProperties.height, suggestedHeight);
    }
    else if (TiDimensionIsAutoFill(layoutProperties.height) || (TiDimensionIsAuto(layoutProperties.height) && followsFillHBehavior) )
    {
        result.height = size.height;
    }
    else if (TiDimensionIsUndefined(layoutProperties.height))
    {
        if (!TiDimensionIsUndefined(layoutProperties.top) && !TiDimensionIsUndefined(layoutProperties.centerY) ) {
            result.height = 2 * ( TiDimensionCalculateValue(layoutProperties.centerY, suggestedHeight) - TiDimensionCalculateValue(layoutProperties.top, suggestedHeight) );
        }
        else if (!TiDimensionIsUndefined(layoutProperties.top) && !TiDimensionIsUndefined(layoutProperties.bottom) ) {
            result.height = TiDimensionCalculateMargins(layoutProperties.top, layoutProperties.bottom, suggestedHeight);
        }
        else if (!TiDimensionIsUndefined(layoutProperties.centerY) && !TiDimensionIsUndefined(layoutProperties.bottom) ) {
            result.height = 2 * ( suggestedHeight - TiDimensionCalculateValue(layoutProperties.bottom, suggestedHeight) - TiDimensionCalculateValue(layoutProperties.centerY, suggestedHeight));
        }
        else {
            result.height = size.height;
        }
    }
    result = minmaxSize(&layoutProperties, result, size);
    return result;
}

-(CGSize)minimumParentSizeForSize:(CGSize)size
{
    if (layoutProperties.fullscreen == YES) return size;
    
    CGSize suggestedSize = size;
    BOOL followsFillWidthBehavior = TiDimensionIsAutoFill([self defaultAutoWidthBehavior:nil]);
    BOOL followsFillHeightBehavior = TiDimensionIsAutoFill([self defaultAutoHeightBehavior:nil]);
    BOOL recheckForFillW = NO, recheckForFillH = NO;
    
    BOOL autoComputed = NO;
    CGSize autoSize = [self sizeForAutoSize:size];
    //    //Ensure that autoHeightForSize is called with the lowest limiting bound
    //    CGFloat desiredWidth = MIN([self minimumParentWidthForSize:size],size.width);
    
    CGFloat offsetx = TiDimensionCalculateValue(layoutProperties.left, suggestedSize.width)
    + TiDimensionCalculateValue(layoutProperties.right, suggestedSize.width);
    
    CGFloat offsety = TiDimensionCalculateValue(layoutProperties.top, suggestedSize.height)
    + TiDimensionCalculateValue(layoutProperties.bottom, suggestedSize.height);
    
    CGSize result = CGSizeMake(offsetx, offsety);

	if (TiDimensionIsDip(layoutProperties.width) || TiDimensionIsPercent(layoutProperties.width))
	{
		result.width += TiDimensionCalculateValue(layoutProperties.width, suggestedSize.width);
	}
	else if (TiDimensionIsAutoFill(layoutProperties.width) || (TiDimensionIsAuto(layoutProperties.width) && followsFillWidthBehavior) )
	{
		result.width = suggestedSize.width;
	}
    else if (followsFillWidthBehavior && TiDimensionIsUndefined(layoutProperties.width))
    {
        if (!TiDimensionIsUndefined(layoutProperties.left) && !TiDimensionIsUndefined(layoutProperties.centerX) ) {
            result.width += 2 * ( TiDimensionCalculateValue(layoutProperties.centerX, suggestedSize.width) - TiDimensionCalculateValue(layoutProperties.left, suggestedSize.width) );
        }
        else if (!TiDimensionIsUndefined(layoutProperties.left) && !TiDimensionIsUndefined(layoutProperties.right) ) {
            result.width += TiDimensionCalculateMargins(layoutProperties.left, layoutProperties.right, suggestedSize.width);
        }
        else if (!TiDimensionIsUndefined(layoutProperties.centerX) && !TiDimensionIsUndefined(layoutProperties.right) ) {
            result.width += 2 * ( size.width - TiDimensionCalculateValue(layoutProperties.right, suggestedSize.width) - TiDimensionCalculateValue(layoutProperties.centerX, suggestedSize.width));
        }
        else {
            recheckForFillW = followsFillWidthBehavior;
            autoComputed = YES;
            autoSize = [self autoSizeForSize:CGSizeMake(autoSize.width - offsetx, autoSize.height - offsety)];
            result.width += autoSize.width;
        }
    }
	else
	{
		autoComputed = YES;
        autoSize = [self autoSizeForSize:CGSizeMake(autoSize.width - offsetx, autoSize.height - offsety)];
        result.width += autoSize.width;
	}
    if (recheckForFillW && (result.width < suggestedSize.width) ) {
        result.width = suggestedSize.width;
    }
    
    
    if (TiDimensionIsDip(layoutProperties.height) || TiDimensionIsPercent(layoutProperties.height))	{
		result.height += TiDimensionCalculateValue(layoutProperties.height, suggestedSize.height);
	}
    else if (TiDimensionIsAutoFill(layoutProperties.height) || (TiDimensionIsAuto(layoutProperties.height) && followsFillHeightBehavior) )
	{
		recheckForFillH = YES;
        if (autoComputed == NO) {
            autoComputed = YES;
            autoSize = [self autoSizeForSize:CGSizeMake(autoSize.width - offsetx, autoSize.height - offsety)];
        }
		result.height += autoSize.height;
	}
    else if (followsFillHeightBehavior && TiDimensionIsUndefined(layoutProperties.height))
    {
        if (!TiDimensionIsUndefined(layoutProperties.top) && !TiDimensionIsUndefined(layoutProperties.centerY) ) {
            result.height += 2 * ( TiDimensionCalculateValue(layoutProperties.centerY, suggestedSize.height) - TiDimensionCalculateValue(layoutProperties.top, suggestedSize.height) );
        }
        else if (!TiDimensionIsUndefined(layoutProperties.top) && !TiDimensionIsUndefined(layoutProperties.bottom) ) {
            result.height += TiDimensionCalculateMargins(layoutProperties.top, layoutProperties.bottom, suggestedSize.height);
        }
        else if (!TiDimensionIsUndefined(layoutProperties.centerY) && !TiDimensionIsUndefined(layoutProperties.bottom) ) {
            result.height += 2 * ( suggestedSize.height - TiDimensionCalculateValue(layoutProperties.bottom, suggestedSize.height) - TiDimensionCalculateValue(layoutProperties.centerY, suggestedSize.height));
        }
        else {
            recheckForFillH = followsFillHeightBehavior;
            if (autoComputed == NO) {
                autoComputed = YES;
                autoSize = [self autoSizeForSize:CGSizeMake(autoSize.width - offsetx, autoSize.height - offsety)];
            }
            result.height += autoSize.height;
        }
    }
	else
	{
		if (autoComputed == NO) {
            autoComputed = YES;
            autoSize = [self autoSizeForSize:CGSizeMake(autoSize.width - offsetx, autoSize.height - offsety)];
        }
		result.height += autoSize.height;
	}
    if (recheckForFillH && (result.height < suggestedSize.height) ) {
        result.height = suggestedSize.height;
    }
    result = minmaxSize(&layoutProperties, result, size);
    
	return result;
}


-(UIBarButtonItem*)barButtonItem
{
	if (barButtonItem == nil)
	{
		isUsingBarButtonItem = YES;
		barButtonItem = [[UIBarButtonItem alloc] initWithCustomView:[self barButtonViewForSize:CGSizeZero]];
	}
	return barButtonItem;
}

- (TiUIView *)barButtonViewForSize:(CGSize)bounds
{
	TiUIView * barButtonView = [self getOrCreateView];
	//TODO: This logic should have a good place in case that refreshLayout is used.
	LayoutConstraint barButtonLayout = layoutProperties;
	if (TiDimensionIsUndefined(barButtonLayout.width))
	{
		barButtonLayout.width = TiDimensionAutoSize;
        
	}
	if (TiDimensionIsUndefined(barButtonLayout.height))
	{
		barButtonLayout.height = TiDimensionAutoSize;
	}
    if ( (bounds.width == 0 && !TiDimensionIsDip(barButtonLayout.width)) ||
        (bounds.height == 0 && !TiDimensionIsDip(barButtonLayout.height) ) ) {
        bounds = [self autoSizeForSize:CGSizeMake(1000, 1000)];
        barButtonLayout.width = TiDimensionDip(bounds.width);
    }
	CGRect barBounds;
	barBounds.origin = CGPointZero;
	barBounds.size = SizeConstraintViewWithSizeAddingResizing(&barButtonLayout, self, bounds, NULL);
	
	[TiUtils setView:barButtonView positionRect:barBounds];
	[barButtonView setAutoresizingMask:UIViewAutoresizingNone];
	
    //Ensure all the child views are laid out as well
    [self windowWillOpen];
    [self setParentVisible:YES];
    [self layoutChildren:NO];
    if (!isUsingBarButtonItem) {
        [self refreshSize];
        [self refreshPosition];
    }
	return barButtonView;
}

#pragma mark Recognizers

//supposed to be called on init
-(void)setDefaultReadyToCreateView:(BOOL)ready
{
    defaultReadyToCreateView = readyToCreateView = ready;
}

-(void)setReadyToCreateView:(BOOL)ready
{
    [self setReadyToCreateView:YES recursive:YES];
}

-(void)setReadyToCreateView:(BOOL)ready recursive:(BOOL)recursive
{
    readyToCreateView = ready;
    if (!recursive) return;
    
    pthread_rwlock_rdlock(&childrenLock);
	if (children != nil) {
		for (TiViewProxy* child in children) {
			[child setReadyToCreateView:ready];
		}
	}
	pthread_rwlock_unlock(&childrenLock);
}

-(TiUIView*)getOrCreateView
{
    readyToCreateView = YES;
    return [self view];
}

-(TiUIView*) getAndPrepareViewForOpening:(CGRect)bounds
{
    if([self viewAttached]) return view;
    [self setSandboxBounds:bounds];
    [self parentWillShow];
    [self windowWillOpen];
    [self windowDidOpen];
    TiUIView* tiview = [self getOrCreateView];
    return tiview;
}

-(void)determineSandboxBoundsForce
{
    if(!CGRectIsEmpty(sandboxBounds)) return;
    if(!CGRectIsEmpty(view.bounds)){
        [self setSandboxBounds:view.bounds];
    }
    else if (!CGRectIsEmpty(sizeCache)) {
        [self setSandboxBounds:sizeCache];
    }
    else if (parent != nil) {
        CGRect bounds = [[parent view] bounds];
        if (!CGRectIsEmpty(bounds)){
            [self setSandboxBounds:bounds];
        }
        else [self setSandboxBounds:parent.sandboxBounds];
    }
}

-(TiUIView*)view
{
	if (view == nil && readyToCreateView)
	{
		WARN_IF_BACKGROUND_THREAD_OBJ
#ifdef VERBOSE
		if(![NSThread isMainThread])
		{
			NSLog(@"[WARN] Break here");
		}
#endif		
		// on open we need to create a new view
		[self viewWillAttach];
		view = [self newView];
		view.proxy = self;
		view.layer.transform = CATransform3DIdentity;
		view.transform = CGAffineTransformIdentity;
        view.hidden = hidden;

		[view initializeState];

        [self configurationStart];
		// fire property changes for all properties to our delegate
		[self firePropertyChanges];

		[self configurationSet];

		pthread_rwlock_rdlock(&childrenLock);
		NSArray * childrenArray = [[self children] retain];
		pthread_rwlock_unlock(&childrenLock);
        
		for (id child in childrenArray)
		{
			TiUIView *childView = [(TiViewProxy*)child getOrCreateView];
			[self insertSubview:childView forProxy:child];
		}
		[childrenArray release];
		[self viewDidAttach];

		viewInitialized = YES;
		// If parent has a non absolute layout signal the parent that
		//contents will change else just lay ourselves out
//		if (parent != nil && ![parent absoluteLayout]) {
//			[parent contentsWillChange];
//		}
//		else {
			if(CGRectIsEmpty(sandboxBounds) && !CGRectIsEmpty(view.bounds)){
                [self setSandboxBounds:view.bounds];
			}
//            [self dirtyItAll];
//            [self refreshViewIfNeeded];
//		}
        if (!CGRectIsEmpty(sandboxBounds))
        {
            [self refreshView];
            [self handlePendingAnimation];
        }
	}

	CGRect bounds = [view bounds];
	if (!CGPointEqualToPoint(bounds.origin, CGPointZero))
	{
		[view setBounds:CGRectMake(0, 0, bounds.size.width, bounds.size.height)];
	}
	
	return view;
}

- (void)prepareForReuse
{
    pthread_rwlock_rdlock(&childrenLock);
    for (TiViewProxy* child in [self children]) {
        [child prepareForReuse];
    }
    pthread_rwlock_unlock(&childrenLock);
}

//CAUTION: TO BE USED ONLY WITH TABLEVIEW MAGIC
-(void)clearView:(BOOL)recurse
{
    [self setView:nil];
    if (recurse)
    pthread_rwlock_rdlock(&childrenLock);
    for (TiViewProxy* child in [self children]) {
        [child clearView:recurse];
    }
    pthread_rwlock_unlock(&childrenLock);
}

//CAUTION: TO BE USED ONLY WITH TABLEVIEW MAGIC
-(void)setView:(TiUIView *)newView
{
    if (view == newView) return;
    
    RELEASE_TO_NIL(view)
    
    if (self.modelDelegate!=nil)
    {
        if ([self.modelDelegate respondsToSelector:@selector(detachProxy)])
            [self.modelDelegate detachProxy];
        self.modelDelegate = nil;
    }
    
    if (newView == nil)
        readyToCreateView = defaultReadyToCreateView;
    else {
        view = [newView retain];
        self.modelDelegate = newView;
    }
}

//USED WITH TABLEVIEW MAGIC
-(void)processPendingAdds
{
    pthread_rwlock_rdlock(&childrenLock);
    for (TiViewProxy* child in [self children]) {
        [child processPendingAdds];
    }
    
    pthread_rwlock_unlock(&childrenLock);
    if (pendingAdds != nil)
    {
        for (id child in pendingAdds)
        {
            [(TiViewProxy*)child processPendingAdds];
            [self add:child];
        }
		RELEASE_TO_NIL(pendingAdds);
    }
}

//CAUTION: TO BE USED ONLY WITH TABLEVIEW MAGIC
-(void)fakeOpening
{
    windowOpened = parentVisible = YES;
}

-(NSMutableDictionary*)langConversionTable
{
    return nil;
}

#pragma mark Methods subclasses should override for behavior changes
-(BOOL)optimizeSubviewInsertion
{
    //Return YES for any view that implements a wrapperView that is a TiUIView (Button and ScrollView currently) and a basic view
    return ( [view isMemberOfClass:[TiUIView class]] ) ;
}

-(BOOL)suppressesRelayout
{
    if (controller != nil) {
        //If controller view is not loaded, sandbox bounds will become zero.
        //In that case we do not want to mess up our sandbox, which is by default
        //mainscreen bounds. It will adjust when view loads.
        return [controller isViewLoaded];
    }
	return NO;
}

-(BOOL)supportsNavBarPositioning
{
	return YES;
}

// TODO: Re-evaluate this along with the other controller propagation mechanisms, post 1.3.0.
// Returns YES for anything that can have a UIController object in its parent view
-(BOOL)canHaveControllerParent
{
	return YES;
}

-(BOOL)shouldDetachViewOnUnload
{
	return YES;
}

-(UIView *)parentViewForChild:(TiViewProxy *)child
{
	return [view parentViewForChildren];
}

#pragma mark Event trigger methods

-(void)windowWillOpen
{

	pthread_rwlock_rdlock(&childrenLock);
	
	// this method is called just before the top level window
	// that this proxy is part of will open and is ready for
	// the views to be attached
	
	if (windowOpened==YES)
	{
		pthread_rwlock_unlock(&childrenLock);
		return;
	}
	
	windowOpened = YES;
	windowOpening = YES;
    	
	// If the window was previously opened, it may need to have
	// its existing children redrawn
	// Maybe need to call layout children instead for non absolute layout
    NSArray* subproxies = [self children];
    for (TiViewProxy* child in subproxies) {
//        [self layoutChild:child optimize:NO withMeasuredBounds:[[self size] rect]];
        [child windowWillOpen];
    }
	
	pthread_rwlock_unlock(&childrenLock);
	
	if (pendingAdds!=nil)
	{
		for (id child in pendingAdds)
		{
			[self add:child];
			[child windowWillOpen];
		}
		RELEASE_TO_NIL(pendingAdds);
	}
    
    //TODO: This should be properly handled and moved, but for now, let's force it (Redundantly, I know.)
	if (parent != nil) {
		[self parentWillShow];
	}
}

-(void)windowDidOpen
{
	windowOpening = NO;
	pthread_rwlock_rdlock(&childrenLock);
	for (TiViewProxy *child in children)
	{
		[child windowDidOpen];
	}
	pthread_rwlock_unlock(&childrenLock);
}

-(void)windowWillClose
{
	pthread_rwlock_rdlock(&childrenLock);
	[children makeObjectsPerformSelector:@selector(windowWillClose)];
	pthread_rwlock_unlock(&childrenLock);
}

-(void)windowDidClose
{
    [self clearAnimations];
    if (controller) {
        [controller removeFromParentViewController];
        RELEASE_TO_NIL_AUTORELEASE(controller);
    }
	pthread_rwlock_rdlock(&childrenLock);
	for (TiViewProxy *child in children)
	{
		[child windowDidClose];
	}
	pthread_rwlock_unlock(&childrenLock);
	[self detachView];
	windowOpened=NO;
}


-(void)willFirePropertyChanges
{
	// for subclasses
	if ([view respondsToSelector:@selector(willFirePropertyChanges)])
	{
		[view performSelector:@selector(willFirePropertyChanges)];
	}
}

-(void)didFirePropertyChanges
{
	// for subclasses
	if ([view respondsToSelector:@selector(didFirePropertyChanges)])
	{
		[view performSelector:@selector(didFirePropertyChanges)];
	}
}

-(void)viewWillAttach
{
	// for subclasses
}


-(void)viewDidAttach
{
	// for subclasses
}

-(void)viewWillDetach
{
	// for subclasses
}

-(void)viewDidDetach
{
	// for subclasses
}

-(void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    //For various views (scrollableView, NavGroup etc this info neeeds to be forwarded)
    NSArray* childProxies = [self children];
	for (TiViewProxy * thisProxy in childProxies)
	{
		if ([thisProxy respondsToSelector:@selector(willAnimateRotationToInterfaceOrientation:duration:)])
		{
			[(id)thisProxy willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
		}
	}
}

-(void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    //For various views (scrollableView, NavGroup etc this info neeeds to be forwarded)
    NSArray* childProxies = [self children];
	for (TiViewProxy * thisProxy in childProxies)
	{
		if ([thisProxy respondsToSelector:@selector(willRotateToInterfaceOrientation:duration:)])
		{
			[(id)thisProxy willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
		}
	}
}

-(void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    //For various views (scrollableView, NavGroup etc this info neeeds to be forwarded)
    NSArray* childProxies = [self children];
	for (TiViewProxy * thisProxy in childProxies)
	{
		if ([thisProxy respondsToSelector:@selector(didRotateFromInterfaceOrientation:)])
		{
			[(id)thisProxy didRotateFromInterfaceOrientation:fromInterfaceOrientation];
		}
	}
}

#pragma mark Housecleaning state accessors

-(BOOL)viewHasSuperview:(UIView *)superview
{
	return [(UIView *)view superview] == superview;
}

-(BOOL)viewAttached
{
	return view!=nil && windowOpened;
}

-(BOOL)viewLayedOut
{
    CGRect rectToTest = parent?sizeCache:[[self view] bounds];
    return (rectToTest.size.width != 0 || rectToTest.size.height != 0);
}

//TODO: When swapping about proxies, views are uninitialized, aren't they?
-(BOOL)viewInitialized
{
	return viewInitialized && (view != nil);
}

-(BOOL)viewReady
{
	return view!=nil &&
			CGRectIsNull(view.bounds)==NO &&
			[view superview] != nil;
}

-(BOOL)windowHasOpened
{
	return windowOpened;
}

-(BOOL)windowIsOpening
{
	return windowOpening;
}

- (BOOL) isUsingBarButtonItem
{
	return isUsingBarButtonItem;
}

#pragma mark Building up and Tearing down

-(void)resetDefaultValues
{
    autoresizeCache = UIViewAutoresizingNone;
    sizeCache = CGRectZero;
    sandboxBounds = CGRectZero;
    positionCache = CGPointZero;
    repositioning = NO;
    parentVisible = NO;
    viewInitialized = NO;
    readyToCreateView = defaultReadyToCreateView;
    windowOpened = NO;
    windowOpening = NO;
    dirtyflags = 0;
    allowContentChange = YES;
    needsContentChange = NO;
}

-(id)init
{
	if ((self = [super init]))
	{
		destroyLock = [[NSRecursiveLock alloc] init];
		pthread_rwlock_init(&childrenLock, NULL);
		_bubbleParent = YES;
        defaultReadyToCreateView = NO;
        hidden = NO;
        [self resetDefaultValues];
        _transitioning = NO;
        childrenCount = 0;
        vzIndex = 0;
//        _runningViewAnimations = [[NSMutableArray alloc] init];
	}
	return self;
}

-(void)_configure
{
    [self replaceValue:NUMBOOL(NO) forKey:@"fullscreen" notification:NO];
    [self replaceValue:NUMBOOL(YES) forKey:@"visible" notification:NO];
    [self replaceValue:NUMBOOL(FALSE) forKey:@"opaque" notification:NO];
    [self replaceValue:NUMFLOAT(1.0f) forKey:@"opacity" notification:NO];
}

-(void)_initWithProperties:(NSDictionary*)properties
{
    updateStarted = YES;
    allowLayoutUpdate = NO;
	// Set horizontal layout wrap:true as default 
	layoutProperties.layoutFlags.horizontalWrap = NO;
    layoutProperties.fullscreen = NO;
	[self initializeProperty:@"visible" defaultValue:NUMBOOL(YES)];
    
    if ([properties objectForKey:@"properties"] || [properties objectForKey:@"childTemplates"]) {
        [self unarchiveFromDictionary:properties rootProxy:self];
        return;
    }
	
	if (properties!=nil)
	{
        NSNumber* isVisible = [properties objectForKey:@"visible"];
        hidden = ![TiUtils boolValue:isVisible def:YES];
        
		NSString *objectId = [properties objectForKey:@"id"];
		NSString* className = [properties objectForKey:@"className"];
		NSMutableArray* classNames = [properties objectForKey:@"classNames"];
		
		NSString *type = [NSStringFromClass([self class]) stringByReplacingOccurrencesOfString:@"TiUI" withString:@""];
		type = [[type stringByReplacingOccurrencesOfString:@"Proxy" withString:@""] lowercaseString];

		TiStylesheet *stylesheet = [[[self pageContext] host] stylesheet];
		NSString *basename = [[self pageContext] basename];
		NSString *density = [TiUtils isRetinaDisplay] ? @"high" : @"medium";

		if (objectId!=nil || className != nil || classNames != nil || [stylesheet basename:basename density:density hasTag:type])
		{
			// get classes from proxy
			NSString *className = [properties objectForKey:@"className"];
			NSMutableArray *classNames = [properties objectForKey:@"classNames"];
			if (classNames==nil)
			{
				classNames = [NSMutableArray arrayWithCapacity:1];
			}
			if (className!=nil)
			{
				[classNames addObject:className];
			}

		    
		    NSDictionary *merge = [stylesheet stylesheet:objectId density:density basename:basename classes:classNames tags:[NSArray arrayWithObject:type]];
			if (merge!=nil)
			{
				// incoming keys take precendence over existing stylesheet keys
				NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:merge];
				[dict addEntriesFromDictionary:properties];
                
				properties = dict;
			}
		}
		// do a translation of language driven keys to their converted counterparts
		// for example titleid should look up the title in the Locale
		NSMutableDictionary *table = [self langConversionTable];
		if (table!=nil)
		{
			for (id key in table)
			{
				// determine which key in the lang table we need to use
				// from the lang property conversion key
				id langKey = [properties objectForKey:key];
				if (langKey!=nil)
				{
					// eg. titleid -> title
					id convertKey = [table objectForKey:key];
					// check and make sure we don't already have that key
					// since you can't override it if already present
					if ([properties objectForKey:convertKey]==nil)
					{
						id newValue = [TiLocale getString:langKey comment:nil];
						if (newValue!=nil)
						{
							[(NSMutableDictionary*)properties setObject:newValue forKey:convertKey];
						}
					}
				}
			}
		}
	}
	[super _initWithProperties:properties];
    updateStarted = NO;
    allowLayoutUpdate = YES;
    [self processTempProperties:nil];
    allowLayoutUpdate = NO;

}

-(void)dealloc
{
    if (controller != nil) {
        [controller detachProxy]; //make the controller knows we are done
        TiThreadReleaseOnMainThread(controller, NO);
        controller = nil;
    }
	RELEASE_TO_NIL(pendingAdds);
	RELEASE_TO_NIL(destroyLock);
//	RELEASE_TO_NIL(_runningViewAnimations);
	pthread_rwlock_destroy(&childrenLock);
	
	//Dealing with children is in _destroy, which is called by super dealloc.
	
	[super dealloc];
}


-(void)viewWillAppear:(BOOL)animated
{
    [self parentWillShowWithoutUpdate];
    [self refreshView];
}
-(void)viewWillDisappear:(BOOL)animated
{
    [self parentWillHide];
}

-(UIViewController*)hostingController;
{
    if (controller == nil) {
        controller = [[TiViewController alloc] initWithViewProxy:self];
    }
    return controller;
}

-(BOOL)retainsJsObjectForKey:(NSString *)key
{
	return ![key isEqualToString:@"animation"];
}

-(void)firePropertyChanges
{
	[self willFirePropertyChanges];
	
	if ([view respondsToSelector:@selector(readProxyValuesWithKeys:)]) {
		id<NSFastEnumeration> values = [self allKeys];
		[view readProxyValuesWithKeys:values];
	}

	[self didFirePropertyChanges];
}

-(TiUIView*)newView
{
    TiUIView* newview = nil;
	NSString * proxyName = NSStringFromClass([self class]);
	if ([proxyName hasSuffix:@"Proxy"]) 
	{
		Class viewClass = nil;
		NSString * className = [proxyName substringToIndex:[proxyName length]-5];
		viewClass = NSClassFromString(className);
		if (viewClass != nil)
		{
			return [[viewClass alloc] init];
		}
	}
	else
	{
		DeveloperLog(@"[WARN] No TiView for Proxy: %@, couldn't find class: %@",self,proxyName);
	}
    return [[TiUIView alloc] init];
}


-(void)detachView
{
	[self detachView:YES];
}

-(void)detachView:(BOOL)recursive
{
	[destroyLock lock];
    
    if(recursive)
    {
        pthread_rwlock_rdlock(&childrenLock);
        [[self children] makeObjectsPerformSelector:@selector(detachView)];
        pthread_rwlock_unlock(&childrenLock);
    }
    
	if (view!=nil)
	{
		[self viewWillDetach];
        [self cancelAllAnimations:nil];
		[view removeFromSuperview];
		view.proxy = nil;
        view.touchDelegate = nil;
		RELEASE_TO_NIL(view);
		[self viewDidDetach];
	}
    if (self.modelDelegate!=nil)
    {
        if ([self.modelDelegate respondsToSelector:@selector(detachProxy)])
            [self.modelDelegate detachProxy];
        self.modelDelegate = nil;
    }
	[destroyLock unlock];
    [self clearAnimations];
    [self resetDefaultValues];

}

-(void)_destroy
{
	[destroyLock lock];
	if ([self destroyed])
	{
		// not safe to do multiple times given rwlock
		[destroyLock unlock];
		return;
	}
	// _destroy is called during a JS context shutdown, to inform the object to 
	// release all its memory and references.  this will then cause dealloc 
	// on objects that it contains (assuming we don't have circular references)
	// since some of these objects are registered in the context and thus still
	// reachable, we need _destroy to help us start the unreferencing part


	pthread_rwlock_wrlock(&childrenLock);
	[children makeObjectsPerformSelector:@selector(setParent:) withObject:nil];
	RELEASE_TO_NIL(children);
	pthread_rwlock_unlock(&childrenLock);
	[super _destroy];

	//Part of super's _destroy is to release the modelDelegate, which in our case is ALSO the view.
	//As such, we need to have the super happen before we release the view, so that we can insure that the
	//release that triggers the dealloc happens on the main thread.
	
	if (barButtonItem != nil)
	{
		if ([NSThread isMainThread])
		{
			RELEASE_TO_NIL(barButtonItem);
		}
		else
		{
			TiThreadReleaseOnMainThread(barButtonItem, NO);
			barButtonItem = nil;
		}
	}

	if (view!=nil)
	{
		if ([NSThread isMainThread])
		{
			[self detachView];
		}
		else
		{
			view.proxy = nil;
			TiThreadReleaseOnMainThread(view, NO);
			view = nil;
		}
	}
	[destroyLock unlock];
}

-(void)destroy
{
	//FIXME- me already have a _destroy, refactor this
	[self _destroy];
}

-(void)removeBarButtonView
{
	isUsingBarButtonItem = NO;
	[self setBarButtonItem:nil];
}

#pragma mark Callbacks

-(void)didReceiveMemoryWarning:(NSNotification*)notification
{
	// Only release a view if we're the only living reference for it
	// WARNING: do not call [self view] here as that will create the
	// view if it doesn't yet exist (thus defeating the purpose of
	// this method)
	
	//NOTE: for now, we're going to have to turn this off until post
	//1.4 where we can figure out why the drawing is screwed up since
	//the views aren't reattaching.  
	/*
	if (view!=nil && [view retainCount]==1)
	{
		[self detachView];
	}*/
	[super didReceiveMemoryWarning:notification];
}

-(void)makeViewPerformSelector:(SEL)selector withObject:(id)object createIfNeeded:(BOOL)create waitUntilDone:(BOOL)wait
{
	BOOL isAttached = [self viewAttached];
	
	if(!isAttached && !create)
	{
		return;
	}

	if([NSThread isMainThread])
	{
		[[self view] performSelector:selector withObject:object];
		return;
	}

	if(isAttached)
	{
		TiThreadPerformOnMainThread(^{[[self view] performSelector:selector withObject:object];}, wait);
		return;
	}

	TiThreadPerformOnMainThread(^{
		[[self view] performSelector:selector withObject:object];
	}, wait);
}

#pragma mark Listener Management

-(BOOL)_hasListeners:(NSString *)type checkParent:(BOOL)check
{
    BOOL returnVal = [super _hasListeners:type];
    if (_bubbleParentDefined) {
        check = _bubbleParent;
    }
    if (!returnVal && check) {
        returnVal = [[self parentForBubbling] _hasListeners:type];
    }
	return returnVal;
}

-(BOOL)_hasListeners:(NSString *)type
{
	return [self _hasListeners:type checkParent:YES];
}

-(void)fireEvent:(NSString*)type withObject:(id)obj propagate:(BOOL)propagate reportSuccess:(BOOL)report errorCode:(int)code message:(NSString*)message checkForListener:(BOOL)checkForListener;
{
    if (checkForListener && ![self _hasListeners:type])
	{
		return;
	}
	
    if (eventOverrideDelegate != nil) {
        obj = [eventOverrideDelegate overrideEventObject:obj forEvent:type fromViewProxy:self];
    }
	[super fireEvent:type withObject:obj propagate:propagate reportSuccess:report errorCode:code message:message checkForListener:NO];
}

-(void)parentListenersChanged
{
    TiThreadPerformOnMainThread(^{
        if (view != nil && [view respondsToSelector:@selector(updateTouchHandling)]) {
            [view updateTouchHandling];
        }
    }, NO);
}

-(void)_listenerAdded:(NSString*)type count:(int)count
{
	if (self.modelDelegate!=nil && [(NSObject*)self.modelDelegate respondsToSelector:@selector(listenerAdded:count:)])
	{
		[self.modelDelegate listenerAdded:type count:count];
	}
	else if(view!=nil) // don't create the view if not already realized
	{
		if ([self.view respondsToSelector:@selector(listenerAdded:count:)]) {
			[self.view listenerAdded:type count:count];
		}
	}
    
    //TIMOB-15991 Update children as well
    NSArray* childrenArray = [[self children] retain];
    for (id child in childrenArray) {
        if ([child respondsToSelector:@selector(parentListenersChanged)]) {
            [child parentListenersChanged];
        }
    }
    [childrenArray release];
}

-(void)_listenerRemoved:(NSString*)type count:(int)count
{
	if (self.modelDelegate!=nil && [(NSObject*)self.modelDelegate respondsToSelector:@selector(listenerRemoved:count:)])
	{
		[self.modelDelegate listenerRemoved:type count:count];
	}
	else if(view!=nil) // don't create the view if not already realized
	{
		if ([self.view respondsToSelector:@selector(listenerRemoved:count:)]) {
			[self.view listenerRemoved:type count:count];
		}
	}

    //TIMOB-15991 Update children as well
    NSArray* childrenArray = [[self children] retain];
    for (id child in childrenArray) {
        if ([child respondsToSelector:@selector(parentListenersChanged)]) {
            [child parentListenersChanged];
        }
    }
    [childrenArray release];
}

-(TiProxy *)parentForBubbling
{
	return parent;
}

#pragma mark Layout events, internal and external

#define SET_AND_PERFORM(flagBit,action)	\
if (!viewInitialized || hidden || !parentVisible || OSAtomicTestAndSetBarrier(flagBit, &dirtyflags)) \
{	\
	action;	\
}


-(void)willEnqueue
{
	SET_AND_PERFORM(TiRefreshViewEnqueued,return);
    if (!allowContentChange) return;
	[TiLayoutQueue addViewProxy:self];
}

-(void)willEnqueueIfVisible
{
	if(parentVisible && !hidden)
	{
		[self willEnqueue];
	}
}


-(void)performBlockWithoutLayout:(void (^)(void))block
{
    allowContentChange = NO;
    block();
    allowContentChange = YES;
}

-(void)parentContentWillChange
{
    if (allowContentChange == NO && [parent allowContentChange])
    {
        [parent performBlockWithoutLayout:^{
            [parent contentsWillChange];
        }];
    }
    else {
        [parent contentsWillChange];
    }
}

-(void)willChangeSize
{
	SET_AND_PERFORM(TiRefreshViewSize,return);

	if (![self absoluteLayout])
	{
		[self willChangeLayout];
	}
    else {
        [self willResizeChildren];
    }
	if(TiDimensionIsUndefined(layoutProperties.centerX) ||
			TiDimensionIsUndefined(layoutProperties.centerY))
	{
		[self willChangePosition];
	}

	[self willEnqueueIfVisible];
    [self parentContentWillChange];
	
    if (!allowContentChange) return;
	pthread_rwlock_rdlock(&childrenLock);
	[children makeObjectsPerformSelector:@selector(parentSizeWillChange)];
	pthread_rwlock_unlock(&childrenLock);
}

-(void)willChangePosition
{
	SET_AND_PERFORM(TiRefreshViewPosition,return);

	if(TiDimensionIsUndefined(layoutProperties.width) || 
			TiDimensionIsUndefined(layoutProperties.height))
	{//The only time size can be changed by the margins is if the margins define the size.
		[self willChangeSize];
	}
	[self willEnqueueIfVisible];
    [self parentContentWillChange];
}

-(void)willChangeZIndex
{
	SET_AND_PERFORM(TiRefreshViewZIndex, return);
	//Nothing cascades from here.
	[self willEnqueueIfVisible];
}

-(void)willShow;
{
    [self willChangeZIndex];
    
    pthread_rwlock_rdlock(&childrenLock);
    if (allowContentChange)
    {
        [children makeObjectsPerformSelector:@selector(parentWillShow)];
    }
    else {
        [children makeObjectsPerformSelector:@selector(parentWillShowWithoutUpdate)];
    }
    pthread_rwlock_unlock(&childrenLock);
    
    if (parent && ![parent absoluteLayout])
        [self parentContentWillChange];
    else {
        [self contentsWillChange];
    }
    
}

-(void)willHide;
{
    //	SET_AND_PERFORM(TiRefreshViewZIndex,);
    dirtyflags = 0;
    
	pthread_rwlock_rdlock(&childrenLock);
	[children makeObjectsPerformSelector:@selector(parentWillHide)];
	pthread_rwlock_unlock(&childrenLock);
    
    if (parent && ![parent absoluteLayout])
        [self parentContentWillChange];
}

-(void)willResizeChildren
{
    if (childrenCount == 0) return;
	SET_AND_PERFORM(TiRefreshViewChildrenPosition,return);
	[self willEnqueueIfVisible];
}

-(void)willChangeLayout
{
    if (!viewInitialized)return;
    BOOL alreadySet = OSAtomicTestAndSet(TiRefreshViewChildrenPosition, &dirtyflags);

	[self willEnqueueIfVisible];

    if (!allowContentChange || alreadySet) return;
	pthread_rwlock_rdlock(&childrenLock);
	[children makeObjectsPerformSelector:@selector(parentWillRelay)];
	pthread_rwlock_unlock(&childrenLock);
}

-(BOOL) widthIsAutoSize
{
    if (layoutProperties.fullscreen) return NO;
    BOOL isAutoSize = NO;
    if (TiDimensionIsAutoSize(layoutProperties.width))
    {
        isAutoSize = YES;
    }
    else if (TiDimensionIsAuto(layoutProperties.width) && TiDimensionIsAutoSize([self defaultAutoWidthBehavior:nil]) )
    {
        isAutoSize = YES;
    }
    else if (TiDimensionIsUndefined(layoutProperties.width) && TiDimensionIsAutoSize([self defaultAutoWidthBehavior:nil]))
    {
        int pinCount = 0;
        if (!TiDimensionIsUndefined(layoutProperties.left) ) {
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.centerX) ) {
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.right) ) {
            pinCount ++;
        }
        if (pinCount < 2) {
            isAutoSize = YES;
        }
    }
    return isAutoSize;
}

-(BOOL) heightIsAutoSize
{
    if (layoutProperties.fullscreen) return NO;
    BOOL isAutoSize = NO;
    if (TiDimensionIsAutoSize(layoutProperties.height))
    {
        isAutoSize = YES;
    }
    else if (TiDimensionIsAuto(layoutProperties.height) && TiDimensionIsAutoSize([self defaultAutoHeightBehavior:nil]) )
    {
        isAutoSize = YES;
    }
    else if (TiDimensionIsUndefined(layoutProperties.height) && TiDimensionIsAutoSize([self defaultAutoHeightBehavior:nil]))
    {
        int pinCount = 0;
        if (!TiDimensionIsUndefined(layoutProperties.top) ) {
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.centerY) ) {
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.bottom) ) {
            pinCount ++;
        }
        if (pinCount < 2) {
            isAutoSize = YES;
        }
    }
    return isAutoSize;
}

-(BOOL) widthIsAutoFill
{
    if (layoutProperties.fullscreen) return YES;
    BOOL isAutoFill = NO;
    BOOL followsFillBehavior = TiDimensionIsAutoFill([self defaultAutoWidthBehavior:nil]);
    
    if (TiDimensionIsAutoFill(layoutProperties.width))
    {
        isAutoFill = YES;
    }
    else if (TiDimensionIsAuto(layoutProperties.width))
    {
        isAutoFill = followsFillBehavior;
    }
    else if (TiDimensionIsUndefined(layoutProperties.width))
    {
        BOOL centerDefined = NO;
        int pinCount = 0;
        if (!TiDimensionIsUndefined(layoutProperties.left) ) {
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.centerX) ) {
            centerDefined = YES;
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.right) ) {
            pinCount ++;
        }
        if ( (pinCount < 2) || (!centerDefined) ){
            isAutoFill = followsFillBehavior;
        }
    }
    return isAutoFill;
}

-(BOOL) heightIsAutoFill
{
    if (layoutProperties.fullscreen) return YES;
    BOOL isAutoFill = NO;
    BOOL followsFillBehavior = TiDimensionIsAutoFill([self defaultAutoHeightBehavior:nil]);
    
    if (TiDimensionIsAutoFill(layoutProperties.height))
    {
        isAutoFill = YES;
    }
    else if (TiDimensionIsAuto(layoutProperties.height))
    {
        isAutoFill = followsFillBehavior;
    }
    else if (TiDimensionIsUndefined(layoutProperties.height))
    {
        BOOL centerDefined = NO;
        int pinCount = 0;
        if (!TiDimensionIsUndefined(layoutProperties.top) ) {
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.centerY) ) {
            centerDefined = YES;
            pinCount ++;
        }
        if (!TiDimensionIsUndefined(layoutProperties.bottom) ) {
            pinCount ++;
        }
        if ( (pinCount < 2) || (!centerDefined) ) {
            isAutoFill = followsFillBehavior;
        }
    }
    return isAutoFill;
}

-(void)contentsWillChange
{
    BOOL isAutoSize = [self widthIsAutoSize] || [self heightIsAutoSize];
    
	if (isAutoSize)
	{
		[self willChangeSize];
	}
	else if (![self absoluteLayout])
	{//Since changing size already does this, we only need to check
	//Layout if the changeSize didn't
		[self willChangeLayout];
	}
}

-(BOOL)allowContentChange
{
    return allowContentChange;
}

-(void)contentsWillChangeImmediate
{
    allowContentChange = NO;
    [self contentsWillChange];
    allowContentChange = YES;
    [self refreshViewOrParent];
}

-(void)contentsWillChangeAnimated:(NSTimeInterval)duration
{
    [UIView animateWithDuration:duration animations:^{
        [self contentsWillChangeImmediate];
    }];
}

-(void)parentSizeWillChange
{
//	if not dip, change size
	if(!TiDimensionIsDip(layoutProperties.width) || !TiDimensionIsDip(layoutProperties.height) )
	{
		[self willChangeSize];
	}
	if(!TiDimensionIsDip(layoutProperties.centerX) ||
			!TiDimensionIsDip(layoutProperties.centerY))
	{
		[self willChangePosition];
	}
}

-(void)parentWillRelay
{
//	if percent or undefined size, change size
	if(TiDimensionIsUndefined(layoutProperties.width) ||
			TiDimensionIsUndefined(layoutProperties.height) ||
			TiDimensionIsPercent(layoutProperties.width) ||
			TiDimensionIsPercent(layoutProperties.height))
	{
		[self willChangeSize];
	}
	[self willChangePosition];
}

-(void)parentWillShow
{
	VerboseLog(@"[INFO] Parent Will Show for %@",self);
	if(parentVisible)
	{//Nothing to do here, we're already visible here.
		return;
	}
	parentVisible = YES;
	if(!hidden)
	{	//We should propagate this new status! Note this does not change the visible property.
		[self willShow];
	}
}

-(void)parentWillShowWithoutUpdate
{
    BOOL wasSet = allowContentChange;
    allowContentChange = NO;
    [self parentWillShow];
    allowContentChange = wasSet;
}

-(void)parentWillHide
{
	VerboseLog(@"[INFO] Parent Will Hide for %@",self);
	if(!parentVisible)
	{//Nothing to do here, we're already invisible here.
		return;
	}
	parentVisible = NO;
	if(!hidden)
	{	//We should propagate this new status! Note this does not change the visible property.
		[self willHide];
	}
}

#pragma mark Layout actions


-(void)updateZIndex {
    if(OSAtomicTestAndClearBarrier(TiRefreshViewZIndex, &dirtyflags) && vzIndex > 0) {
//        [parent insertSubview:view forProxy:self];
        UIView * ourSuperview = [[self view] superview];
        if(ourSuperview != nil) {
            [[self class] reorderViewsInParent:ourSuperview];
        }
    }
}

// Need this so we can overload the sandbox bounds on split view detail/master
-(void)determineSandboxBounds
{
    if (controller) return;
    [self updateZIndex];
    UIView * ourSuperview = [[self view] superview];
    if(ourSuperview != nil)
    {
        sandboxBounds = [ourSuperview bounds];
    }
}

-(void)refreshView:(TiUIView *)transferView
{
    [self refreshView:transferView withinAnimation:nil];
}


-(void)refreshView
{
    [self dirtyItAll];
	[self refreshViewIfNeeded:NO];
}

-(void)refreshViewIfNeeded
{
	[self refreshViewIfNeeded:NO];
}

-(void)refreshViewOrParent
{
    if (parent && [parent isDirty]) {
        if ([view runningAnimation])
        {
            [parent setRunningAnimation:[self runningAnimation]];
            [parent refreshViewOrParent];
            [parent setRunningAnimation:nil];
        }
        else {
            
            [parent refreshViewOrParent];
        }
    }
    else {
        [self refreshViewIfNeeded:YES];
    }
}

-(void)refreshViewIfNeeded:(BOOL)recursive
{
    BOOL needsRefresh = OSAtomicTestAndClear(TiRefreshViewEnqueued, &dirtyflags);
    if (parent && [parent willBeRelaying] && ![parent absoluteLayout]) {
        return;
    }
    
    if (!needsRefresh)
    {
        //even if our sandbox is null and we are not ready (next test) let s still call refresh our our children. They wont refresh but at least they will clear their TiRefreshViewEnqueued flags !
        if (recursive){
            [self makeChildrenPerformSelector:@selector(refreshViewIfNeeded:) withObject:recursive];
        }
        return;
	}
    if (CGRectIsEmpty(sandboxBounds) && (!view || ![view superview])) {
        //we have no way to get our size yet. May be we need to be added to a superview
        //let s keep our flags set
        return;
    }
    
	if(parent && !parentVisible)
	{
		VerboseLog(@"[INFO] Parent Invisible");
		return;
	}
	
	if(hidden)
	{
		return;
	}
    
    if (view != nil)
	{
        BOOL relayout = ![self suppressesRelayout];
        if (parent != nil && ![parent absoluteLayout]) {
            //Do not mess up the sandbox in vertical/horizontal layouts
            relayout = NO;
        }
        if(relayout)
        {
            [self determineSandboxBounds];
        }
        BOOL layoutChanged = [self relayout];
        
        if (OSAtomicTestAndClear(TiRefreshViewChildrenPosition, &dirtyflags) || layoutChanged) {
            [self layoutChildren:NO];
        }
	}
}

-(void)dirtyItAll
{
    OSAtomicTestAndSet(TiRefreshViewZIndex, &dirtyflags);
    OSAtomicTestAndSet(TiRefreshViewEnqueued, &dirtyflags);
    OSAtomicTestAndSet(TiRefreshViewSize, &dirtyflags);
    OSAtomicTestAndSet(TiRefreshViewPosition, &dirtyflags);
    if (childrenCount > 0) OSAtomicTestAndSet(TiRefreshViewChildrenPosition, &dirtyflags);
}

-(void)clearItAll
{
    dirtyflags = 0;
}

-(BOOL)isDirty
{
    return [self willBeRelaying];
}

-(void)refreshView:(TiUIView *)transferView withinAnimation:(TiViewAnimationStep*)animation
{
    [transferView setRunningAnimation:animation];
    WARN_IF_BACKGROUND_THREAD_OBJ;
	OSAtomicTestAndClearBarrier(TiRefreshViewEnqueued, &dirtyflags);
	
	if(!parentVisible)
	{
		VerboseLog(@"[INFO] Parent Invisible");
		return;
	}
	
	if(hidden)
	{
		return;
	}
    
	BOOL changedFrame = NO;
    //BUG BARRIER: Code in this block is legacy code that should be factored out.
	if (windowOpened && [self viewAttached])
	{
		CGRect oldFrame = [[self view] frame];
        BOOL relayout = ![self suppressesRelayout];
        if (parent != nil && ![parent absoluteLayout]) {
            //Do not mess up the sandbox in vertical/horizontal layouts
            relayout = NO;
        }
        if(relayout)
        {
            [self determineSandboxBounds];
        }
        if ([self relayout] || relayout || animation || OSAtomicTestAndClear(TiRefreshViewChildrenPosition, &dirtyflags)) {
            OSAtomicTestAndClear(TiRefreshViewChildrenPosition, &dirtyflags);
            [self layoutChildren:NO];
        }
		if (!CGRectEqualToRect(oldFrame, [[self view] frame])) {
			[parent childWillResize:self withinAnimation:animation];
		}
	}
    
    //END BUG BARRIER
    
	if(OSAtomicTestAndClearBarrier(TiRefreshViewSize, &dirtyflags))
	{
		[self refreshSize];
		if(TiLayoutRuleIsAbsolute(layoutProperties.layoutStyle))
		{
			pthread_rwlock_rdlock(&childrenLock);
			for (TiViewProxy * thisChild in children)
			{
				[thisChild setSandboxBounds:sizeCache];
			}
			pthread_rwlock_unlock(&childrenLock);
		}
		changedFrame = YES;
	}
	else if(transferView != nil)
	{
		[transferView setBounds:sizeCache];
	}
    
	if(OSAtomicTestAndClearBarrier(TiRefreshViewPosition, &dirtyflags))
	{
		[self refreshPosition];
		changedFrame = YES;
	}
	else if(transferView != nil)
	{
		[transferView setCenter:positionCache];
	}
    
    //We should only recurse if we're a non-absolute layout. Otherwise, the views can take care of themselves.
	if(OSAtomicTestAndClearBarrier(TiRefreshViewChildrenPosition, &dirtyflags) && (transferView == nil))
        //If transferView is non-nil, this will be managed by the table row.
	{
		
	}
    
	if(transferView != nil)
	{
        //TODO: Better handoff of view
		[self setView:transferView];
	}
    
    //By now, we MUST have our view set to transferView.
	if(changedFrame || (transferView != nil))
	{
		[view setAutoresizingMask:autoresizeCache];
	}
    
    
	[self updateZIndex];
    [transferView setRunningAnimation:nil];
}

-(void)refreshPosition
{
	OSAtomicTestAndClearBarrier(TiRefreshViewPosition, &dirtyflags);
}

-(void)refreshSize
{
	OSAtomicTestAndClearBarrier(TiRefreshViewSize, &dirtyflags);
}


+(void)reorderViewsInParent:(UIView*)parentView
{
	if (parentView == nil) return;
    
    NSMutableArray* parentViewToSort = [NSMutableArray array];
    for (UIView* subview in [parentView subviews])
    {
        if ([subview isKindOfClass:[TiUIView class]]) {
            [parentViewToSort addObject:subview];
        }
    }
    NSArray *sortedArray = [parentViewToSort sortedArrayUsingSelector:@selector(compare:)];
    for (TiUIView* view in sortedArray) {
        [parentView bringSubviewToFront:view];
    }
}

-(void)insertSubview:(UIView *)childView forProxy:(TiViewProxy *)childProxy
{
	int result = 0;
//	int childZindex = [childProxy vzIndex];
	int childZindex = 0;
	BOOL earlierSibling = YES;
	UIView * ourView = [self parentViewForChild:childProxy];
	if (ourView == nil) return;
    BOOL optimizeInsertion = [childProxy optimizeSubviewInsertion];
    
    for (UIView* subview in [ourView subviews])
    {
        if (!optimizeInsertion || ![subview isKindOfClass:[TiUIView class]]) {
            result++;
        }
    }
	pthread_rwlock_rdlock(&childrenLock);
	for (TiViewProxy * thisChildProxy in children)
	{
		if(thisChildProxy == childProxy)
		{
			earlierSibling = NO;
			continue;
		}
		
		if(![thisChildProxy viewHasSuperview:ourView])
		{
			continue;
		}
		
//		int thisChildZindex = [thisChildProxy vzIndex];
		int thisChildZindex = 0;
		if((thisChildZindex < childZindex) ||
				(earlierSibling && (thisChildZindex == childZindex)))
		{
			result ++;
		}
	}
	pthread_rwlock_unlock(&childrenLock);
    if ([[ourView subviews] indexOfObject:childView] != NSNotFound) return;
    if (result == 0 || result  >= [[ourView subviews] count]) {
        [ourView addSubview:childView];
    }
    else {
        //Doing a blind insert at index messes up the underlying sublayer indices
        //if there are layers which do not belong to subviews (backgroundGradient)
        //So ensure the subview layer goes at the right index
        //See TIMOB-11586 for fail case
        UIView *sibling = [[ourView subviews] objectAtIndex:result-1];
        [ourView insertSubview:childView aboveSubview:sibling];
    }
}


-(BOOL)absoluteLayout
{
    return TiLayoutRuleIsAbsolute(layoutProperties.layoutStyle);
}


-(CGRect)computeBoundsForParentBounds:(CGRect)parentBounds
{
    CGSize size = SizeConstraintViewWithSizeAddingResizing(&layoutProperties,self, parentBounds.size, &autoresizeCache);
    if (!CGSizeEqualToSize(size, sizeCache.size)) {
        sizeCache.size = size;
    }
    CGPoint position = PositionConstraintGivenSizeBoundsAddingResizing(&layoutProperties, [parent layoutProperties], self, sizeCache.size,
                                                               [[view layer] anchorPoint], parentBounds.size, sandboxBounds.size, &autoresizeCache);
    position.x += sizeCache.origin.x + sandboxBounds.origin.x;
    position.y += sizeCache.origin.y + sandboxBounds.origin.y;
    if (!CGPointEqualToPoint(position, positionCache)) {
        positionCache = position;
    }
    return CGRectMake(position.x - size.width/2, position.y - size.height/2, size.width, size.height);
}

#pragma mark Layout commands that need refactoring out

-(BOOL)relayout
{
	if (!repositioning && !CGSizeEqualToSize(sandboxBounds.size, CGSizeZero))
	{
		ENSURE_UI_THREAD_0_ARGS
        OSAtomicTestAndClear(TiRefreshViewEnqueued, &dirtyflags);
		repositioning = YES;

        UIView *parentView = [parent parentViewForChild:self];
        CGSize referenceSize = (parentView != nil) ? parentView.bounds.size : sandboxBounds.size;
        if (CGSizeEqualToSize(referenceSize, CGSizeZero)) {
            repositioning = NO;
            return;
        }
        BOOL needsAll = CGRectIsEmpty(sizeCache);
        BOOL needsSize = OSAtomicTestAndClear(TiRefreshViewSize, &dirtyflags) || needsAll;
        BOOL needsPosition = OSAtomicTestAndClear(TiRefreshViewPosition, &dirtyflags) || needsAll;
        BOOL layoutChanged = NO;
        if (needsSize) {
            CGSize size;
            if (parent != nil && ![parent absoluteLayout] ) {
                size = SizeConstraintViewWithSizeAddingResizing(&layoutProperties,self, sandboxBounds.size, &autoresizeCache);
            }
            else {
                size = SizeConstraintViewWithSizeAddingResizing(&layoutProperties,self, referenceSize, &autoresizeCache);
            }
            if (!CGSizeEqualToSize(size, sizeCache.size)) {
                sizeCache.size = size;
                layoutChanged = YES;
            }
        }
        if (needsPosition) {
            CGPoint position;
            position = PositionConstraintGivenSizeBoundsAddingResizing(&layoutProperties, [parent layoutProperties], self, sizeCache.size,
            [[view layer] anchorPoint], referenceSize, sandboxBounds.size, &autoresizeCache);

            position.x += sizeCache.origin.x + sandboxBounds.origin.x;
            position.y += sizeCache.origin.y + sandboxBounds.origin.y;
            if (!CGPointEqualToPoint(position, positionCache)) {
                positionCache = position;
                layoutChanged = YES;
            }
        }
        
        layoutChanged |= autoresizeCache != view.autoresizingMask;
        if (!layoutChanged && [view isKindOfClass:[TiUIView class]]) {
            //Views with flexible margins might have already resized when the parent resized.
            //So we need to explicitly check for oldSize here which triggers frameSizeChanged
            CGSize oldSize = [(TiUIView*) view oldSize];
            layoutChanged = layoutChanged || !(CGSizeEqualToSize(oldSize,sizeCache.size) || !CGRectEqualToRect([view bounds], sizeCache) || !CGPointEqualToPoint([view center], positionCache));
        }
        
		
        [view setAutoresizingMask:autoresizeCache];
        [view setBounds:sizeCache];
        [view setCenter:positionCache];
        
        [self updateZIndex];
        
        if ([observer respondsToSelector:@selector(proxyDidRelayout:)]) {
            [observer proxyDidRelayout:self];
        }

        if (layoutChanged) {
            [self fireEvent:@"postlayout" propagate:NO];
        }
        [self handlePendingAnimation];
        repositioning = NO;
        return layoutChanged;
	}
#ifdef VERBOSE
	else
	{
		DeveloperLog(@"[INFO] %@ Calling Relayout from within relayout.",self);
	}
#endif
    return NO;
}

-(void)layoutChildrenIfNeeded
{
	IGNORE_IF_NOT_OPENED
	
    // if not visible, ignore layout
    if (view.hidden)
    {
        OSAtomicTestAndClearBarrier(TiRefreshViewEnqueued, &dirtyflags);
        return;
    }
    
    [self refreshView:nil];
}

-(BOOL)willBeRelaying
{
    DeveloperLog(@"DIRTY FLAGS %d WILLBERELAYING %d",dirtyflags, (*((char*)&dirtyflags) & (1 << (7 - TiRefreshViewEnqueued))));
    return ((*((char*)&dirtyflags) & (1 << (7 - TiRefreshViewEnqueued))) != 0);
}

-(void)childWillResize:(TiViewProxy *)child
{
    [self childWillResize:child withinAnimation:nil];
}

-(void)childWillResize:(TiViewProxy *)child withinAnimation:(TiViewAnimationStep*)animation
{
    if (animation != nil) {
        [self refreshView:nil withinAnimation:animation];
        return;
    }
    
	[self contentsWillChange];

	IGNORE_IF_NOT_OPENED
	
	pthread_rwlock_rdlock(&childrenLock);
	BOOL containsChild = [children containsObject:child];
	pthread_rwlock_unlock(&childrenLock);

	ENSURE_VALUE_CONSISTENCY(containsChild,YES);

	if (![self absoluteLayout])
	{
		BOOL alreadySet = OSAtomicTestAndSet(TiRefreshViewChildrenPosition, &dirtyflags);
		if (!alreadySet)
		{
			[self willEnqueue];
		}
	}
}

-(void)reposition
{
    [self repositionWithinAnimation:nil];
}

-(TiViewAnimationStep*)runningAnimation
{
    return [view runningAnimation];
}

-(void)setRunningAnimation:(TiViewAnimationStep*)animation
{
    [view setRunningAnimation:animation];
}

-(void)setRunningAnimationRecursive:(TiViewAnimationStep*)animation
{
    [view setRunningAnimation:animation];
    [self runBlock:^(TiViewProxy *proxy) {
        [proxy setRunningAnimationRecursive:animation];
    } onlyVisible:YES recursive:YES];
}

-(void)setFakeAnimationOfDuration:(NSTimeInterval)duration andCurve:(CAMediaTimingFunction*)curve
{
    TiFakeAnimation* anim = [[TiFakeAnimation alloc] init];
    anim.duration = duration;
    anim.curve = curve;
    [self setRunningAnimationRecursive:anim];
}

-(BOOL)isRotating
{
    return [[self runningAnimation] isKindOfClass:[TiFakeAnimation class]];
}

-(void)removeFakeAnimation
{
    id anim = [self runningAnimation];
    if ([anim isKindOfClass:[TiFakeAnimation class]])
    {
        [self setRunningAnimationRecursive:nil];
        [anim release];
    }
}


-(void)repositionWithinAnimation:(TiViewAnimationStep*)animation
{
	IGNORE_IF_NOT_OPENED
	
	UIView* superview = [[self view] superview];
	if (![self viewAttached] || view.hidden || superview == nil)
	{
		VerboseLog(@"[INFO] Reposition is exiting early in %@.",self);
		return;
	}
	if ([NSThread isMainThread])
    {
        [self setRunningAnimation:animation];
        [self performBlockWithoutLayout:^{
            [self willChangeSize];
            [self willChangePosition];
        }];
        
        [self refreshViewOrParent];
        //        if (!CGRectEqualToRect(oldFrame, [[self view] frame])) {
        //			[parent childWillResize:self withinAnimation:animation];
        //		}
        [self setRunningAnimation:nil];
	}
	else
	{
		VerboseLog(@"[INFO] Reposition was called by a background thread in %@.",self);
		TiThreadPerformOnMainThread(^{[self reposition];}, NO);
	}
    
}

-(BOOL)wantsToFillVerticalLayout
{
    if ([self heightIsAutoFill]) return YES;
    if (TiDimensionIsDip(layoutProperties.height) || TiDimensionIsPercent(layoutProperties.height))return NO;
    NSArray* subproxies = [self visibleChildren];
    for (TiViewProxy* child in subproxies) {
        if ([child wantsToFillVerticalLayout]) return YES;
    }
    return NO;
}

-(BOOL)wantsToFillHorizontalLayout
{
    if ([self widthIsAutoFill]) return YES;
    if (TiDimensionIsDip(layoutProperties.width) || TiDimensionIsPercent(layoutProperties.width))return NO;
    NSArray* subproxies = [self visibleChildren];
    for (TiViewProxy* child in subproxies) {
        if ([child wantsToFillHorizontalLayout]) return YES;
    }
    return NO;
}

-(CGRect)boundsForMeasureForChild:(TiViewProxy*)child
{
    UIView * ourView = [self parentViewForChild:child];
    if (!ourView) return CGRectZero;
    return [ourView bounds];
}

-(NSArray*)measureChildren:(NSArray*)childArray
{
    if ([childArray count] == 0) {
        return nil;
    }
    
    BOOL horizontal =  TiLayoutRuleIsHorizontal(layoutProperties.layoutStyle);
    BOOL vertical =  TiLayoutRuleIsVertical(layoutProperties.layoutStyle);
	BOOL horizontalNoWrap = horizontal && !TiLayoutFlagsHasHorizontalWrap(&layoutProperties);
	BOOL horizontalWrap = horizontal && TiLayoutFlagsHasHorizontalWrap(&layoutProperties);
    NSMutableArray * measuredBounds = [NSMutableArray arrayWithCapacity:[childArray count]];
    NSUInteger i, count = [childArray count];
	int maxHeight = 0;
    
    NSMutableArray * widthFillChildren = horizontal?[NSMutableArray array]:nil;
    NSMutableArray * heightFillChildren = (vertical || horizontalWrap)?[NSMutableArray array]:nil;
    CGFloat widthNonFill = 0;
    CGFloat heightNonFill = 0;
    
    //First measure the sandbox bounds
    for (id child in childArray)
    {
        CGRect bounds = [self boundsForMeasureForChild:child];
        TiRect * childRect = [[TiRect alloc] init];
        CGRect childBounds = CGRectZero;
        
        if(![self absoluteLayout])
        {
            if (horizontalNoWrap) {
                if ([child wantsToFillHorizontalLayout])
                {
                    [widthFillChildren addObject:child];
                }
                else{
                    childBounds = [self computeChildSandbox:child withBounds:bounds];
                    maxHeight = MAX(maxHeight, childBounds.size.height);
                    widthNonFill += childBounds.size.width;
                }
            }
            else if (vertical) {
                if ([child wantsToFillVerticalLayout])
                {
                    [heightFillChildren addObject:child];
                }
                else{
                    childBounds = [self computeChildSandbox:child withBounds:bounds];
                    heightNonFill += childBounds.size.height;
                }
            }
            else {
                childBounds = [self computeChildSandbox:child withBounds:bounds];
            }
        }
        else {
            childBounds = bounds;
        }
        [childRect setRect:childBounds];
        [measuredBounds addObject:childRect];
        [childRect release];
    }
    //If it is a horizontal layout ensure that all the children in a row have the
    //same height for the sandbox
    
    int nbWidthAutoFill = [widthFillChildren count];
    if (nbWidthAutoFill > 0) {
        //it is horizontalNoWrap
        horizontalLayoutBoundary = 0;
        for (int i =0; i < [childArray count]; i++) {
            id child = [childArray objectAtIndex:i];
            CGRect bounds = [self boundsForMeasureForChild:child];
            CGFloat width = floorf((bounds.size.width - widthNonFill) / nbWidthAutoFill);
            if ([widthFillChildren containsObject:child]){
                CGRect usableRect = CGRectMake(0,0,width + horizontalLayoutBoundary, bounds.size.height);
                CGRect result = [self computeChildSandbox:child withBounds:usableRect];
                maxHeight = MAX(maxHeight, result.size.height);
                [(TiRect*)[measuredBounds objectAtIndex:i] setRect:result];
            }
            else {
                horizontalLayoutBoundary += [[(TiRect*)[measuredBounds objectAtIndex:i] width] floatValue];
            }
        }
    }
    
    int nbHeightAutoFill = [heightFillChildren count];
    if (nbHeightAutoFill > 0) {
        //it is vertical
        verticalLayoutBoundary = 0;
        for (int i =0; i < [childArray count]; i++) {
            id child = [childArray objectAtIndex:i];
            CGRect bounds = [self boundsForMeasureForChild:child];
            CGFloat height = floorf((bounds.size.height - heightNonFill) / nbHeightAutoFill);
            if ([heightFillChildren containsObject:child]){
                CGRect usableRect = CGRectMake(0,0,bounds.size.width, height + verticalLayoutBoundary);
                CGRect result = [self computeChildSandbox:child withBounds:usableRect];
                [(TiRect*)[measuredBounds objectAtIndex:i] setRect:result];
            }
            else {
                verticalLayoutBoundary += [[(TiRect*)[measuredBounds objectAtIndex:i] height] floatValue];
            }
        }
    }
	if (horizontalNoWrap)
	{
        int currentLeft = 0;
		for (i=0; i<count; i++)
		{
            [(TiRect*)[measuredBounds objectAtIndex:i] setX:[NSNumber numberWithInt:currentLeft]];
            currentLeft += [[(TiRect*)[measuredBounds objectAtIndex:i] width] integerValue];
			[(TiRect*)[measuredBounds objectAtIndex:i] setHeight:[NSNumber numberWithInt:maxHeight]];
		}
	}
    else if(vertical && (count > 1) )
    {
        int currentTop = 0;
		for (i=0; i<count; i++)
		{
            [(TiRect*)[measuredBounds objectAtIndex:i] setY:[NSNumber numberWithInt:currentTop]];
            currentTop += [[(TiRect*)[measuredBounds objectAtIndex:i] height] integerValue];
		}
    }
	else if(horizontal && (count > 1) )
    {
        int startIndex,endIndex, currentTop;
        startIndex = endIndex = maxHeight = currentTop = -1;
        for (i=0; i<count; i++)
        {
            CGRect childSandbox = (CGRect)[(TiRect*)[measuredBounds objectAtIndex:i] rect];
            if (startIndex == -1)
            {
                //FIRST ELEMENT
                startIndex = i;
                maxHeight = childSandbox.size.height;
                currentTop = childSandbox.origin.y;
            }
            else
            {
                if (childSandbox.origin.y != currentTop)
                {
                    //MOVED TO NEXT ROW
                    endIndex = i;
                    for (int j=startIndex; j<endIndex; j++)
                    {
                        [(TiRect*)[measuredBounds objectAtIndex:j] setHeight:[NSNumber numberWithInt:maxHeight]];
                    }
                    startIndex = i;
                    endIndex = -1;
                    maxHeight = childSandbox.size.height;
                    currentTop = childSandbox.origin.y;
                }
                else if (childSandbox.size.height > maxHeight)
                {
                    //SAME ROW HEIGHT CHANGED
                    maxHeight = childSandbox.size.height;
                }
            }
        }
        if (endIndex == -1)
        {
            //LAST ROW
            for (i=startIndex; i<count; i++)
            {
                [(TiRect*)[measuredBounds objectAtIndex:i] setHeight:[NSNumber numberWithInt:maxHeight]];
            }
        }
    }
    return measuredBounds;
}

-(CGRect)computeChildSandbox:(TiViewProxy*)child withBounds:(CGRect)bounds
{
    CGRect originalBounds = bounds;
    BOOL followsFillWBehavior = TiDimensionIsAutoFill([child defaultAutoWidthBehavior:nil]);
    BOOL followsFillHBehavior = TiDimensionIsAutoFill([child defaultAutoHeightBehavior:nil]);
    __block CGSize autoSize;
    __block BOOL autoSizeComputed = FALSE;
    __block CGFloat boundingWidth = bounds.size.width-horizontalLayoutBoundary;
    __block CGFloat boundingHeight = bounds.size.height-verticalLayoutBoundary;
    if (boundingHeight < 0) {
        boundingHeight = 0;
    }
    void (^computeAutoSize)() = ^() {
        if (autoSizeComputed == FALSE) {
            autoSize = [child minimumParentSizeForSize:CGSizeMake(bounds.size.width, boundingHeight)];
            autoSizeComputed = YES;
        }
    };
    
    CGFloat (^computeHeight)() = ^() {
        if ([child layoutProperties]->fullscreen == YES) return boundingHeight;
        //TOP + BOTTOM
        CGFloat offsetV = TiDimensionCalculateValue([child layoutProperties]->top, bounds.size.height)
        + TiDimensionCalculateValue([child layoutProperties]->bottom, bounds.size.height);
        TiDimension constraint = [child layoutProperties]->height;
        switch (constraint.type)
        {
            case TiDimensionTypePercent:
            case TiDimensionTypeDip:
            {
                return  TiDimensionCalculateValue(constraint, bounds.size.height) + offsetV;
            }
            case TiDimensionTypeAutoFill:
            {
                return boundingHeight;
            }
            case TiDimensionTypeUndefined:
            {
                if (!TiDimensionIsUndefined([child layoutProperties]->top) && !TiDimensionIsUndefined([child layoutProperties]->centerY) ) {
                    CGFloat height = 2 * ( TiDimensionCalculateValue([child layoutProperties]->centerY, boundingHeight) - TiDimensionCalculateValue([child layoutProperties]->top, boundingHeight) );
                    return height + offsetV;
                }
                else if (!TiDimensionIsUndefined([child layoutProperties]->top) && !TiDimensionIsUndefined([child layoutProperties]->bottom) ) {
                    return boundingHeight;
                }
                else if (!TiDimensionIsUndefined([child layoutProperties]->centerY) && !TiDimensionIsUndefined([child layoutProperties]->bottom) ) {
                    CGFloat height = 2 * ( boundingHeight - TiDimensionCalculateValue([child layoutProperties]->bottom, boundingHeight) - TiDimensionCalculateValue([child layoutProperties]->centerY, boundingHeight));
                    return height + offsetV;
                }
            }
            case TiDimensionTypeAuto:
            {
                if (followsFillHBehavior) {
                    //FILL behavior
                    return boundingHeight;
                }
            }
            default:
            case TiDimensionTypeAutoSize:
            {
                computeAutoSize();
                return autoSize.height; //offset is already in autoSize
            }
        }
    };
    
    if(TiLayoutRuleIsVertical(layoutProperties.layoutStyle))
    {
        bounds.origin.y = verticalLayoutBoundary;
        //LEFT + RIGHT
        CGFloat offsetH = TiDimensionCalculateValue([child layoutProperties]->left, bounds.size.width)
        + TiDimensionCalculateValue([child layoutProperties]->right, bounds.size.width);
        
        if ([child layoutProperties]->fullscreen == YES) {
            bounds.size.width = boundingWidth;
        }
        else {
            TiDimension constraint = [child layoutProperties]->width;
            switch (constraint.type)
            {
                case TiDimensionTypePercent:
                case TiDimensionTypeDip:
                {
                    bounds.size.width =  TiDimensionCalculateValue(constraint, bounds.size.width) + offsetH;
                    break;
                }
                case TiDimensionTypeAutoFill:
                {
                    bounds.size.width = boundingWidth;
                    break;
                }
                case TiDimensionTypeUndefined:
                {
                    if (!TiDimensionIsUndefined([child layoutProperties]->left) && !TiDimensionIsUndefined([child layoutProperties]->centerX) ) {
                        CGFloat width = 2 * ( TiDimensionCalculateValue([child layoutProperties]->centerX, bounds.size.width) - TiDimensionCalculateValue([child layoutProperties]->left, bounds.size.width) );
                        bounds.size.width = width + offsetH;
                    }
                    else if (!TiDimensionIsUndefined([child layoutProperties]->centerX) && !TiDimensionIsUndefined([child layoutProperties]->right) ) {
                        CGFloat w   = 2 * ( boundingWidth - TiDimensionCalculateValue([child layoutProperties]->right, bounds.size.width) - TiDimensionCalculateValue([child layoutProperties]->centerX, bounds.size.width));
                        bounds.size.width = autoSize.width + offsetH;
                        break;
                    }
                }
                case TiDimensionTypeAuto:
                {
                    if (followsFillWBehavior) {
                        bounds.size.width = boundingWidth;
                        break;
                    }
                }
                default:
                case TiDimensionTypeAutoSize:
                {
                    computeAutoSize();
                    bounds.size.width = autoSize.width; //offset is already in autoSize
                    break;
                }
            }
        }
        
        bounds.size.height = computeHeight();
        verticalLayoutBoundary += bounds.size.height;
    }
    else if(TiLayoutRuleIsHorizontal(layoutProperties.layoutStyle))
    {
		BOOL horizontalWrap = TiLayoutFlagsHasHorizontalWrap(&layoutProperties);
        BOOL followsFillBehavior = TiDimensionIsAutoFill([child defaultAutoWidthBehavior:nil]);
        bounds.size = [child sizeForAutoSize:bounds.size];
        
        //LEFT + RIGHT
        CGFloat offsetH = TiDimensionCalculateValue([child layoutProperties]->left, bounds.size.width)
        + TiDimensionCalculateValue([child layoutProperties]->right, bounds.size.width);
        //TOP + BOTTOM
        CGFloat offsetV = TiDimensionCalculateValue([child layoutProperties]->top, bounds.size.height)
        + TiDimensionCalculateValue([child layoutProperties]->bottom, bounds.size.height);
        
        
        CGFloat desiredWidth;
        BOOL recalculateWidth = NO;
        BOOL isPercent = NO;
        if ([child layoutProperties]->fullscreen == YES) {
            followsFillBehavior = YES;
            desiredWidth = boundingWidth;
        }
        else {
            TiDimension constraint = [child layoutProperties]->width;

            if (TiDimensionIsDip(constraint) || TiDimensionIsPercent(constraint))
            {
                desiredWidth =  TiDimensionCalculateValue(constraint, bounds.size.width) + offsetH;
                isPercent = TiDimensionIsPercent(constraint);
            }
            else if (followsFillBehavior && TiDimensionIsUndefined(constraint))
            {
                if (!TiDimensionIsUndefined([child layoutProperties]->left) && !TiDimensionIsUndefined([child layoutProperties]->centerX) ) {
                    desiredWidth = 2 * ( TiDimensionCalculateValue([child layoutProperties]->centerX, boundingWidth) - TiDimensionCalculateValue([child layoutProperties]->left, boundingWidth) );
                    desiredWidth += offsetH;
                }
                else if (!TiDimensionIsUndefined([child layoutProperties]->left) && !TiDimensionIsUndefined([child layoutProperties]->right) ) {
                    recalculateWidth = YES;
                    followsFillBehavior = YES;
                    desiredWidth = bounds.size.width;
                }
                else if (!TiDimensionIsUndefined([child layoutProperties]->centerX) && !TiDimensionIsUndefined([child layoutProperties]->right) ) {
                    desiredWidth = 2 * ( boundingWidth - TiDimensionCalculateValue([child layoutProperties]->right, boundingWidth) - TiDimensionCalculateValue([child layoutProperties]->centerX, boundingWidth));
                    desiredWidth += offsetH;
                }
                else {
                    recalculateWidth = YES;
                    computeAutoSize();
                    desiredWidth = autoSize.width;
                }
            }
            else if(TiDimensionIsAutoFill(constraint) || (TiDimensionIsAuto(constraint) && followsFillWBehavior)){
                followsFillBehavior = YES;
                desiredWidth = boundingWidth;
            }
            else {
                //This block takes care of auto,SIZE and FILL. If it is size ensure followsFillBehavior is set to false
                recalculateWidth = YES;
                computeAutoSize();
                desiredWidth = autoSize.width;
                followsFillBehavior = NO;
            }
        }
        
        bounds.size.height = computeHeight();
        
        if (horizontalWrap && (desiredWidth > boundingWidth)) {
            if (horizontalLayoutBoundary == 0.0) {
                //This is start of row
                bounds.origin.x = horizontalLayoutBoundary;
                bounds.origin.y = verticalLayoutBoundary;
                verticalLayoutBoundary += bounds.size.height;
                horizontalLayoutRowHeight = 0.0;
            }
            else {
                //This is not the start of row. Move to next row
                horizontalLayoutBoundary = 0.0;
                verticalLayoutBoundary += horizontalLayoutRowHeight;
                horizontalLayoutRowHeight = 0;
                bounds.origin.x = horizontalLayoutBoundary;
                bounds.origin.y = verticalLayoutBoundary;
                
                boundingWidth = originalBounds.size.width;
                boundingHeight = originalBounds.size.height - verticalLayoutBoundary;
                
                if (!recalculateWidth) {
                    if (desiredWidth < boundingWidth) {
                        horizontalLayoutBoundary += desiredWidth;
                        bounds.size.width = desiredWidth;
                        horizontalLayoutRowHeight = bounds.size.height;
                    }
                    else {
                        verticalLayoutBoundary += bounds.size.height;
                    }
                }
                else if (followsFillBehavior) {
                    
                    verticalLayoutBoundary += bounds.size.height;
                }
                else {
                    computeAutoSize();
                    desiredWidth = autoSize.width + offsetH;
                    if (desiredWidth < boundingWidth) {
                        
                        bounds.size.width = desiredWidth;
                        horizontalLayoutBoundary = bounds.size.width;
                        horizontalLayoutRowHeight = bounds.size.height;
                    }
                    else {
                        //fill whole space, another row again
                        verticalLayoutBoundary += bounds.size.height;
                    }
                }
                
            }
        }
        else {
            //If it fits update the horizontal layout row height
            bounds.origin.x = horizontalLayoutBoundary;
            bounds.origin.y = verticalLayoutBoundary;
            
            if (bounds.size.height > horizontalLayoutRowHeight) {
                horizontalLayoutRowHeight = bounds.size.height;
            }
            if (!recalculateWidth) {
                //DIP,PERCENT,UNDEFINED WITH ATLEAST 2 PINS one of them being centerX
                bounds.size.width = desiredWidth;
                horizontalLayoutBoundary += bounds.size.width;
            }
            else if(followsFillBehavior)
            {
                //FILL that fits in left over space. Move to next row
                bounds.size.width = boundingWidth;
				if (horizontalWrap) {
					horizontalLayoutBoundary = 0.0;
                	verticalLayoutBoundary += horizontalLayoutRowHeight;
					horizontalLayoutRowHeight = 0.0;
				} else {
					horizontalLayoutBoundary += bounds.size.width;
				}
            }
            else
            {
                //SIZE behavior
                bounds.size.width = desiredWidth;
                horizontalLayoutBoundary += bounds.size.width;
            }
        }
    }
    else {
        //        CGSize autoSize = [child minimumParentSizeForSize:bounds.size];
    }
    return bounds;
}

-(void)layoutChild:(TiViewProxy*)child optimize:(BOOL)optimize withMeasuredBounds:(CGRect)bounds
{
	IGNORE_IF_NOT_OPENED
	
	UIView * ourView = [self parentViewForChild:child];

	if (ourView==nil || [child isHidden])
	{
        [child clearItAll];
		return;
	}
	
	if (optimize==NO)
	{
		TiUIView *childView = [child view];
		TiUIView *parentView = (TiUIView*)[childView superview];
		if (parentView!=ourView)
		{
            [self insertSubview:childView forProxy:child];
		}
	}
	[child setSandboxBounds:bounds];
    [child dirtyItAll]; //for multileve recursion we need to make sure the child resizes itself
    if ([view runningAnimation]){
		[child setRunningAnimation:[self runningAnimation]];
		[child relayout];
		[child setRunningAnimation:nil];
    }
    else {
		[child relayout];
    }

	// tell our children to also layout
	[child layoutChildren:optimize];
}

-(void)layoutNonRealChild:(TiViewProxy*)child withParent:(UIView*)parentView
{
    CGRect bounds = [self computeChildSandbox:child withBounds:[parentView bounds]];
    [child setSandboxBounds:bounds];
    [child refreshViewIfNeeded];
}

-(void)layoutChildren:(BOOL)optimize
{
	IGNORE_IF_NOT_OPENED
	
	verticalLayoutBoundary = 0.0;
	horizontalLayoutBoundary = 0.0;
	horizontalLayoutRowHeight = 0.0;
	
	if (optimize==NO)
	{
		OSAtomicTestAndSetBarrier(TiRefreshViewChildrenPosition, &dirtyflags);
	}
    
    if (CGSizeEqualToSize([[self view] bounds].size, CGSizeZero)) return;
    
    if (childrenCount > 0)
    {
        //TODO: This is really expensive, but what can you do? Laying out the child needs the lock again.
        pthread_rwlock_rdlock(&childrenLock);
        NSArray * childrenArray = [[self visibleChildren] retain];
        pthread_rwlock_unlock(&childrenLock);
        
        NSUInteger childCount = [childrenArray count];
        if (childCount > 0) {
            NSArray * measuredBounds = [[self measureChildren:childrenArray] retain];
            NSUInteger childIndex;
            for (childIndex = 0; childIndex < childCount; childIndex++) {
                id child = [childrenArray objectAtIndex:childIndex];
                CGRect childSandBox = (CGRect)[(TiRect*)[measuredBounds objectAtIndex:childIndex] rect];
                [self layoutChild:child optimize:optimize withMeasuredBounds:childSandBox];
            }
            [measuredBounds release];
        }
        [childrenArray release];
    }


	
	if (optimize==NO)
	{
		OSAtomicTestAndClearBarrier(TiRefreshViewChildrenPosition, &dirtyflags);
	}
}


-(TiDimension)defaultAutoWidthBehavior:(id)unused
{
    return TiDimensionAutoFill;
}
-(TiDimension)defaultAutoHeightBehavior:(id)unused
{
    return TiDimensionAutoFill;
}

#pragma mark - Accessibility API

- (void)setAccessibilityLabel:(id)accessibilityLabel
{
	ENSURE_UI_THREAD(setAccessibilityLabel, accessibilityLabel);
	if ([self viewAttached]) {
		[[self view] setAccessibilityLabel_:accessibilityLabel];
	}
	[self replaceValue:accessibilityLabel forKey:@"accessibilityLabel" notification:NO];
}

- (void)setAccessibilityValue:(id)accessibilityValue
{
	ENSURE_UI_THREAD(setAccessibilityValue, accessibilityValue);
	if ([self viewAttached]) {
		[[self view] setAccessibilityValue_:accessibilityValue];
	}
	[self replaceValue:accessibilityValue forKey:@"accessibilityValue" notification:NO];
}

- (void)setAccessibilityHint:(id)accessibilityHint
{
	ENSURE_UI_THREAD(setAccessibilityHint, accessibilityHint);
	if ([self viewAttached]) {
		[[self view] setAccessibilityHint_:accessibilityHint];
	}
	[self replaceValue:accessibilityHint forKey:@"accessibilityHint" notification:NO];
}

- (void)setAccessibilityHidden:(id)accessibilityHidden
{
	ENSURE_UI_THREAD(setAccessibilityHidden, accessibilityHidden);
	if ([self viewAttached]) {
		[[self view] setAccessibilityHidden_:accessibilityHidden];
	}
	[self replaceValue:accessibilityHidden forKey:@"accessibilityHidden" notification:NO];
}

#pragma mark - View Templates

- (void)unarchiveFromTemplate:(id)viewTemplate_ withEvents:(BOOL)withEvents
{
	TiViewTemplate *viewTemplate = [TiViewTemplate templateFromViewTemplate:viewTemplate_];
	if (viewTemplate == nil) {
		return;
	}
	
	id<TiEvaluator> context = self.executionContext;
	if (context == nil) {
		context = self.pageContext;
	}
	
	[self _initWithProperties:viewTemplate.properties];
	if (withEvents && [viewTemplate.events count] > 0) {
		[context.krollContext invokeBlockOnThread:^{
			[viewTemplate.events enumerateKeysAndObjectsUsingBlock:^(NSString *eventName, NSArray *listeners, BOOL *stop) {
				[listeners enumerateObjectsUsingBlock:^(KrollWrapper *wrapper, NSUInteger idx, BOOL *stop) {
					[self addEventListener:[NSArray arrayWithObjects:eventName, wrapper, nil]];
				}];
			}];
		}];		
	}
	
	[viewTemplate.childTemplates enumerateObjectsUsingBlock:^(TiViewTemplate *childTemplate, NSUInteger idx, BOOL *stop) {
		TiViewProxy *child = [[self class] unarchiveFromTemplate:childTemplate inContext:context withEvents:withEvents];
		if (child != nil) {
			[context.krollContext invokeBlockOnThread:^{
				[self rememberProxy:child];
				[child forgetSelf];
			}];
			[self addInternal:child shouldRelayout:NO];
		}
	}];
}

// Returns protected proxy, caller should do forgetSelf.
+ (TiViewProxy *)unarchiveFromTemplate:(id)viewTemplate_ inContext:(id<TiEvaluator>)context withEvents:(BOOL)withEvents
{
	TiViewTemplate *viewTemplate = [TiViewTemplate templateFromViewTemplate:viewTemplate_];
	if (viewTemplate == nil) {
		return;
	}
	
	if (viewTemplate.type != nil) {
		TiViewProxy *proxy = [[self class] createProxy:viewTemplate.type withProperties:nil inContext:context];
		[context.krollContext invokeBlockOnThread:^{
			[context registerProxy:proxy];
			[proxy rememberSelf];
		}];
		[proxy unarchiveFromTemplate:viewTemplate withEvents:withEvents];
		return proxy;
	}
	return nil;
}


- (void)unarchiveFromDictionary:(NSDictionary*)dictionary rootProxy:(TiProxy*)rootProxy
{
	if (dictionary == nil) {
		return;
	}
	
	id<TiEvaluator> context = self.executionContext;
	if (context == nil) {
		context = self.pageContext;
	}
	NSDictionary* properties = (NSDictionary*)[dictionary objectForKey:@"properties"];
    if (properties == nil) properties = dictionary;
	[self _initWithProperties:properties];
    NSString* bindId = [dictionary objectForKey:@"bindId"];
    if (bindId) {
        [rootProxy setValue:self forKey:bindId];
    }
	NSDictionary* events = (NSDictionary*)[dictionary objectForKey:@"events"];
	if ([events count] > 0) {
		[context.krollContext invokeBlockOnThread:^{
			[events enumerateKeysAndObjectsUsingBlock:^(NSString *eventName, KrollCallback *listener, BOOL *stop) {
                [self addEventListener:[NSArray arrayWithObjects:eventName, listener, nil]];
			}];
		}];
	}
	NSArray* childTemplates = (NSArray*)[dictionary objectForKey:@"childTemplates"];
	
	[childTemplates enumerateObjectsUsingBlock:^(id childTemplate, NSUInteger idx, BOOL *stop) {
        TiViewProxy *child = nil;
        if ([childTemplate isKindOfClass:[NSDictionary class]]) {
            child = [[self class] unarchiveFromDictionary:childTemplate rootProxy:rootProxy inContext:context];
        }
        else if(([childTemplate isKindOfClass:[TiViewProxy class]]))
        {
            child = (TiViewProxy *)childTemplate;
        }
		if (child != nil) {
			[context.krollContext invokeBlockOnThread:^{
				[self rememberProxy:child];
				[child forgetSelf];
			}];
			[self addInternal:child shouldRelayout:NO];
		}
	}];
}

// Returns protected proxy, caller should do forgetSelf.
+ (TiViewProxy *)unarchiveFromDictionary:(NSDictionary*)dictionary rootProxy:(TiProxy*)rootProxy inContext:(id<TiEvaluator>)context
{
	if (dictionary == nil) {
		return nil;
	}
    NSString* type = [dictionary objectForKey:@"type"];
    
	if (type == nil) type = @"Ti.UI.View";
    TiViewProxy *proxy = [[self class] createProxy:type withProperties:nil inContext:context];
    [context.krollContext invokeBlockOnThread:^{
        [context registerProxy:proxy];
        [proxy rememberSelf];
    }];
    [proxy unarchiveFromDictionary:dictionary rootProxy:rootProxy];
    return proxy;
}

-(void)hideKeyboard:(id)arg
{
	ENSURE_UI_THREAD_1_ARG(arg);
	if (view != nil)
		[self.view endEditing:YES];
}

-(id)getNextChildrenOfClass:(Class)class afterChild:(TiViewProxy*)child
{
    pthread_rwlock_rdlock(&childrenLock);
    id result = nil;
    NSArray* subproxies = [self children];
    NSInteger index=[subproxies indexOfObject:child];
    if(NSNotFound != index) {
        for (int i = index + 1; i < [subproxies count] ; i++) {
            id obj = [subproxies objectAtIndex:i];
            if ([obj isKindOfClass:class]) {
                TiViewProxy* aview = (TiViewProxy*)obj;
                if([aview view].hidden == NO){
                    result = obj;
                    break;
                }
            }
        }
    }
	pthread_rwlock_unlock(&childrenLock);
    return result;
}

-(void)blur:(id)args
{
	ENSURE_UI_THREAD_1_ARG(args)
	if ([self viewAttached])
	{
		[[self view] endEditing:YES];
	}
}

-(void)focus:(id)args
{
	ENSURE_UI_THREAD_1_ARG(args)
	if ([self viewAttached])
	{
		[[self view] becomeFirstResponder];
	}
}

- (BOOL)focused:(id)unused
{
    return [self focused];
}

-(BOOL)focused
{
	BOOL result=NO;
	if ([self viewAttached])
	{
		result = [[self view] isFirstResponder];
	}
    
	return result;
}


-(void)handlePendingTransition
{
    if (_pendingTransition) {
        id args = _pendingTransition;
        _pendingTransition = nil;
        [self transitionViews:args];
        RELEASE_TO_NIL(args);
    }
}

-(void)transitionViews:(id)args
{
    
	ENSURE_UI_THREAD_1_ARG(args)
    if (_transitioning) {
        _pendingTransition = [args retain];
        return;
    }
    _transitioning = YES;
    if ([args count] > 1) {
        TiViewProxy *view1Proxy = nil;
        TiViewProxy *view2Proxy = nil;
        ENSURE_ARG_OR_NIL_AT_INDEX(view1Proxy, args, 0, TiViewProxy);
        ENSURE_ARG_OR_NIL_AT_INDEX(view2Proxy, args, 1, TiViewProxy);
        if ([self viewAttached])
        {
            if (view1Proxy != nil) {
                pthread_rwlock_wrlock(&childrenLock);
                if (![children containsObject:view1Proxy])
                {
                    pthread_rwlock_unlock(&childrenLock);
                    if (view2Proxy)[self add:view2Proxy];
                    _transitioning = NO;
                    [self handlePendingTransition];
                    return;
                }
            }
            NSDictionary* props = [args count] > 2 ? [args objectAtIndex:2] : nil;
            if (props == nil) {
                DebugLog(@"[WARN] Called transitionViews without transitionStyle");
            }
            pthread_rwlock_unlock(&childrenLock);
            
            TiUIView* view1 = nil;
            __block TiUIView* view2 = nil;
            if (view2Proxy) {
                [view2Proxy performBlockWithoutLayout:^{
                    [self determineSandboxBoundsForce]; //just in case
                    [view2Proxy setParent:self];
                    [self refreshViewOrParent];
                    [view2Proxy determineSandboxBoundsForce];
                    view2 = [view2Proxy getOrCreateView];
                    [view2Proxy windowWillOpen];
                    [view2Proxy windowDidOpen];
                    [view2Proxy dirtyItAll];
                    [view2Proxy refreshViewIfNeeded];
                }];
                
                id<TiEvaluator> context = self.executionContext;
                if (context == nil) {
                    context = self.pageContext;
                }
                [context.krollContext invokeBlockOnThread:^{
                    [self rememberProxy:view2Proxy];
                    [view2Proxy forgetSelf];
                }];
            }
            if (view1Proxy != nil) {
                view1 = [view1Proxy getOrCreateView];
            }
            
            TiTransition* transition = [TiTransitionHelper transitionFromArg:props containerView:self.view];
            transition.adTransition.type = ADTransitionTypePush;
            [[self view] transitionfromView:view1 toView:view2 withTransition:transition completionBlock:^{
                if (view1Proxy) [self remove:view1Proxy];
                if (view2Proxy) [self add:view2Proxy];
                _transitioning = NO;
                [self handlePendingTransition];
            }];
        }
        else {
            if (view1Proxy) [self remove:view1Proxy];
            if (view2Proxy)[self add:view2Proxy];
            _transitioning = NO;
            [self handlePendingTransition];
        }
	}
}


-(void)blurBackground:(id)args
{
    ENSURE_UI_THREAD_1_ARG(args)
    if ([self viewAttached]) {
        [[self view] blurBackground:args];
    }
}
-(void)configurationStart:(BOOL)recursive
{
    needsContentChange = allowContentChange = NO;
    [view configurationStart];
    if (recursive)[self makeChildrenPerformSelector:@selector(configurationStart:) withObject:recursive];
}

-(void)configurationStart
{
    [self configurationStart:NO];
}

-(void)configurationSet:(BOOL)recursive
{
    [view configurationSet];
    if (recursive)[self makeChildrenPerformSelector:@selector(configurationSet:) withObject:recursive];
    allowContentChange = YES;
}

-(void)configurationSet
{
    [self configurationSet:NO];
}

-(BOOL)containsView:(id)args
{
    ENSURE_SINGLE_ARG(args, TiViewProxy);
    if (args == self)return YES;
    if ([self viewAttached]) {
        NSArray* subproxies = [self children];
        for (TiViewProxy * thisChildProxy in subproxies)
        {
            if ([thisChildProxy containsView:args]) return YES;
        }
    }
    return NO;
}
@end
