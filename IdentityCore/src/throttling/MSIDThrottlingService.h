//
// Copyright (c) Microsoft Corporation.
// All rights reserved.
//
// This code is licensed under the MIT License.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "MSIDRequestContext.h"
#import "MSIDThumbprintCalculatable.h"
#import "MSIDThrottlingCacheRecord.h"
#import "MSIDTokenResponse.h"

typedef void (^MSIDThrottleResultBlock)(BOOL shouldBeThrottled, NSError * _Nullable error);

@interface MSIDThrottlingService : NSObject

- (instancetype _Nonnull)initWithAccessGroup:(NSString * _Nullable)accessGroup
                                     context:(id<MSIDRequestContext> _Nonnull)context;

- (void)shouldThrottleRequest:(id<MSIDThumbprintCalculatable> _Nonnull)request
                  resultBlock:(nonnull MSIDThrottleResultBlock)resultBlock;

- (void)updateThrottlingService:(NSError * _Nonnull)error
                   tokenRequest:(id<MSIDThumbprintCalculatable> _Nonnull)tokenRequest;

+ (BOOL)updateLastRefreshTimeAccessGroup:(NSString * _Nullable)accessGroup
                                 context:(id<MSIDRequestContext>_Nullable)context
                                   error:(NSError*__nullable*__nullable)error;

@end
