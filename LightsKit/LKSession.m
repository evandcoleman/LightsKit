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
#import "LKRoom.h"
#import "LKBeacon.h"

static id _activeSession = nil;

@interface LKSession ()

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

- (instancetype)initWithBaseURL:(NSURL *)url {
    self = [super initWithBaseURL:url];
    if (self) {
        _activeSession = self;
    }
    return self;
}

#pragma mark - SocketRocket methods

- (void)openSessionWithUsername:(NSString *)username password:(NSString *)password completion:(void (^)(NSDictionary *userDict))completion {
    NSDictionary *params = @{@"username": username, @"password": password};
    [self POST:@"api/v1/sessions" parameters:params success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        self.authToken = responseObject[@"auth"][@"token"];
        NSString *str = [self.baseURL absoluteString];
        NSInteger colon = [str rangeOfString:@":"].location;
        if (colon != NSNotFound) {
            str = [str substringFromIndex:colon];
            str = [@"ws" stringByAppendingString:str];
        }
        self.socketSession = [[LKSocketSession alloc] initWithServer:[[NSURL URLWithString:str] URLByAppendingPathComponent:@"websocket"]];
        [self.socketSession openSessionWithCompletion:^{
            completion(responseObject);
        }];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        
    }];
}

- (void)suspendSession {
    [self.socketSession closeSession];
}

- (void)resumeSessionWithCompletion:(void (^)())completion {
    [self.socketSession resumeSessionWithCompletion:completion];
}

- (void)registerDeviceToken:(NSString *)deviceToken completion:(void (^)())completion {
    [self POST:@"api/v1/users/register_device_token"
                   parameters:@{@"auth_token": self.authToken, @"device_token": deviceToken}
                      success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
                          if (completion) {
                              completion();
                          }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"%@", [error localizedDescription]);
    }];
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
    [self POST:@"api/v1/schedule" parameters:params success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        [self.socketSession notifyServerOfScheduleUpdateInZone:event.zone withCompletion:^{
            if (completion) {
                completion();
            }
        }];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"%@", [error localizedDescription]);
    }];
}

- (void)updateEvent:(LKScheduledEvent *)event withCompletion:(void (^)())completion {
    NSMutableDictionary *params = [@{@"auth_token": self.authToken} mutableCopy];
    params[@"schedule"] = [event dictionaryRepresentation];
    NSString *urlString = [NSString stringWithFormat:@"api/v1/schedule/%li", event.scheduleId];
    [self POST:urlString parameters:params success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        [self.socketSession notifyServerOfScheduleUpdateInZone:event.zone withCompletion:^{
            if (completion) {
                completion();
            }
        }];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"%@", [error localizedDescription]);
    }];
}

- (void)addPreset:(LKPreset *)preset withCompletion:(void (^)())completion {
    NSMutableDictionary *params = [@{@"auth_token": self.authToken} mutableCopy];
    params[@"preset"] = [preset dictionaryRepresentation];
    [self POST:@"api/v1/presets" parameters:params success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        completion();
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"%@", [error localizedDescription]);
    }];
}

- (void)executePreset:(LKPreset *)preset {
    LKEventCollection *collection = [LKEventCollection collectionWithEvents:preset.actions];
    [self sendEventCollection:collection];
}

#pragma mark - Convenience methods

- (void)queryStateWithBlock:(void (^)(LKEvent *event))block {
    [self.socketSession queryStateWithCompletion:block];
}

- (void)queryX10DevicesWithBlock:(void (^)(NSArray *devices))block {
    [self GET:@"api/v1/users/devices" parameters:@{@"auth_token": self.authToken} success:^(NSURLSessionDataTask *task, NSArray *responseObject) {
        NSMutableArray *devices = [NSMutableArray array];
        for (NSDictionary *zoneDict in responseObject) {
            for (NSDictionary *deviceDict in zoneDict[@"x10_devices"]) {
                [devices addObject:[LKX10Device deviceWithDictionary:deviceDict]];
            }
        }
        block([devices copy]);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"%@", [error localizedDescription]);
    }];
}

- (void)queryPresetsWithBlock:(void (^)(NSArray *))block {
    [self GET:@"api/v1/presets" parameters:@{@"auth_token": self.authToken} success:^(NSURLSessionDataTask *task, NSArray *responseObject) {
        NSMutableArray *presets = [NSMutableArray array];
        int i = 0;
        for (NSDictionary *presetDict in responseObject) {
            LKPreset *preset = [LKPreset presetFromDictionary:presetDict atIndex:i];
            [presets addObject:preset];
            i++;
        }
        block([presets copy]);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"%@", [error localizedDescription]);
    }];
}

- (void)queryScheduleWithBlock:(void (^)(NSArray *))block {
    [self GET:@"api/v1/schedule" parameters:@{@"auth_token": self.authToken} success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        NSMutableArray *events = [NSMutableArray array];
        for (NSDictionary *eventDict in responseObject[@"events"]) {
            [events addObject:[LKScheduledEvent eventFromDictionary:eventDict]];
        }
        block([events copy]);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"%@", [error localizedDescription]);
    }];
}

- (void)queryAnimationsWithBlock:(void (^)(NSArray *))block {
    [self GET:@"api/v1/colors/animations" parameters:@{@"auth_token": self.authToken} success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        NSMutableArray *devices = [NSMutableArray array];
        for (NSDictionary *dict in responseObject[@"animations"]) {
            [devices addObject:[LKAnimation animationWithDictionary:dict]];
        }
        block([devices copy]);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"%@", [error localizedDescription]);
    }];
}

- (void)queryColorPermissionsWithBlock:(void (^)(NSArray *))block {
    [self GET:@"api/v1/users/color_zones" parameters:@{@"auth_token": self.authToken} success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
        block(responseObject[@"color_zones"]);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"%@", [error localizedDescription]);
    }];
}

- (void)queryRoomsWithBlock:(void (^)(NSArray *))block {
    [self GET:@"api/v1/rooms" parameters:@{@"auth_token": self.authToken} success:^(NSURLSessionDataTask *task, NSArray *responseObject) {
        NSMutableArray *rooms = [NSMutableArray array];
        for (NSDictionary *roomDict in responseObject) {
            [rooms addObject:[LKRoom roomWithDictionary:roomDict]];
        }
        block([rooms copy]);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"%@", [error localizedDescription]);
    }];
}

- (void)queryBeaconsWithBlock:(void (^)(NSArray *))block {
    [self GET:@"api/v1/beacons" parameters:@{@"auth_token": self.authToken} success:^(NSURLSessionDataTask *task, NSArray *responseObject) {
        NSMutableArray *beacons = [NSMutableArray array];
        for (NSDictionary *beaconDict in responseObject) {
            [beacons addObject:[LKBeacon beaconWithDictionary:beaconDict]];
        }
        block([beacons copy]);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"%@", [error localizedDescription]);
    }];
}

@end
