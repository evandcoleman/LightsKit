//
//  LKSession.m
//  LightsKit
//
//  Created by Evan Coleman on 11/29/13.
//  Copyright (c) 2013 Evan Coleman. All rights reserved.
//

#import "LKSession.h"
#import "LKEvent.h"
#import "LKColor.h"
#import "LKResponse.h"
#import "LKPreset.h"
#import "LKSocketSession.h"
#import "LKEventCollection.h"
#import <AFNetworking/AFNetworking.h>

static id _activeSession = nil;

@interface LKSession ()

@property (nonatomic) AFHTTPSessionManager *sessionManager;
@property (nonatomic) LKSocketSession *socketSession;
@property (nonatomic) NSString *authToken;

@property (nonatomic, copy) void (^didReceiveStateBlock)(LKResponse *response);
@property (nonatomic, copy) void (^didReceiveDevicesBlock)(LKResponse *response);
@property (nonatomic, copy) void (^didReceivePresetsBlock)(LKResponse *response);
@property (nonatomic, copy) void (^didReceiveScheduleBlock)(LKResponse *response);

@end

@implementation LKSession

#pragma mark - Class lifecycle

+ (instancetype)activeSession {
    return _activeSession;
}

- (instancetype)initWithServer:(NSURL *)url {
    self = [super init];
    if (self) {
        _sessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL:url];
        _activeSession = self;
    }
    return self;
}

#pragma mark - Getters

- (NSURL *)serverURL {
    return self.sessionManager.baseURL;
}

#pragma mark - SocketRocket methods

- (void)openSessionWithUsername:(NSString *)username password:(NSString *)password completion:(void (^)())completion {
    NSDictionary *params = @{@"username": username, @"password": password};
    [self.sessionManager POST:@"api/v1/sessions" parameters:params success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        self.authToken = responseObject[@"token"];
        NSString *str = [self.serverURL absoluteString];
        NSInteger colon = [str rangeOfString:@":"].location;
        if (colon != NSNotFound) {
            str = [str substringFromIndex:colon];
            str = [@"ws" stringByAppendingString:str];
        }
        self.socketSession = [[LKSocketSession alloc] initWithServer:[[NSURL URLWithString:str] URLByAppendingPathComponent:@"websocket"]];
        [self.socketSession openSessionWithCompletion:completion];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        
    }];
}

- (void)sendEvent:(LKEvent *)event {
    [self.socketSession sendEvent:event];
}

- (void)sendEventCollection:(LKEventCollection *)collection {
    [self.socketSession sendEventCollection:collection];
}

- (void)executePreset:(LKPreset *)preset {
    LKEvent *event = [LKEvent presetEventAtIndex:preset.index];
    [self sendEvent:event];
}

#pragma mark - Convenience methods

- (void)queryStateWithBlock:(void (^)(LKResponse *response))block {
    
}

- (void)queryX10DevicesWithBlock:(void (^)(LKResponse *response))block {
    [self.sessionManager GET:@"api/v1/users/devices" parameters:@{@"auth_token": self.authToken} success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        LKResponse *response = [LKResponse responseWithDevices:responseObject[LKDevicesKey]];
        block(response);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        
    }];
}

- (void)queryPresetsWithBlock:(void (^)(LKResponse *))block {
    
}

- (void)queryScheduleWithBlock:(void (^)(LKResponse *))block {
    
}

@end
