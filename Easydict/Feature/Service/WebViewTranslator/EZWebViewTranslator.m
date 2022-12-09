//
//  EZBaiduWebTranslate.m
//  Easydict
//
//  Created by tisfeng on 2022/12/4.
//  Copyright © 2022 izual. All rights reserved.
//

#import "EZWebViewTranslator.h"
#import <WebKit/WebKit.h>
#import "EZURLSchemeHandler.h"

// Max query duration seconds
static NSTimeInterval const MAX_QUERY_SECONDS = 10.0;

// Delay query seconds
static NSTimeInterval const DELAY_SECONDS = 0.1; // Usually takes more than 0.1 seconds.


@interface EZWebViewTranslator () <WKNavigationDelegate, WKUIDelegate>

@property (nonatomic, strong) WKWebView *webView;

@property (nonatomic, copy) NSString *queryURL;
@property (nonatomic, copy) void (^completion)(NSString *, NSError *);

@property (nonatomic, assign) NSUInteger retryCount;

@property (nonatomic, strong) EZURLSchemeHandler *urlSchemeHandler;

@end


@implementation EZWebViewTranslator

- (WKWebView *)webView {
    if (!_webView) {
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        WKPreferences *preferences = [[WKPreferences alloc] init];
        preferences.javaScriptCanOpenWindowsAutomatically = NO;
        configuration.preferences = preferences;
        
        self.urlSchemeHandler = [EZURLSchemeHandler sharedInstance];
        [configuration setURLSchemeHandler:self.urlSchemeHandler forURLScheme:@"https"];
        
        WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
        _webView = webView;
        webView.navigationDelegate = self;
        
        NSString *cookieString = @"APPGUIDE_10_0_2=1; REALTIME_TRANS_SWITCH=1; FANYI_WORD_SWITCH=1; HISTORY_SWITCH=1; SOUND_SPD_SWITCH=1; SOUND_PREFER_SWITCH=1; ZD_ENTRY=google; BAIDUID=483C3DD690DBC65C6F133A670013BF5D:FG=1; BAIDUID_BFESS=483C3DD690DBC65C6F133A670013BF5D:FG=1; newlogin=1; BDUSS=50ZnpUNG93akxsaGZZZ25tTFBZZEY4TzQ2ZG5ZM3FVaUVPS0J-M2JVSVpvNXBqSVFBQUFBJCQAAAAAAAAAAAEAAACFn5wyus3Jz7Xb1sD3u9fTMjkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABkWc2MZFnNjSX; BDUSS_BFESS=50ZnpUNG93akxsaGZZZ25tTFBZZEY4TzQ2ZG5ZM3FVaUVPS0J-M2JVSVpvNXBqSVFBQUFBJCQAAAAAAAAAAAEAAACFn5wyus3Jz7Xb1sD3u9fTMjkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABkWc2MZFnNjSX; Hm_lvt_64ecd82404c51e03dc91cb9e8c025574=1670083644; Hm_lvt_afd111fa62852d1f37001d1f980b6800=1670084751; Hm_lpvt_afd111fa62852d1f37001d1f980b6800=1670084751; Hm_lpvt_64ecd82404c51e03dc91cb9e8c025574=1670166705";
        
        NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:@{
            NSHTTPCookieName : @"Cookie",
            NSHTTPCookieValue : cookieString,
        }];
        
        WKHTTPCookieStore *cookieStore = webView.configuration.websiteDataStore.httpCookieStore;
        [cookieStore setCookie:cookie completionHandler:^{
            // cookie 设置完成
        }];
        
        // custom UserAgent.
        [webView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(id obj, NSError *error) {
            if (error) {
                return;
            }
            [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent" : EZUserAgent}];
        }];
        
        // Preload webView, in order to save the loading time later.
        [webView loadHTMLString:@"" baseURL:nil];
    }
    return _webView;
}

- (void)preloadURL:(NSString *)url {
    [self loadURL:url success:nil failure:nil];
}

#pragma mark - Query

/// Load URL in webView.
- (void)loadURL:(NSString *)URL
        success:(nullable void (^)(NSString *translatedText))success
        failure:(nullable void (^)(NSError *error))failure {
    
    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:URL]]];
    
    self.queryURL = URL;
    if (!self.queryURL.length || !self.querySelector.length) {
        NSLog(@"query url and selector cannot be nil");
        return;
    }
    
    NSLog(@"query url: %@", self.queryURL);
    
    self.retryCount = 0;
    
    mm_weakify(self);
    self.completion = ^(NSString *result, NSError *error) {
        mm_strongify(self);
        
        if (result) {
            if (success) {
                success(result);
            }
        } else {
            if (failure) {
                failure(error);
            }
        }
        
        // !!!: When finished, set completion to nil, and reset webView.
        self.completion = nil;
        [self.webView loadHTMLString:@"" baseURL:nil];
    };
}

- (void)getTextContentOfElement:(NSString *)selector
                     completion:(void (^)(NSString *_Nullable, NSError *))completion {
    NSLog(@"get result count: %ld", self.retryCount + 1);
    
    // 定义一个异步方法，用于判断页面中是否存在目标元素
    // 先判断页面中是否存在目标元素
    NSString *js = [NSString stringWithFormat:@"document.querySelector('%@') != null", selector];
    [self.webView evaluateJavaScript:js completionHandler:^(id _Nullable result, NSError *_Nullable error) {
        if (error) {
            // 如果执行出错，则直接返回
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        void (^retryBlock)(void) = ^{
            // 如果页面中不存在目标元素，则延迟一段时间后再次判断
            self.retryCount++;
            NSInteger maxRetryCount = ceil(MAX_QUERY_SECONDS / DELAY_SECONDS);
            if (self.retryCount < maxRetryCount && self.completion) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DELAY_SECONDS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self getTextContentOfElement:selector completion:completion];
                });
            } else {
                NSLog(@"finish, retry count: %ld", self.retryCount);
                if (completion) {
                    NSError *error = [NSError errorWithDomain:@"com.eztranslation" code:-1 userInfo:@{NSLocalizedDescriptionKey : @"retry count is too large"}];
                    completion(nil, error);
                }
            }
        };
        
        if ([result boolValue]) {
            // 如果页面中存在目标元素，则执行下面的代码获取它的 textContent 属性
            NSString *js = [NSString stringWithFormat:@"document.querySelector('%@').textContent", selector];
            [self.webView evaluateJavaScript:js completionHandler:^(id _Nullable result, NSError *_Nullable error) {
                if (error) {
                    // 如果执行出错，则直接返回
                    if (completion) {
                        completion(nil, error);
                    }
                }
                // trim text
                NSString *translatedText = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (completion && [translatedText length]) {
                    completion(translatedText, nil);
                } else {
                    retryBlock();
                }
            }];
        } else {
            retryBlock();
        }
    }];
}

- (void)monitorURL:(NSString *)url completionHandler:(void (^)(NSURLResponse * _Nonnull, id _Nullable, NSError * _Nullable))completionHandler {
    [self.urlSchemeHandler monitorURL:url completionHandler:completionHandler];
}

#pragma mark - WKNavigationDelegate

// 页面加载完成后，获取翻译结果
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"didFinishNavigation: %@", webView.URL.absoluteString);
    
    if (self.completion) {
        [self getTextContentOfElement:self.querySelector completion:self.completion];
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"didFailNavigation: %@", error);
}

/** 请求服务器发生错误 (如果是goBack时，当前页面也会回调这个方法，原因是NSURLErrorCancelled取消加载) */
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"didFailProvisionalNavigation: %@", error);
}

// 监听 JavaScript 代码是否执行
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    // JavaScript 代码执行
    NSLog(@"runJavaScriptAlertPanelWithMessage: %@", message);
}


/** 在收到响应后，决定是否跳转 */
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    NSLog(@"decidePolicyForNavigationResponse: %@", navigationResponse.response.URL.absoluteString);
    
    // 这里可以查看页面内部的网络请求，并做出相应的处理
    // navigationResponse 包含了请求的相关信息，你可以通过它来获取请求的 URL、请求方法、请求头等信息
    // decisionHandler 是一个回调，你可以通过它来决定是否允许这个请求发送
    
    
    //允许跳转
    decisionHandler(WKNavigationResponsePolicyAllow);
    //不允许跳转
    // decisionHandler(WKNavigationResponsePolicyCancel);
}

/** 接收到服务器跳转请求即服务重定向时之后调用 */
- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation {
    NSLog(@"didReceiveServerRedirectForProvisionalNavigation: %@", webView.URL.absoluteURL);
}

/** 收到服务器响应后，在发送请求之前，决定是否跳转 */
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSString *navigationActionURL = navigationAction.request.URL.absoluteString;
    NSLog(@"decidePolicyForNavigationAction URL: %@", navigationActionURL);
    
    //    if ([navigationActionURL isEqualToString:@"about:blank"]) {
    //        decisionHandler(WKNavigationActionPolicyCancel);
    //        return;
    //    }
    
    //允许跳转
    decisionHandler(WKNavigationActionPolicyAllow);
    //不允许跳转
    // decisionHandler(WKNavigationActionPolicyCancel);
}

@end
