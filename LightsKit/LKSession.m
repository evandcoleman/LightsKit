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
#import "LKX10Device.h"
#import "LKAnimation.h"
#import "LKScheduledEvent.h"
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

- (void)suspendSession {
    [self.socketSession closeSession];
}

- (void)resumeSessionWithCompletion:(void (^)())completion {
    [self.socketSession resumeSessionWithCompletion:completion];
}

- (void)sendEvent:(LKEvent *)event {
    [self.socketSession sendEvent:event];
}

- (void)sendEventCollection:(LKEventCollection *)collection {
    [self.socketSession sendEventCollection:collection];
}

- (void)scheduleEvent:(LKScheduledEvent *)event withCompletion:(void (^)())completion {
    NSMutableDictionary *params = [[event dictionaryRepresentation] mutableCopy];
    params[@"auth_token"] = self.authToken;
    [self.sessionManager POST:@"api/v1/schedule" parameters:params success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        [self.socketSession notifyServerOfScheduleUpdateInZone:event.zone withCompletion:^{
            if (completion) {
                completion();
            }
        }];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"%@", [error localizedDescription]);
    }];
}

- (void)executePreset:(LKPreset *)preset {
    LKEvent *event = [LKEvent presetEventAtIndex:preset.index];
    [self sendEvent:event];
}

#pragma mark - Convenience methods

- (void)queryStateWithBlock:(void (^)(LKEvent *event))block {
    [self.socketSession queryStateWithCompletion:block];
}

- (void)queryX10DevicesWithBlock:(void (^)(NSArray *devices))block {
    [self.sessionManager GET:@"api/v1/users/devices" parameters:@{@"auth_token": self.authToken} success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        NSMutableArray *devices = [NSMutableArray array];
        for (NSDictionary *deviceDict in responseObject[@"devices"]) {
            [devices addObject:[LKX10Device deviceWithDictionary:deviceDict]];
        }
        block([devices copy]);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        
    }];
}

- (void)queryPresetsWithBlock:(void (^)(NSArray *))block {
    
}

- (void)queryScheduleWithBlock:(void (^)(NSArray *))block {
    
}

- (void)queryAnimationsWithBlock:(void (^)(NSArray *))block {
    [self.sessionManager GET:@"api/v1/colors/animations" parameters:@{@"auth_token": self.authToken} success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        NSMutableArray *devices = [NSMutableArray array];
        for (NSDictionary *dict in responseObject[@"animations"]) {
            [devices addObject:[LKAnimation animationWithDictionary:dict]];
        }
        block([devices copy]);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        
    }];
}

@end
