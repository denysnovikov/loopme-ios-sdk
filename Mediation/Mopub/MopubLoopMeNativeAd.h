//
//  LoopMeNativeAd.h
//  LoopMeMediatonDemo
//
//  Created by Dmitriy on 7/29/15.
//  Copyright (c) 2015 injectios. All rights reserved.
//

#import "MPNativeAd.h"
#import "LoopMeAdView.h"
#import "LoopMeInterstitial.h"

@interface MopubLoopMeNativeAd : MPNativeAd

@property (nonatomic, strong) LoopMeAdView *adView;

@end