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

#import <XCTest/XCTest.h>
#import "MSIDInteractiveTokenRequest.h"
#import "MSIDInteractiveTokenRequestParameters.h"
#import "MSIDAADV2Oauth2Factory.h"
#import "MSIDDefaultTokenResponseValidator.h"
#import "MSIDDefaultTokenCacheAccessor.h"
#import "MSIDKeychainTokenCache.h"
#import "MSIDTestSwizzle.h"
#import "MSIDWebviewAuthorization.h"
#import "MSIDWebAADAuthCodeResponse.h"
#import "MSIDTestURLResponse+Util.h"
#import "NSDictionary+MSIDTestUtil.h"
#import "MSIDTestIdTokenUtil.h"
#import "MSIDTestURLSession.h"
#import "MSIDTokenResult.h"
#import "MSIDAccount.h"
#import "MSIDAccountIdentifier.h"
#import "MSIDAccessToken.h"
#import "MSIDRefreshToken.h"
#import "MSIDAuthority+Internal.h"
#import "MSIDWebWPJResponse.h"
#import "MSIDTestIdentifiers.h"
#if TARGET_OS_IPHONE
#import "MSIDApplicationTestUtil.h"
#endif
#import "MSIDWebOpenBrowserResponse.h"
#import "MSIDAADNetworkConfiguration.h"
#import "MSIDAadAuthorityCache.h"
#import "MSIDAccountMetadataCacheAccessor.h"
#import "NSString+MSIDTestUtil.h"
#import "MSIDWebAADAuthCodeResponse.h"

@interface MSIDDefaultInteractiveTokenRequestTests : XCTestCase

@end

@implementation MSIDDefaultInteractiveTokenRequestTests

#pragma mark - Helpers

- (MSIDDefaultTokenCacheAccessor *)tokenCache
{
    id<MSIDExtendedTokenCacheDataSource> dataSource = [[MSIDKeychainTokenCache alloc] initWithGroup:@"com.microsoft.adalcache" error:nil];
    MSIDDefaultTokenCacheAccessor *tokenCache = [[MSIDDefaultTokenCacheAccessor alloc] initWithDataSource:dataSource otherCacheAccessors:nil];
    return tokenCache;
}

- (MSIDAccountMetadataCacheAccessor *)metadataCache
{
    id<MSIDMetadataCacheDataSource> dataSource = [[MSIDKeychainTokenCache alloc] initWithGroup:@"com.microsoft.adalcache" error:nil];
    MSIDAccountMetadataCacheAccessor *metadataCache = [[MSIDAccountMetadataCacheAccessor alloc] initWithDataSource:dataSource];
    return metadataCache;
}

- (void)setUp
{
    [super setUp];
    [MSIDAADNetworkConfiguration.defaultConfiguration setValue:@"v2.0" forKey:@"aadApiVersion"];
    MSIDKeychainTokenCache *cache = [[MSIDKeychainTokenCache alloc] initWithGroup:@"com.microsoft.adalcache" error:nil];
    [cache clearWithContext:nil error:nil];
}

- (void)tearDown
{
    [[MSIDAadAuthorityCache sharedInstance] removeAllObjects];
    [[MSIDAuthority openIdConfigurationCache] removeAllObjects];
    XCTAssertTrue([MSIDTestURLSession noResponsesLeft]);
    [MSIDAADNetworkConfiguration.defaultConfiguration setValue:nil forKey:@"aadApiVersion"];
    [super tearDown];
}

#pragma mark - Tests

- (void)testInteractiveRequestFlow_whenValid_shouldReturnResultWithNoError
{
    __block NSUUID *correlationId = [NSUUID new];

    MSIDInteractiveTokenRequestParameters *parameters = [MSIDInteractiveTokenRequestParameters new];
    parameters.target = @"fakescope1 fakescope2";
    parameters.authority = [@"https://login.microsoftonline.com/common" aadAuthority];
    parameters.redirectUri = @"x-msauth-test://com.microsoft.testapp";
    parameters.clientId = @"my_client_id";
    parameters.extraAuthorizeURLQueryParameters = @{ @"eqp1" : @"val1", @"eqp2" : @"val2" };
    parameters.loginHint = @"fakeuser@contoso.com";
    parameters.correlationId = correlationId;
    parameters.webviewType = MSIDWebviewTypeWKWebView;
    parameters.extraScopesToConsent = @"fakescope3";
    parameters.oidcScope = @"openid profile offline_access";
    parameters.promptType = MSIDPromptTypeConsent;
    parameters.authority.openIdConfigurationEndpoint = [NSURL URLWithString:@"https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration"];
    parameters.accountIdentifier = [[MSIDAccountIdentifier alloc] initWithDisplayableId:@"user@contoso.com" homeAccountId:DEFAULT_TEST_HOME_ACCOUNT_ID];
    parameters.enablePkce = YES;

    MSIDInteractiveTokenRequest *request = [[MSIDInteractiveTokenRequest alloc] initWithRequestParameters:parameters
                                                                                             oauthFactory:[MSIDAADV2Oauth2Factory new] tokenResponseValidator:[MSIDDefaultTokenResponseValidator new]
                                                                                               tokenCache:self.tokenCache accountMetadataCache:self.metadataCache extendedTokenCache:nil];

    XCTAssertNotNil(request);

    // Swizzle out the main entry point for WebUI, WebUI is tested in its own component tests
    [MSIDTestSwizzle classMethod:@selector(startSessionWithWebView:oauth2Factory:configuration:context:completionHandler:)
                           class:[MSIDWebviewAuthorization class]
                           block:(id)^(
                                __unused id obj,
                                __unused NSObject<MSIDWebviewInteracting> *webview,
                                __unused MSIDOauth2Factory *oauth2Factory,
                                __unused MSIDBaseWebRequestConfiguration *configuration,
                                __unused id<MSIDRequestContext> context,
                                MSIDWebviewAuthCompletionHandler completionHandler)
    {
         NSString *responseString = [NSString stringWithFormat:@"x-msauth-test://com.microsoft.testapp?code=iamafakecode&client_info=%@", [@{ @"uid" : @"1", @"utid" : @"1234-5678-90abcdefg"} msidBase64UrlJson]];

         MSIDWebAADAuthCodeResponse *oauthResponse = [[MSIDWebAADAuthCodeResponse alloc] initWithURL:[NSURL URLWithString:responseString]
                                                                                             context:nil error:nil];
         completionHandler(oauthResponse, nil);
     }];

    NSMutableDictionary *reqHeaders = [[MSIDTestURLResponse msidDefaultRequestHeaders] mutableCopy];
    [reqHeaders setObject:@"application/x-www-form-urlencoded" forKey:@"Content-Type"];

    NSString *url = @"https://login.microsoftonline.com/common/oauth2/v2.0/token";

    MSIDTestURLResponse *response =
    [MSIDTestURLResponse requestURLString:url
                           requestHeaders:reqHeaders
                        requestParamsBody:@{ @"code" : @"iamafakecode",
                                             @"client_id" : @"my_client_id",
                                             @"scope" : @"fakescope1 fakescope2 openid profile offline_access",
                                             @"redirect_uri" : @"x-msauth-test://com.microsoft.testapp",
                                             @"grant_type" : @"authorization_code",
                                             @"code_verifier" : [MSIDTestRequireValueSentinel sentinel],
                                             @"client_info" : @"1"}
                        responseURLString:@"https://login.microsoftonline.com/common/oauth2/v2.0/token"
                             responseCode:200
                         httpHeaderFields:nil
                         dictionaryAsJSON:@{ @"access_token" : @"i am a access token!",
                                             @"expires_in" : @"600",
                                             @"refresh_token" : @"i am a refresh token",
                                             @"id_token" : [MSIDTestIdTokenUtil defaultV2IdToken],
                                             @"id_token_expires_in" : @"1200",
                                             @"client_info" : [@{ @"uid" : @"1", @"utid" : @"1234-5678-90abcdefg"} msidBase64UrlJson],
                                             @"scope": @"fakescope1 fakescope2 openid profile offline_access"
                                             }];

    [response->_requestHeaders removeObjectForKey:@"Content-Length"];

    [MSIDTestURLSession addResponse:response];

    NSString *authority = @"https://login.microsoftonline.com/common";
    MSIDTestURLResponse *discoveryResponse = [MSIDTestURLResponse discoveryResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:discoveryResponse];

    MSIDTestURLResponse *oidcResponse = [MSIDTestURLResponse oidcResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:oidcResponse];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Run request."];

    [request executeRequestWithCompletion:^(MSIDTokenResult * _Nullable result, NSError * _Nullable error, MSIDWebWPJResponse * _Nullable installBrokerResponse) {

        XCTAssertNotNil(result);
        XCTAssertNil(error);
        XCTAssertNotNil(result.account);
        XCTAssertEqualObjects(result.account.accountIdentifier.homeAccountId, @"1.1234-5678-90abcdefg");
        XCTAssertEqualObjects(result.account.name, [MSIDTestIdTokenUtil defaultName]);
        XCTAssertEqualObjects(result.account.username, [MSIDTestIdTokenUtil defaultUsername]);
        XCTAssertEqualObjects(result.accessToken.accessToken, @"i am a access token!");
        XCTAssertEqualObjects(result.rawIdToken, [MSIDTestIdTokenUtil defaultV2IdToken]);
        XCTAssertFalse(result.extendedLifeTimeToken);
        XCTAssertEqualObjects(result.authority.url.absoluteString, DEFAULT_TEST_AUTHORITY_GUID);
        XCTAssertNil(installBrokerResponse);
        XCTAssertNil(error);

        [expectation fulfill];

    }];

    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testInteractiveRequestFlow_whenValidWithCloudHostName_shouldReturnResultWithNoErrorAndCorrectAuthority
{
    __block NSUUID *correlationId = [NSUUID new];

    MSIDInteractiveTokenRequestParameters *parameters = [MSIDInteractiveTokenRequestParameters new];
    parameters.target = @"fakescope1 fakescope2";
    parameters.authority = [@"https://login.microsoftonline.com/common" aadAuthority];
    parameters.redirectUri = @"x-msauth-test://com.microsoft.testapp";
    parameters.clientId = @"my_client_id";
    parameters.extraAuthorizeURLQueryParameters = @{ @"eqp1" : @"val1", @"eqp2" : @"val2", @"instance_aware" : @"true" };
    parameters.loginHint = @"fakeuser@contoso.com";
    parameters.correlationId = correlationId;
    parameters.webviewType = MSIDWebviewTypeWKWebView;
    parameters.extraScopesToConsent = @"fakescope3";
    parameters.oidcScope = @"openid profile offline_access";
    parameters.promptType = MSIDPromptTypeConsent;
    parameters.authority.openIdConfigurationEndpoint = [NSURL URLWithString:@"https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration"];
    parameters.accountIdentifier = [[MSIDAccountIdentifier alloc] initWithDisplayableId:@"user@contoso.com" homeAccountId:@"1.1234-5678-90abcdefg"];
    parameters.enablePkce = YES;

    MSIDInteractiveTokenRequest *request = [[MSIDInteractiveTokenRequest alloc] initWithRequestParameters:parameters oauthFactory:[MSIDAADV2Oauth2Factory new] tokenResponseValidator:[MSIDDefaultTokenResponseValidator new] tokenCache:self.tokenCache accountMetadataCache:self.metadataCache extendedTokenCache:nil];

    XCTAssertNotNil(request);

    // Swizzle out the main entry point for WebUI, WebUI is tested in its own component tests
    [MSIDTestSwizzle classMethod:@selector(startSessionWithWebView:oauth2Factory:configuration:context:completionHandler:)
                           class:[MSIDWebviewAuthorization class]
                           block:(id)^(
                                __unused id obj,
                                __unused NSObject<MSIDWebviewInteracting> *webview,
                                __unused MSIDOauth2Factory *oauth2Factory,
                                __unused MSIDBaseWebRequestConfiguration *configuration,
                                __unused id<MSIDRequestContext> context,
                                MSIDWebviewAuthCompletionHandler completionHandler)
    {
         NSString *responseString = [NSString stringWithFormat:@"x-msauth-test://com.microsoft.testapp?code=iamafakecode&cloud_instance_host_name=contoso.onmicrosoft.cn&client_info=%@", [@{ @"uid" : @"1", @"utid" : @"1234-5678-90abcdefg"} msidBase64UrlJson]];

         MSIDWebAADAuthCodeResponse *oauthResponse = [[MSIDWebAADAuthCodeResponse alloc] initWithURL:[NSURL URLWithString:responseString]
                                                                                             context:nil error:nil];
         completionHandler(oauthResponse, nil);
     }];

    NSMutableDictionary *reqHeaders = [[MSIDTestURLResponse msidDefaultRequestHeaders] mutableCopy];
    [reqHeaders setObject:@"application/x-www-form-urlencoded" forKey:@"Content-Type"];

    NSString *url = @"https://contoso.onmicrosoft.cn/common/oauth2/v2.0/token";
    
    MSIDTestURLResponse *response =
    [MSIDTestURLResponse requestURLString:url
                           requestHeaders:reqHeaders
                        requestParamsBody:@{ @"code" : @"iamafakecode",
                                             @"client_id" : @"my_client_id",
                                             @"scope" : @"fakescope1 fakescope2 openid profile offline_access",
                                             @"redirect_uri" : @"x-msauth-test://com.microsoft.testapp",
                                             @"grant_type" : @"authorization_code",
                                             @"code_verifier" : [MSIDTestRequireValueSentinel sentinel],
                                             @"client_info" : @"1"}
                        responseURLString:@"https://contoso.onmicrosoft.cn/oauth2/v2.0/token"
                             responseCode:200
                         httpHeaderFields:nil
                         dictionaryAsJSON:@{ @"access_token" : @"i am a access token!",
                                             @"expires_in" : @"600",
                                             @"refresh_token" : @"i am a refresh token",
                                             @"id_token" : [MSIDTestIdTokenUtil defaultV2IdToken],
                                             @"id_token_expires_in" : @"1200",
                                             @"client_info" : [@{ @"uid" : @"1", @"utid" : @"1234-5678-90abcdefg"} msidBase64UrlJson],
                                             @"scope": @"fakescope1 fakescope2 openid profile offline_access"
                                             }];

    [response->_requestHeaders removeObjectForKey:@"Content-Length"];

    [MSIDTestURLSession addResponse:response];

    NSString *wwAuthority = @"https://login.microsoftonline.com/common";

    MSIDTestURLResponse *discoveryResponse = [MSIDTestURLResponse discoveryResponseForAuthority:wwAuthority];
    [MSIDTestURLSession addResponse:discoveryResponse];

    MSIDTestURLResponse *wwOidcResponse = [MSIDTestURLResponse oidcResponseForAuthority:wwAuthority];
    [MSIDTestURLSession addResponse:wwOidcResponse];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Run request."];

    [request executeRequestWithCompletion:^(MSIDTokenResult * _Nullable result, NSError * _Nullable error, MSIDWebWPJResponse * _Nullable installBrokerResponse) {

        XCTAssertNotNil(result);
        XCTAssertNil(error);
        XCTAssertNotNil(result.account);
        XCTAssertEqualObjects(result.account.accountIdentifier.homeAccountId, @"1.1234-5678-90abcdefg");
        XCTAssertEqualObjects(result.account.name, [MSIDTestIdTokenUtil defaultName]);
        XCTAssertEqualObjects(result.account.username, [MSIDTestIdTokenUtil defaultUsername]);
        XCTAssertEqualObjects(result.accessToken.accessToken, @"i am a access token!");
        XCTAssertEqualObjects(result.rawIdToken, [MSIDTestIdTokenUtil defaultV2IdToken]);
        XCTAssertFalse(result.extendedLifeTimeToken);
        XCTAssertEqualObjects(result.authority.url.absoluteString, @"https://contoso.onmicrosoft.cn/"DEFAULT_TEST_UTID);
        XCTAssertNil(installBrokerResponse);
        XCTAssertNil(error);

        [expectation fulfill];

    }];

    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testInteractiveRequestFlow_whenAccountMismatch_andShouldValidateResultAccountYES_shouldReturnNilResultWithError
{
    __block NSUUID *correlationId = [NSUUID new];

    MSIDInteractiveTokenRequestParameters *parameters = [MSIDInteractiveTokenRequestParameters new];
    parameters.target = @"fakescope1 fakescope2";
    parameters.authority = [@"https://login.microsoftonline.com/common" aadAuthority];
    parameters.redirectUri = @"x-msauth-test://com.microsoft.testapp";
    parameters.clientId = @"my_client_id";
    parameters.extraAuthorizeURLQueryParameters = @{ @"eqp1" : @"val1", @"eqp2" : @"val2" };
    parameters.loginHint = @"fakeuser@contoso.com";
    parameters.correlationId = correlationId;
    parameters.webviewType = MSIDWebviewTypeWKWebView;
    parameters.extraScopesToConsent = @"fakescope3";
    parameters.oidcScope = @"openid profile offline_access";
    parameters.promptType = MSIDPromptTypeConsent;
    parameters.authority.openIdConfigurationEndpoint = [NSURL URLWithString:@"https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration"];
    parameters.accountIdentifier = [[MSIDAccountIdentifier alloc] initWithDisplayableId:@"user@contoso.com" homeAccountId:@"1.1234-5678-90abcdefg"];
    parameters.enablePkce = YES;
    parameters.shouldValidateResultAccount = YES;

    MSIDInteractiveTokenRequest *request = [[MSIDInteractiveTokenRequest alloc] initWithRequestParameters:parameters oauthFactory:[MSIDAADV2Oauth2Factory new] tokenResponseValidator:[MSIDDefaultTokenResponseValidator new] tokenCache:self.tokenCache accountMetadataCache:self.metadataCache extendedTokenCache:nil];

    XCTAssertNotNil(request);

    // Swizzle out the main entry point for WebUI, WebUI is tested in its own component tests
    [MSIDTestSwizzle classMethod:@selector(startSessionWithWebView:oauth2Factory:configuration:context:completionHandler:)
                           class:[MSIDWebviewAuthorization class]
                           block:(id)^(
                               __unused id obj,
                               __unused NSObject<MSIDWebviewInteracting> *webview,
                               __unused MSIDOauth2Factory *oauth2Factory,
                               __unused MSIDBaseWebRequestConfiguration *configuration,
                               __unused id<MSIDRequestContext> context,
                               MSIDWebviewAuthCompletionHandler completionHandler)
    {
         NSString *responseString = [NSString stringWithFormat:@"x-msauth-test://com.microsoft.testapp?code=iamafakecode&client_info=%@", [@{ @"uid" : @"1", @"utid" : @"1234-5678-90abcdefg"} msidBase64UrlJson]];

         MSIDWebAADAuthCodeResponse *oauthResponse = [[MSIDWebAADAuthCodeResponse alloc] initWithURL:[NSURL URLWithString:responseString]
                                                                                             context:nil error:nil];
         completionHandler(oauthResponse, nil);
     }];

    NSMutableDictionary *reqHeaders = [[MSIDTestURLResponse msidDefaultRequestHeaders] mutableCopy];
    [reqHeaders setObject:@"application/x-www-form-urlencoded" forKey:@"Content-Type"];

    NSString *url = @"https://login.microsoftonline.com/common/oauth2/v2.0/token";

    MSIDTestURLResponse *response =
    [MSIDTestURLResponse requestURLString:url
                           requestHeaders:reqHeaders
                        requestParamsBody:@{ @"code" : @"iamafakecode",
                                             @"client_id" : @"my_client_id",
                                             @"scope" : @"fakescope1 fakescope2 openid profile offline_access",
                                             @"redirect_uri" : @"x-msauth-test://com.microsoft.testapp",
                                             @"grant_type" : @"authorization_code",
                                             @"code_verifier" : [MSIDTestRequireValueSentinel sentinel],
                                             @"client_info" : @"1"}
                        responseURLString:@"https://login.microsoftonline.com/common/oauth2/v2.0/token"
                             responseCode:200
                         httpHeaderFields:nil
                         dictionaryAsJSON:@{ @"access_token" : @"i am a access token!",
                                             @"expires_in" : @"600",
                                             @"refresh_token" : @"i am a refresh token",
                                             @"id_token" : [MSIDTestIdTokenUtil defaultV2IdToken],
                                             @"id_token_expires_in" : @"1200",
                                             @"client_info" : [@{ @"uid" : @"2", @"utid" : @"1234-5678-90abcdefg"} msidBase64UrlJson],
                                             @"scope": @"fakescope1 fakescope2 openid profile offline_access"
                                             }];

    [response->_requestHeaders removeObjectForKey:@"Content-Length"];

    [MSIDTestURLSession addResponse:response];

    NSString *authority = @"https://login.microsoftonline.com/common";

    MSIDTestURLResponse *discoveryResponse = [MSIDTestURLResponse discoveryResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:discoveryResponse];

    MSIDTestURLResponse *oidcResponse = [MSIDTestURLResponse oidcResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:oidcResponse];
    
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Run request."];

    [request executeRequestWithCompletion:^(MSIDTokenResult * _Nullable result, NSError * _Nullable error, MSIDWebWPJResponse * _Nullable installBrokerResponse) {

        XCTAssertNil(result);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, MSIDErrorMismatchedAccount);
        XCTAssertNil(installBrokerResponse);

        [expectation fulfill];

    }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testInteractiveRequestFlow_whenProtectionPolicyRequired_shouldReturnNilResultWithError
{
    __block NSUUID *correlationId = [NSUUID new];

    MSIDInteractiveTokenRequestParameters *parameters = [MSIDInteractiveTokenRequestParameters new];
    parameters.target = @"fakescope1 fakescope2";
    parameters.authority = [@"https://login.microsoftonline.com/common" aadAuthority];
    parameters.redirectUri = @"x-msauth-test://com.microsoft.testapp";
    parameters.clientId = @"my_client_id";
    parameters.extraAuthorizeURLQueryParameters = @{ @"eqp1" : @"val1", @"eqp2" : @"val2" };
    parameters.loginHint = @"fakeuser@contoso.com";
    parameters.correlationId = correlationId;
    parameters.webviewType = MSIDWebviewTypeWKWebView;
    parameters.extraScopesToConsent = @"fakescope3";
    parameters.oidcScope = @"openid profile offline_access";
    parameters.promptType = MSIDPromptTypeConsent;
    parameters.authority.openIdConfigurationEndpoint = [NSURL URLWithString:@"https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration"];
    parameters.accountIdentifier = [[MSIDAccountIdentifier alloc] initWithDisplayableId:@"user@contoso.com" homeAccountId:@"1.1234-5678-90abcdefg"];
    parameters.enablePkce = YES;

    MSIDInteractiveTokenRequest *request = [[MSIDInteractiveTokenRequest alloc] initWithRequestParameters:parameters oauthFactory:[MSIDAADV2Oauth2Factory new] tokenResponseValidator:[MSIDDefaultTokenResponseValidator new] tokenCache:self.tokenCache accountMetadataCache:self.metadataCache extendedTokenCache:nil];

    XCTAssertNotNil(request);

    // Swizzle out the main entry point for WebUI, WebUI is tested in its own component tests
    [MSIDTestSwizzle classMethod:@selector(startSessionWithWebView:oauth2Factory:configuration:context:completionHandler:)
                           class:[MSIDWebviewAuthorization class]
                           block:(id)^(
                               __unused id obj,
                               __unused NSObject<MSIDWebviewInteracting> *webview,
                               __unused MSIDOauth2Factory *oauth2Factory,
                               __unused MSIDBaseWebRequestConfiguration *configuration,
                               __unused id<MSIDRequestContext> context,
                               MSIDWebviewAuthCompletionHandler completionHandler)
    {
         NSString *responseString = [NSString stringWithFormat:@"x-msauth-test://com.microsoft.testapp?code=iamafakecode&client_info=%@", [@{ @"uid" : @"1", @"utid" : @"1234-5678-90abcdefg"} msidBase64UrlJson]];

         MSIDWebAADAuthCodeResponse *oauthResponse = [[MSIDWebAADAuthCodeResponse alloc] initWithURL:[NSURL URLWithString:responseString]
                                                                                             context:nil error:nil];
         completionHandler(oauthResponse, nil);
     }];

    NSMutableDictionary *reqHeaders = [[MSIDTestURLResponse msidDefaultRequestHeaders] mutableCopy];
    [reqHeaders setObject:@"application/x-www-form-urlencoded" forKey:@"Content-Type"];

    NSString *url = @"https://login.microsoftonline.com/common/oauth2/v2.0/token";

    MSIDTestURLResponse *response =
    [MSIDTestURLResponse requestURLString:url
                           requestHeaders:reqHeaders
                        requestParamsBody:@{ @"code" : @"iamafakecode",
                                             @"client_id" : @"my_client_id",
                                             @"scope" : @"fakescope1 fakescope2 openid profile offline_access",
                                             @"redirect_uri" : @"x-msauth-test://com.microsoft.testapp",
                                             @"grant_type" : @"authorization_code",
                                             @"code_verifier" : [MSIDTestRequireValueSentinel sentinel],
                                             @"client_info" : @"1"}
                        responseURLString:@"https://login.microsoftonline.com/common/oauth2/v2.0/token"
                             responseCode:200
                         httpHeaderFields:nil
                         dictionaryAsJSON:@{ @"error" : @"unauthorized_client",
                                             @"error_description" : @"Unauthorized client",
                                             @"suberror" : @"protection_policy_required",
                                             @"adi" : @"fakeuser@contoso.com"
                                             }];

    [response->_requestHeaders removeObjectForKey:@"Content-Length"];

    [MSIDTestURLSession addResponse:response];

    NSString *authority = @"https://login.microsoftonline.com/common";

    MSIDTestURLResponse *discoveryResponse = [MSIDTestURLResponse discoveryResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:discoveryResponse];

    MSIDTestURLResponse *oidcResponse = [MSIDTestURLResponse oidcResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:oidcResponse];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Run request."];

    [request executeRequestWithCompletion:^(MSIDTokenResult * _Nullable result, NSError * _Nullable error, MSIDWebWPJResponse * _Nullable installBrokerResponse) {

        XCTAssertNil(result);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, MSIDErrorServerProtectionPoliciesRequired);
        XCTAssertEqual(error.domain, MSIDOAuthErrorDomain);
        XCTAssertEqualObjects(error.userInfo[MSIDOAuthSubErrorKey], MSID_PROTECTION_POLICY_REQUIRED);
        XCTAssertEqualObjects(error.userInfo[MSIDUserDisplayableIdkey], @"fakeuser@contoso.com");
        XCTAssertEqualObjects(error.userInfo[MSIDHomeAccountIdkey], @"1.1234-5678-90abcdefg");
        XCTAssertNil(installBrokerResponse);

        [expectation fulfill];

    }];

    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testInteractiveRequestFlow_whenErrorInCodeRedemption_shouldReturnNilResultWithError
{
    __block NSUUID *correlationId = [NSUUID new];

    MSIDInteractiveTokenRequestParameters *parameters = [MSIDInteractiveTokenRequestParameters new];
    parameters.target = @"fakescope1 fakescope2";
    parameters.authority = [@"https://login.microsoftonline.com/common" aadAuthority];
    parameters.redirectUri = @"x-msauth-test://com.microsoft.testapp";
    parameters.clientId = @"my_client_id";
    parameters.extraAuthorizeURLQueryParameters = @{ @"eqp1" : @"val1", @"eqp2" : @"val2" };
    parameters.loginHint = @"fakeuser@contoso.com";
    parameters.correlationId = correlationId;
    parameters.webviewType = MSIDWebviewTypeWKWebView;
    parameters.extraScopesToConsent = @"fakescope3";
    parameters.oidcScope = @"openid profile offline_access";
    parameters.promptType = MSIDPromptTypeConsent;
    parameters.authority.openIdConfigurationEndpoint = [NSURL URLWithString:@"https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration"];
    parameters.accountIdentifier = [[MSIDAccountIdentifier alloc] initWithDisplayableId:@"user@contoso.com" homeAccountId:@"1.1234-5678-90abcdefg"];
    parameters.enablePkce = YES;

    MSIDInteractiveTokenRequest *request = [[MSIDInteractiveTokenRequest alloc] initWithRequestParameters:parameters oauthFactory:[MSIDAADV2Oauth2Factory new] tokenResponseValidator:[MSIDDefaultTokenResponseValidator new] tokenCache:self.tokenCache accountMetadataCache:self.metadataCache extendedTokenCache:nil];

    XCTAssertNotNil(request);

    // Swizzle out the main entry point for WebUI, WebUI is tested in its own component tests
    [MSIDTestSwizzle classMethod:@selector(startSessionWithWebView:oauth2Factory:configuration:context:completionHandler:)
                           class:[MSIDWebviewAuthorization class]
                           block:(id)^(
                               __unused id obj,
                               __unused NSObject<MSIDWebviewInteracting> *webview,
                               __unused MSIDOauth2Factory *oauth2Factory,
                               __unused MSIDBaseWebRequestConfiguration *configuration,
                               __unused id<MSIDRequestContext> context,
                               MSIDWebviewAuthCompletionHandler completionHandler)
    {
         NSString *responseString = [NSString stringWithFormat:@"x-msauth-test://com.microsoft.testapp?code=iamafakecode&client_info=%@", [@{ @"uid" : @"1", @"utid" : @"1234-5678-90abcdefg"} msidBase64UrlJson]];

         MSIDWebAADAuthCodeResponse *oauthResponse = [[MSIDWebAADAuthCodeResponse alloc] initWithURL:[NSURL URLWithString:responseString]
                                                                                             context:nil error:nil];
         completionHandler(oauthResponse, nil);
     }];

    NSMutableDictionary *reqHeaders = [[MSIDTestURLResponse msidDefaultRequestHeaders] mutableCopy];
    [reqHeaders setObject:@"application/x-www-form-urlencoded" forKey:@"Content-Type"];

    NSString *url = @"https://login.microsoftonline.com/common/oauth2/v2.0/token";

    MSIDTestURLResponse *response =
    [MSIDTestURLResponse requestURLString:url
                           requestHeaders:reqHeaders
                        requestParamsBody:@{ @"code" : @"iamafakecode",
                                             @"client_id" : @"my_client_id",
                                             @"scope" : @"fakescope1 fakescope2 openid profile offline_access",
                                             @"redirect_uri" : @"x-msauth-test://com.microsoft.testapp",
                                             @"grant_type" : @"authorization_code",
                                             @"code_verifier" : [MSIDTestRequireValueSentinel sentinel],
                                             @"client_info" : @"1"}
                        responseURLString:@"https://login.microsoftonline.com/common/oauth2/v2.0/token"
                             responseCode:200
                         httpHeaderFields:nil
                         dictionaryAsJSON:@{ @"error" : @"invalid_request",
                                             @"error_description" : @"Error occured",
                                             @"suberror" : @"consent_required"
                                             }];

    [response->_requestHeaders removeObjectForKey:@"Content-Length"];

    [MSIDTestURLSession addResponse:response];

    NSString *authority = @"https://login.microsoftonline.com/common";
    MSIDTestURLResponse *discoveryResponse = [MSIDTestURLResponse discoveryResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:discoveryResponse];

    MSIDTestURLResponse *oidcResponse = [MSIDTestURLResponse oidcResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:oidcResponse];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Run request."];

    [request executeRequestWithCompletion:^(MSIDTokenResult * _Nullable result, NSError * _Nullable error, MSIDWebWPJResponse * _Nullable installBrokerResponse) {

        XCTAssertNil(result);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, MSIDErrorServerInvalidRequest);
        XCTAssertEqualObjects(error.userInfo[MSIDOAuthSubErrorKey], @"consent_required");
        XCTAssertEqualObjects(error.userInfo[MSIDOAuthErrorKey], @"invalid_request");
        XCTAssertEqualObjects(error.userInfo[MSIDErrorDescriptionKey], @"Error occured");
        XCTAssertNil(installBrokerResponse);

        [expectation fulfill];

    }];

    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testInteractiveRequestFlow_whenAuthCodeNotReceived_shouldReturnNilResultWithError
{
    __block NSUUID *correlationId = [NSUUID new];

    MSIDInteractiveTokenRequestParameters *parameters = [MSIDInteractiveTokenRequestParameters new];
    parameters.target = @"fakescope1 fakescope2";
    parameters.authority = [@"https://login.microsoftonline.com/common" aadAuthority];
    parameters.redirectUri = @"x-msauth-test://com.microsoft.testapp";
    parameters.clientId = @"my_client_id";
    parameters.extraAuthorizeURLQueryParameters = @{ @"eqp1" : @"val1", @"eqp2" : @"val2" };
    parameters.loginHint = @"fakeuser@contoso.com";
    parameters.correlationId = correlationId;
    parameters.webviewType = MSIDWebviewTypeWKWebView;
    parameters.extraScopesToConsent = @"fakescope3";
    parameters.oidcScope = @"openid profile offline_access";
    parameters.promptType = MSIDPromptTypeConsent;
    parameters.authority.openIdConfigurationEndpoint = [NSURL URLWithString:@"https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration"];
    parameters.accountIdentifier = [[MSIDAccountIdentifier alloc] initWithDisplayableId:@"user@contoso.com" homeAccountId:@"1.1234-5678-90abcdefg"];
    parameters.enablePkce = YES;

    MSIDInteractiveTokenRequest *request = [[MSIDInteractiveTokenRequest alloc] initWithRequestParameters:parameters oauthFactory:[MSIDAADV2Oauth2Factory new] tokenResponseValidator:[MSIDDefaultTokenResponseValidator new] tokenCache:self.tokenCache accountMetadataCache:self.metadataCache extendedTokenCache:nil];

    XCTAssertNotNil(request);

    // Swizzle out the main entry point for WebUI, WebUI is tested in its own component tests
    [MSIDTestSwizzle classMethod:@selector(startSessionWithWebView:oauth2Factory:configuration:context:completionHandler:)
                           class:[MSIDWebviewAuthorization class]
                           block:(id)^(
                               __unused id obj,
                               __unused NSObject<MSIDWebviewInteracting> *webview,
                               __unused MSIDOauth2Factory *oauth2Factory,
                               __unused MSIDBaseWebRequestConfiguration *configuration,
                               __unused id<MSIDRequestContext> context,
                               MSIDWebviewAuthCompletionHandler completionHandler)
    {
         NSString *responseString = @"x-msauth-test://com.microsoft.testapp?error=access_denied&error_description=MyError";

         MSIDWebAADAuthCodeResponse *oauthResponse = [[MSIDWebAADAuthCodeResponse alloc] initWithURL:[NSURL URLWithString:responseString]
                                                                                             context:nil error:nil];
         completionHandler(oauthResponse, nil);
     }];

    NSString *authority = @"https://login.microsoftonline.com/common";

    MSIDTestURLResponse *discoveryResponse = [MSIDTestURLResponse discoveryResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:discoveryResponse];

    MSIDTestURLResponse *oidcResponse = [MSIDTestURLResponse oidcResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:oidcResponse];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Run request."];

    [request executeRequestWithCompletion:^(MSIDTokenResult * _Nullable result, NSError * _Nullable error, MSIDWebWPJResponse * _Nullable installBrokerResponse) {

        XCTAssertNil(result);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, MSIDErrorServerAccessDenied);
        XCTAssertEqualObjects(error.domain, MSIDOAuthErrorDomain);
        XCTAssertEqualObjects(error.userInfo[MSIDOAuthErrorKey], @"access_denied");
        XCTAssertEqualObjects(error.userInfo[MSIDErrorDescriptionKey], @"MyError");
        XCTAssertNil(installBrokerResponse);

        [expectation fulfill];

    }];

    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testInteractiveRequestFlow_whenBrokerInstallResponse_shouldReturnNilResultWithNilErrorAndBrokerResponse
{
    __block NSUUID *correlationId = [NSUUID new];

    MSIDInteractiveTokenRequestParameters *parameters = [MSIDInteractiveTokenRequestParameters new];
    parameters.target = @"fakescope1 fakescope2";
    parameters.authority = [@"https://login.microsoftonline.com/common" aadAuthority];
    parameters.redirectUri = @"x-msauth-test://com.microsoft.testapp";
    parameters.clientId = @"my_client_id";
    parameters.extraAuthorizeURLQueryParameters = @{ @"eqp1" : @"val1", @"eqp2" : @"val2" };
    parameters.loginHint = @"fakeuser@contoso.com";
    parameters.correlationId = correlationId;
    parameters.webviewType = MSIDWebviewTypeWKWebView;
    parameters.extraScopesToConsent = @"fakescope3";
    parameters.oidcScope = @"openid profile offline_access";
    parameters.promptType = MSIDPromptTypeConsent;
    parameters.authority.openIdConfigurationEndpoint = [NSURL URLWithString:@"https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration"];
    parameters.accountIdentifier = [[MSIDAccountIdentifier alloc] initWithDisplayableId:@"user@contoso.com" homeAccountId:@"1.1234-5678-90abcdefg"];
    parameters.enablePkce = YES;

    MSIDInteractiveTokenRequest *request = [[MSIDInteractiveTokenRequest alloc] initWithRequestParameters:parameters oauthFactory:[MSIDAADV2Oauth2Factory new] tokenResponseValidator:[MSIDDefaultTokenResponseValidator new] tokenCache:self.tokenCache accountMetadataCache:self.metadataCache extendedTokenCache:nil];

    XCTAssertNotNil(request);

    // Swizzle out the main entry point for WebUI, WebUI is tested in its own component tests
    [MSIDTestSwizzle classMethod:@selector(startSessionWithWebView:oauth2Factory:configuration:context:completionHandler:)
                           class:[MSIDWebviewAuthorization class]
                           block:(id)^(
                               __unused id obj,
                               __unused NSObject<MSIDWebviewInteracting> *webview,
                               __unused MSIDOauth2Factory *oauth2Factory,
                               __unused MSIDBaseWebRequestConfiguration *configuration,
                               __unused id<MSIDRequestContext> context,
                               MSIDWebviewAuthCompletionHandler completionHandler)
    {

         NSString *responseString = @"msauth://wpj?app_link=https://login.microsoftonline.appinstall.test";

         MSIDWebWPJResponse *msauthResponse = [[MSIDWebWPJResponse alloc] initWithURL:[NSURL URLWithString:responseString] context:nil error:nil];
         completionHandler(msauthResponse, nil);
     }];

    NSString *authority = @"https://login.microsoftonline.com/common";
    MSIDTestURLResponse *discoveryResponse = [MSIDTestURLResponse discoveryResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:discoveryResponse];

    MSIDTestURLResponse *oidcResponse = [MSIDTestURLResponse oidcResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:oidcResponse];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Run request."];

    [request executeRequestWithCompletion:^(MSIDTokenResult * _Nullable result, NSError * _Nullable error, MSIDWebWPJResponse * _Nullable installBrokerResponse) {

        XCTAssertNil(result);
        XCTAssertNil(error);
        XCTAssertNotNil(installBrokerResponse);
        XCTAssertEqualObjects(installBrokerResponse.appInstallLink, @"https://login.microsoftonline.appinstall.test");

        [expectation fulfill];

    }];

    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testInteractiveRequestFlow_whenNestedAuth_shouldReturnResultWithBrokerParametersAndNoError
{
    __block NSUUID *correlationId = [NSUUID new];

    MSIDInteractiveTokenRequestParameters *parameters = [MSIDInteractiveTokenRequestParameters new];
    parameters.target = @"fakescope1 fakescope2";
    parameters.authority = [@"https://login.microsoftonline.com/common" aadAuthority];
    parameters.redirectUri = @"x-msauth-test://com.microsoft.testapp";
    parameters.clientId = @"my_client_id";
    parameters.extraAuthorizeURLQueryParameters = @{ @"eqp1" : @"val1", @"eqp2" : @"val2" };
    parameters.loginHint = @"fakeuser@contoso.com";
    parameters.correlationId = correlationId;
    parameters.webviewType = MSIDWebviewTypeWKWebView;
    parameters.extraScopesToConsent = @"fakescope3";
    parameters.oidcScope = @"openid profile offline_access";
    parameters.promptType = MSIDPromptTypeConsent;
    parameters.authority.openIdConfigurationEndpoint = [NSURL URLWithString:@"https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration"];
    parameters.accountIdentifier = [[MSIDAccountIdentifier alloc] initWithDisplayableId:@"user@contoso.com" homeAccountId:DEFAULT_TEST_HOME_ACCOUNT_ID];
    parameters.enablePkce = YES;
    parameters.nestedAuthBrokerClientId = @"123-456-7890-123";
    parameters.nestedAuthBrokerRedirectUri = @"msauth.com.app.id://auth";

    MSIDInteractiveTokenRequest *request = [[MSIDInteractiveTokenRequest alloc] initWithRequestParameters:parameters
                                                                                             oauthFactory:[MSIDAADV2Oauth2Factory new] tokenResponseValidator:[MSIDDefaultTokenResponseValidator new]
                                                                                               tokenCache:self.tokenCache accountMetadataCache:self.metadataCache extendedTokenCache:nil];

    XCTAssertNotNil(request);

    // Swizzle out the main entry point for WebUI, WebUI is tested in its own component tests
    [MSIDTestSwizzle classMethod:@selector(startSessionWithWebView:oauth2Factory:configuration:context:completionHandler:)
                           class:[MSIDWebviewAuthorization class]
                           block:(id)^(
                                   __unused id obj,
                                   __unused NSObject<MSIDWebviewInteracting> *webview,
                                   __unused MSIDOauth2Factory *oauth2Factory,
                                   __unused MSIDBaseWebRequestConfiguration *configuration,
                                   __unused id<MSIDRequestContext> context,
                                   MSIDWebviewAuthCompletionHandler completionHandler)
                           {
                               NSString *responseString = [NSString stringWithFormat:@"x-msauth-test://com.microsoft.testapp?code=iamafakecode&client_info=%@", [@{ @"uid" : @"1", @"utid" : @"1234-5678-90abcdefg"} msidBase64UrlJson]];

                               MSIDWebAADAuthCodeResponse *oauthResponse = [[MSIDWebAADAuthCodeResponse alloc] initWithURL:[NSURL URLWithString:responseString]
                                                                                                                   context:nil error:nil];
                               completionHandler(oauthResponse, nil);
                           }];

    NSMutableDictionary *reqHeaders = [[MSIDTestURLResponse msidDefaultRequestHeaders] mutableCopy];
    reqHeaders[@"Content-Type"] = @"application/x-www-form-urlencoded";

    NSString *url = @"https://login.microsoftonline.com/common/oauth2/v2.0/token";

    MSIDTestURLResponse *response =
            [MSIDTestURLResponse requestURLString:url
                                   requestHeaders:reqHeaders
                                requestParamsBody:@{ @"code" : @"iamafakecode",
                                        @"client_id" : @"my_client_id",
                                        @"scope" : @"fakescope1 fakescope2 openid profile offline_access",
                                        @"redirect_uri" : @"x-msauth-test://com.microsoft.testapp",
                                        @"grant_type" : @"authorization_code",
                                        @"code_verifier" : [MSIDTestRequireValueSentinel sentinel],
                                        @"client_info" : @"1",
                                        @"brk_client_id" : @"123-456-7890-123",
                                        @"brk_redirect_uri" : @"msauth.com.app.id://auth"}
                                responseURLString:@"https://login.microsoftonline.com/common/oauth2/v2.0/token"
                                     responseCode:200
                                 httpHeaderFields:nil
                                 dictionaryAsJSON:@{ @"access_token" : @"i am a access token!",
                                         @"expires_in" : @"600",
                                         @"refresh_token" : @"i am a refresh token",
                                         @"id_token" : [MSIDTestIdTokenUtil defaultV2IdToken],
                                         @"id_token_expires_in" : @"1200",
                                         @"client_info" : [@{ @"uid" : @"1", @"utid" : @"1234-5678-90abcdefg"} msidBase64UrlJson],
                                         @"scope": @"fakescope1 fakescope2 openid profile offline_access"
                                 }];

    [response->_requestHeaders removeObjectForKey:@"Content-Length"];

    [MSIDTestURLSession addResponse:response];

    NSString *authority = @"https://login.microsoftonline.com/common";
    MSIDTestURLResponse *discoveryResponse = [MSIDTestURLResponse discoveryResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:discoveryResponse];

    MSIDTestURLResponse *oidcResponse = [MSIDTestURLResponse oidcResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:oidcResponse];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Run request."];

    [request executeRequestWithCompletion:^(MSIDTokenResult * _Nullable result, NSError * _Nullable error, MSIDWebWPJResponse * _Nullable installBrokerResponse) {

        XCTAssertNotNil(result);
        XCTAssertNil(error);
        XCTAssertNotNil(result.account);
        XCTAssertEqualObjects(result.account.accountIdentifier.homeAccountId, @"1.1234-5678-90abcdefg");
        XCTAssertEqualObjects(result.account.name, [MSIDTestIdTokenUtil defaultName]);
        XCTAssertEqualObjects(result.account.username, [MSIDTestIdTokenUtil defaultUsername]);
        XCTAssertEqualObjects(result.accessToken.accessToken, @"i am a access token!");
        XCTAssertEqualObjects(result.rawIdToken, [MSIDTestIdTokenUtil defaultV2IdToken]);
        XCTAssertEqualObjects(((MSIDRefreshToken*)result.refreshToken).clientId, parameters.nestedAuthBrokerClientId, @"Make sure RT's clientId is from nested client id");
        XCTAssertFalse(result.extendedLifeTimeToken);
        XCTAssertEqualObjects(result.authority.url.absoluteString, DEFAULT_TEST_AUTHORITY_GUID);
        XCTAssertNil(installBrokerResponse);
        XCTAssertNil(error);

        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1 handler:nil];
}

#if TARGET_OS_IPHONE
- (void)testInteractiveRequestFlow_whenOpenBrowserResponse_shouldOpenLink
{
    __block NSUUID *correlationId = [NSUUID new];

    MSIDInteractiveTokenRequestParameters *parameters = [MSIDInteractiveTokenRequestParameters new];
    parameters.target = @"fakescope1 fakescope2";
    parameters.authority = [@"https://login.microsoftonline.com/common" aadAuthority];
    parameters.redirectUri = @"x-msauth-test://com.microsoft.testapp";
    parameters.clientId = @"my_client_id";
    parameters.extraAuthorizeURLQueryParameters = @{ @"eqp1" : @"val1", @"eqp2" : @"val2" };
    parameters.loginHint = @"fakeuser@contoso.com";
    parameters.correlationId = correlationId;
    parameters.webviewType = MSIDWebviewTypeWKWebView;
    parameters.extraScopesToConsent = @"fakescope3";
    parameters.oidcScope = @"openid profile offline_access";
    parameters.promptType = MSIDPromptTypeConsent;
    parameters.authority.openIdConfigurationEndpoint = [NSURL URLWithString:@"https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration"];
    parameters.accountIdentifier = [[MSIDAccountIdentifier alloc] initWithDisplayableId:@"user@contoso.com" homeAccountId:@"1.1234-5678-90abcdefg"];
    parameters.enablePkce = YES;

    MSIDInteractiveTokenRequest *request = [[MSIDInteractiveTokenRequest alloc] initWithRequestParameters:parameters oauthFactory:[MSIDAADV2Oauth2Factory new] tokenResponseValidator:[MSIDDefaultTokenResponseValidator new] tokenCache:self.tokenCache accountMetadataCache:self.metadataCache extendedTokenCache:nil];

    XCTAssertNotNil(request);

    // Swizzle out the main entry point for WebUI, WebUI is tested in its own component tests
    [MSIDTestSwizzle classMethod:@selector(startSessionWithWebView:oauth2Factory:configuration:context:completionHandler:)
                           class:[MSIDWebviewAuthorization class]
                           block:(id)^(
                               __unused id obj,
                               __unused NSObject<MSIDWebviewInteracting> *webview,
                               __unused MSIDOauth2Factory *oauth2Factory,
                               __unused MSIDBaseWebRequestConfiguration *configuration,
                               __unused id<MSIDRequestContext> context,
                               MSIDWebviewAuthCompletionHandler completionHandler)
    {

         NSString *responseString = @"browser://login.microsoftonline.appinstall.test";

         MSIDWebOpenBrowserResponse *msauthResponse = [[MSIDWebOpenBrowserResponse alloc] initWithURL:[NSURL URLWithString:responseString] context:nil error:nil];
         completionHandler(msauthResponse, nil);
     }];

    NSString *authority = @"https://login.microsoftonline.com/common";
    MSIDTestURLResponse *discoveryResponse = [MSIDTestURLResponse discoveryResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:discoveryResponse];

    MSIDTestURLResponse *oidcResponse = [MSIDTestURLResponse oidcResponseForAuthority:authority];
    [MSIDTestURLSession addResponse:oidcResponse];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Run request."];

    [request executeRequestWithCompletion:^(MSIDTokenResult * _Nullable result, NSError * _Nullable error, MSIDWebWPJResponse * _Nullable installBrokerResponse) {

        XCTAssertNil(result);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, MSIDErrorSessionCanceledProgrammatically);
        XCTAssertNil(installBrokerResponse);

        [expectation fulfill];

    }];

    XCTestExpectation *openURLExpectation = [self expectationWithDescription:@"Open URL."];

    [MSIDApplicationTestUtil onOpenURL:^BOOL(NSURL *url, __unused NSDictionary<NSString *,id> *options) {
        XCTAssertEqualObjects(url.absoluteString, @"https://login.microsoftonline.appinstall.test");
        [openURLExpectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1 handler:nil];
}
#endif

@end
