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


#import <Foundation/Foundation.h>
#import "MSIDThrottlingModelFactory.h"
#import "MSIDThrottlingCacheRecord.h"
#import "MSIDLRUCache.h"
#import "MSIDThrottlingModelBase.h"
#import "MSIDThrottlingModelInteractionRequire.h"
#import "MSIDThrottlingModel429.h"

@implementation MSIDThrottlingModelFactory

+ (MSIDThrottlingModelBase *)throttlingModelForIncomingRequest:(id<MSIDThumbprintCalculatable> _Nonnull)request
                                                   accessGroup:(NSString *)accessGroup
                                                       context:(id<MSIDRequestContext> _Nonnull)context
{
    if (![MSIDThrottlingModelFactory validateInput:request]) return nil;
    NSError *error;
    MSIDThrottlingCacheRecord *cacheRecord = [MSIDThrottlingModelFactory getDBRecordWithStrictThumbprint:request.strictRequestThumbprint
                                                                                          fullThumbprint:request.fullRequestThumbprint                     error:&error];
    if(!cacheRecord) return nil;
    return [self generateModelFromErrorResponse:nil
                                        request:request
                                   throttleType:cacheRecord.throttleType
                                    cacheRecord:cacheRecord
                                    accessGroup:accessGroup];
}

+ (MSIDThrottlingModelBase *)throttlingModelForResponseWithRequest:(id<MSIDThumbprintCalculatable> _Nonnull)request
                                                       accessGroup:(NSString *)accessGroup
                                                     errorResponse:(NSError *)errorResponse
                                                           context:(id<MSIDRequestContext>)context
{
    NSError *localError = nil;
    MSIDThrottlingType throttleType = [MSIDThrottlingModelFactory processErrorResponseToGetThrottleType:errorResponse
                                                                                                  error:&localError];
    if(throttleType == MSIDThrottlingTypeNone) return nil;
    return [self generateModelFromErrorResponse:errorResponse
                                        request:request
                                   throttleType:throttleType
                                    cacheRecord:nil
                                    accessGroup:accessGroup];
}

+ (MSIDThrottlingModelBase *)generateModelFromErrorResponse:(NSError * _Nullable)errorResponse
                                                    request:(id<MSIDThumbprintCalculatable>)request
                                               throttleType:(MSIDThrottlingType)throttleType
                                                cacheRecord:(MSIDThrottlingCacheRecord * _Nullable)cacheRecord
                                                accessGroup:(NSString *)accessGroup
{
    if(throttleType == MSIDThrottlingType429)
    {
        return [[MSIDThrottlingModel429 alloc] initWithRequest:request cacheRecord:cacheRecord errorResponse:errorResponse accessGroup:accessGroup];
    }
    else
    {
        return [[MSIDThrottlingModelInteractionRequire alloc] initWithRequest:request cacheRecord:cacheRecord errorResponse:errorResponse accessGroup:accessGroup];
    }
}

+ (MSIDThrottlingType)processErrorResponseToGetThrottleType:(NSError *)errorResponse
                                                      error:(NSError *_Nullable *_Nullable)error
{
    
    MSIDThrottlingType throttleType = MSIDThrottlingTypeNone;
    if ([MSIDThrottlingModel429 isApplicableForTheThrottleModel:errorResponse])
    {
        throttleType = MSIDThrottlingType429;
        return throttleType;
    }
    
    if ([MSIDThrottlingModelInteractionRequire isApplicableForTheThrottleModel:errorResponse])
    {
        throttleType = MSIDThrottlingTypeInteractiveRequired;
        return throttleType;
    }
    
    return throttleType;
}


+ (BOOL)validateInput:(id<MSIDThumbprintCalculatable> _Nonnull)request
{
    return (request.fullRequestThumbprint || request.strictRequestThumbprint);
}


+ (MSIDThrottlingCacheRecord *)getDBRecordWithStrictThumbprint:(NSString *)strictThumbprint
                                                fullThumbprint:(NSString *)fullThumbprint
                                                         error:(NSError **)error
{
    MSIDThrottlingCacheRecord *cacheRecord = [self.cacheService objectForKey:strictThumbprint
                                                                       error:error];
    if (!cacheRecord)
    {
        cacheRecord = [self.cacheService objectForKey:fullThumbprint error:error];
    }
    return cacheRecord;
}

+ (MSIDLRUCache *)cacheService
{
    static MSIDLRUCache *cacheService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cacheService = [[MSIDLRUCache alloc] initWithCacheSize:1000];
    });
    return cacheService;
}

@end
