//
//  LoopMeAdDisplayController.m
//  LoopMeSDK
//
//  Created by Dmitriy Lihachov on 8/21/12.
//  Copyright (c) 2013 LoopMe. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

#import "LoopMeAdDisplayController.h"
#import "LoopMeAdConfiguration.h"
#import "LoopMeAdWebView.h"
#import "LoopMeDefinitions.h"
#import "LoopMeDestinationDisplayController.h"
#import "LoopMeJSClient.h"
#import "LoopMeVideoClient.h"
#import "NSURL+LoopMeAdditions.h"
#import "LoopMeError.h"
#import "LoopMeLogging.h"

#import "LoopMe360ViewController.h"

NSInteger const kLoopMeWebViewLoadingTimeout = 180;
NSString * const kLoopMeShakeNotificationName = @"DeviceShaken";

@interface LoopMeAdDisplayController ()
<
    UIWebViewDelegate,
    LoopMeVideoClientDelegate,
    LoopMeJSClientDelegate,
    LoopMeDestinationDisplayControllerDelegate
>

@property (nonatomic, strong) LoopMeAdWebView *webView;
@property (nonatomic, strong) LoopMeJSClient *JSClient;
@property (nonatomic, strong) LoopMeVideoClient *videoClient;
@property (nonatomic, strong) LoopMeDestinationDisplayController *destinationDisplayClient;
@property (nonatomic, assign, getter = isShouldHandleRequests) BOOL shouldHandleRequests;
@property (nonatomic, strong) NSTimer *webViewTimeOutTimer;
@property (nonatomic, strong) LoopMeAdConfiguration *configuration;

@property (nonatomic, assign, getter=isFirstCallToExpand) BOOL firstCallToExpand;
@property (nonatomic, assign) CGPoint prevLoaction;
@property (nonatomic, strong) UIPanGestureRecognizer *panWebView;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchWebView;

- (void)deviceShaken;
- (BOOL)shouldIntercept:(NSURL *)URL
         navigationType:(UIWebViewNavigationType)navigationType;
- (void)interceptURL:(NSURL *)URL;

@end

@implementation LoopMeAdDisplayController

#pragma mark - Properties

- (LoopMeVideoClient *)videoClient
{
    if (_videoClient == nil) {
        _videoClient = [[LoopMeVideoClient alloc] initWithDelegate:self];
    }
    return _videoClient;
}

- (LoopMeDestinationDisplayController *)destinationDisplayClient {
    if (_destinationDisplayClient == nil) {
        _destinationDisplayClient = [LoopMeDestinationDisplayController controllerWithDelegate:self];
    }
    return _destinationDisplayClient;
}

- (void)setVisible:(BOOL)visible
{
    if (_visible != visible) {
        
        if (_forceHidden) {
            _visible = NO;
        } else {
            _visible = visible;
        }
        
        if (visible && !_forceHidden) {
            [self.JSClient executeEvent:LoopMeEvent.state forNamespace:kLoopMeNamespaceWebview param:LoopMeWebViewState.visible];
        } else {
            [self.JSClient executeEvent:LoopMeEvent.state forNamespace:kLoopMeNamespaceWebview param:LoopMeWebViewState.hidden];
        }
    }
}

- (void)setVisibleNoJS:(BOOL)visibleNoJS
{
    if (_visibleNoJS != visibleNoJS) {
        
        _visibleNoJS = visibleNoJS;
        if (_visibleNoJS) {
            [self.videoClient play];
        } else {
            [self.videoClient pause];
        }
    }
}

#pragma mark - Life Cycle

- (void)dealloc
{
    [_webView stopLoading];
    _webView.delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kLoopMeShakeNotificationName object:nil];
    [_webViewTimeOutTimer invalidate];
    _webViewTimeOutTimer = nil;
}

- (instancetype)initWithDelegate:(id<LoopMeAdDisplayControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _destinationDisplayClient = [LoopMeDestinationDisplayController controllerWithDelegate:self];
        _JSClient = [[LoopMeJSClient alloc] initWithDelegate:self];
        _webView = [[LoopMeAdWebView alloc] init];
        _webView.delegate = self;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(deviceShaken) name:kLoopMeShakeNotificationName object:nil];
        
        _firstCallToExpand = YES;
    }
    return self;
}

#pragma mark - Private

- (void)deviceShaken
{
    [self.JSClient setShake];
}

- (BOOL)shouldIntercept:(NSURL *)URL
         navigationType:(UIWebViewNavigationType)navigationType
{
    if (navigationType == UIWebViewNavigationTypeLinkClicked) {
        if ([self.delegate respondsToSelector:@selector(adDisplayControllerDidReceiveTap:)]) {
            [self.delegate adDisplayControllerDidReceiveTap:self];
        }
        return YES;
    }
    return NO;
}

- (void)interceptURL:(NSURL *)URL
{
    [self.destinationDisplayClient displayDestinationWithURL:URL];
}

- (void)cancelWebView
{
    [self.webView stopLoading];
    
    NSError *error = [LoopMeError errorForStatusCode:LoopMeErrorCodeHTMLRequestTimeOut];
    if ([self.delegate respondsToSelector:@selector(adDisplayController:didFailToLoadAdWithError:)]) {
        LoopMeLogInfo(@"Ad failed to load: %@", error);
        [self.delegate adDisplayController:self didFailToLoadAdWithError:error];
    }
}

- (void)panWebView:(UIPanGestureRecognizer *)recognizer
{
    CGPoint currentLocation = [recognizer locationInView:self.webView];
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.prevLoaction = currentLocation;
    }
    
    LoopMe360ViewController *vc = [self.videoClient viewController360];
    [vc pan:currentLocation prevLocation:self.prevLoaction];
    self.prevLoaction = currentLocation;
}

- (void)pinchWebView:(UIPinchGestureRecognizer *)recognizer
{
    LoopMe360ViewController *vc = [self.videoClient viewController360];
    [vc handlePinchGesture:recognizer];
}
#pragma mark - Public

- (void)loadConfiguration:(LoopMeAdConfiguration *)configuration
{
    self.configuration = configuration;
    self.shouldHandleRequests = YES;
    [self.webView loadHTMLString:configuration.adResponseHTMLString
                         baseURL:nil];
    self.webViewTimeOutTimer = [NSTimer scheduledTimerWithTimeInterval:kLoopMeWebViewLoadingTimeout target:self selector:@selector(cancelWebView) userInfo:nil repeats:NO];
}

- (void)displayAd
{
    self.videoClient.viewController = [self.delegate viewControllerForPresentation];
    self.webView.frame = self.delegate.containerView.bounds;
    
    CGRect adjustedFrame = self.webView.frame;

    if ((self.configuration.orientation == LoopMeAdOrientationLandscape && adjustedFrame.size.width < adjustedFrame.size.height) || (self.configuration.orientation == LoopMeAdOrientationPortrait && adjustedFrame.size.width > adjustedFrame.size.height)) {
        adjustedFrame = CGRectMake(adjustedFrame.origin.x, adjustedFrame.origin.y, adjustedFrame.size.height, adjustedFrame.size.width);
    }
    
    [self.videoClient adjustViewToFrame:adjustedFrame];
    [self.delegate.containerView addSubview:self.webView];
    [self.delegate.containerView bringSubviewToFront:self.webView];
    [self.videoClient willAppear];
    
    
    self.panWebView = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panWebView:)];
    [self.webView addGestureRecognizer:self.panWebView];
    
    self.pinchWebView = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchWebView:)];
    [self.webView addGestureRecognizer:self.pinchWebView];
}

- (void)closeAd
{
    [self stopHandlingRequests];
    self.visible = NO;
    [self.webView removeGestureRecognizer:self.panWebView];
    [self.webView removeGestureRecognizer:self.pinchWebView];
    [self.JSClient executeEvent:LoopMeEvent.state forNamespace:kLoopMeNamespaceWebview param:LoopMeWebViewState.closed];
}

- (void)layoutSubviews
{
    [self.videoClient adjustViewToFrame:self.webView.bounds];
}

- (void)layoutSubviewsToFrame:(CGRect)frame
{
    [self.videoClient adjustViewToFrame:frame];
}

- (void)stopHandlingRequests
{
    self.shouldHandleRequests = NO;
    [self.destinationDisplayClient cancel];
    self.destinationDisplayClient = nil;
    [self.videoClient cancel];
    self.videoClient = nil;
    self.destinationDisplayClient = nil;
    [self.webView stopLoading];
    [self.webViewTimeOutTimer invalidate];
}

- (void)continueHandlingRequests
{
    self.shouldHandleRequests = YES;
}

- (void)moveView:(BOOL)hideWebView
{
    [self.videoClient moveView];
    [self displayAd];
    self.webView.hidden = hideWebView;
}

- (void)expandReporting
{
    [self.JSClient setFullScreenModeEnabled:YES];
}

- (void)collapseReporting
{
    [self.JSClient setFullScreenModeEnabled:NO];
}

#pragma mark - UIWebViewDelegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request
 navigationType:(UIWebViewNavigationType)navigationType
{
    if (!self.isShouldHandleRequests) {
        return NO;
    }
    NSURL *URL = [request URL];
    if ([self.JSClient shouldInterceptURL:URL]) {
        [self.JSClient executeEvent:LoopMeEvent.isNativeCallFinished forNamespace:kLoopMeNamespaceWebview param:@YES paramBOOL:YES];
        [self.JSClient processURL:URL];
        return NO;
    } else if ([self shouldIntercept:URL navigationType:navigationType]) {
        [self interceptURL:URL];
        return NO;
    }
    return YES;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    LoopMeLogDebug(@"WebView received an error %@", error);
    if (error.code == -1004) {
        if ([self.delegate respondsToSelector:@selector(adDisplayController:didFailToLoadAdWithError:)]) {
            [self.delegate adDisplayController:self didFailToLoadAdWithError:error];
        }
    }
}

#pragma mark - LoopMeDestinationDisplayControllerDelegate

- (UIViewController *)viewControllerForPresentingModalView
{
    return [self.delegate viewControllerForPresentation];
}

- (void)destinationDisplayControllerWillLeaveApplication:(LoopMeDestinationDisplayController *)destinationDisplayController
{
    if ([self.delegate respondsToSelector:@selector(adDisplayControllerWillLeaveApplication:)]) {
        [self.delegate adDisplayControllerWillLeaveApplication:self];
    }
}

- (void)destinationDisplayControllerWillPresentModal:(LoopMeDestinationDisplayController *)destinationDisplayController
{
    self.visible = NO;
    self.destinationIsPresented = YES;
}

- (void)destinationDisplayControllerDidDismissModal:(LoopMeDestinationDisplayController *)destinationDisplayController
{
    if ([self.delegate respondsToSelector:@selector(adDisplayControllerDidDismissModal:)]) {
        [self.delegate adDisplayControllerDidDismissModal:self];
    }
    self.destinationIsPresented = NO;
}

#pragma mark - JSClientDelegate 

- (UIWebView *)webViewTransport
{
    return self.webView;
}

- (id<LoopMeVideoCommunicatorProtocol>)videoCommunicator
{
    return self.videoClient;
}

- (void)JSClientDidReceiveSuccessCommand:(LoopMeJSClient *)client
{
    LoopMeLogInfo(@"Ad was successfully loaded");
    [self.webViewTimeOutTimer invalidate];
    _webViewTimeOutTimer = nil;
    if ([self.delegate respondsToSelector:@selector(adDisplayControllerDidFinishLoadingAd:)]) {
        [self.delegate adDisplayControllerDidFinishLoadingAd:self];
    }
}

- (void)JSClientDidReceiveFailCommand:(LoopMeJSClient *)client
{
    NSError *error = [LoopMeError errorForStatusCode:LoopMeErrorCodeSpecificHost];
    LoopMeLogInfo(@"Ad failed to load: %@", error);
    [self.webViewTimeOutTimer invalidate];
    _webViewTimeOutTimer = nil;
    if ([self.delegate respondsToSelector:@selector(adDisplayController:didFailToLoadAdWithError:)]) {
        [self.delegate adDisplayController:self didFailToLoadAdWithError:error];
    }
}

- (void)JSClientDidReceiveCloseCommand:(LoopMeJSClient *)client
{
    if ([self.delegate respondsToSelector:@selector(adDisplayControllerShouldCloseAd:)]) {
        [self.delegate adDisplayControllerShouldCloseAd:self];
    }
}

- (void)JSClientDidReceiveVibrateCommand:(LoopMeJSClient *)client
{
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)JSClientDidReceiveFulLScreenCommand:(LoopMeJSClient *)client fullScreen:(BOOL)expand
{
 
    if (self.isFirstCallToExpand) {
        expand = NO;
        self.firstCallToExpand = NO;
    }
    
    if (expand) {
        if ([self.delegate respondsToSelector:@selector(adDisplayControllerWillExpandAd:)]) {
            [self.videoClient setGravity:AVLayerVideoGravityResizeAspect];
            [self.delegate adDisplayControllerWillExpandAd:self];
        }
    } else {
        if ([self.delegate respondsToSelector:@selector(adDisplayControllerWillCollapse:)]) {
            [self.delegate adDisplayControllerWillCollapse:self];
        }
    }
}

#pragma mark - VideoClientDelegate

- (id<LoopMeJSCommunicatorProtocol>)JSCommunicator
{
    return self.JSClient;
}

- (void)videoClientDidReachEnd:(LoopMeVideoClient *)client
{
    LoopMeLogInfo(@"Video ad did reach end");
    if ([self.delegate respondsToSelector:
         @selector(adDisplayControllerVideoDidReachEnd:)]) {
        [self.delegate adDisplayControllerVideoDidReachEnd:self];
    }
}

- (void)videoClient:(LoopMeVideoClient *)client didFailToLoadVideoWithError:(NSError *)error
{
    LoopMeLogInfo(@"Did fail to load video ad");
    if ([self.delegate respondsToSelector:
         @selector(adDisplayController:didFailToLoadAdWithError:)]) {
        [self.delegate adDisplayController:self didFailToLoadAdWithError:error];
    }
}

- (void)videoClient:(LoopMeVideoClient *)client setupView:(UIView *)view
{
    view.frame = self.delegate.containerView.bounds;
    [[self.delegate containerView] insertSubview:view belowSubview:self.webView];
}

@end
