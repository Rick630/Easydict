//
//  EZLinkParser.m
//  Easydict
//
//  Created by tisfeng on 2023/2/25.
//  Copyright © 2023 izual. All rights reserved.
//

#import "EZLinkParser.h"
#import "EZOpenAIService.h"

// easydict://
static NSString *kEasydictSchema = @"easydict://";

@implementation EZLinkParser

#pragma mark - Write dict to NSUserDefaults

/// Open URL with text and completion bool.
- (BOOL)openURLWithText:(NSString *)text completion:(void (^)(BOOL success))completion {
    BOOL handled = [self isEasydictSchema:text];
    if (!handled) {
        completion(NO);
        return NO;
    }
    
    // Remove easydict://
    text = [text substringFromIndex:kEasydictSchema.length];
    
    handled = [self tryWriteKeyValue:text];
    completion(handled);
    return YES;
}


/// Check text, if text is "easydict://writeKeyValue?key=xxx&value=xxx"
/// easydict://writeKeyValue?EZOpenAIKey=sk-5DJ2bQxdT
/// easydict://writeKeyValue?EZBetaFeatureKey=1
- (BOOL)tryWriteKeyValue:(NSString *)text {
    NSString *prefix = @"writeKeyValue?";
    if ([text hasPrefix:prefix]) {
        NSString *keyValueText = [text substringFromIndex:prefix.length];
        return [self writeKeyValue:keyValueText];
    }
    return NO;
}


// Check if text started with easydict://
- (BOOL)isEasydictSchema:(NSString *)text {
    return [[text trim] hasPrefix:kEasydictSchema];
}

- (BOOL)writeKeyValue:(NSString *)text {
    NSDictionary *keyValue = [self getKeyValues:text];
    BOOL handled = NO;
    for (NSString *key in keyValue) {
        NSString *value = keyValue[key];
        if ([self.allowedWriteKeys containsObject:key]) {
            [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
            handled = YES;
        }
    }
    return handled;
}

/// Return key values dict from text.
/// TODO: allow multiple key-value pairs: key1=value1&key2=value2&key3=value3
- (NSDictionary *)getKeyValues:(NSString *)text {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSArray *keyValueArray = [text componentsSeparatedByString:@"&"];
    for (NSString *keyValue in keyValueArray) {
        NSArray *array = [keyValue componentsSeparatedByString:@"="];
        if (array.count == 2) {
            NSString *key = array[0];
            NSString *value = array[1];
            dict[key] = value;
        }
    }
    return dict;
}

/// Return allowed write keys to NSUserDefaults.
- (NSArray *)allowedWriteKeys {
    return @[
        EZOpenAIKey,
        EZBetaFeatureKey,
    ];
}

@end