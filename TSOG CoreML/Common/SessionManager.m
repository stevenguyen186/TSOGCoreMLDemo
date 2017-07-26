//
//  SessionManager.m
//  TSOG CoreML
//
//  Created by Van Nguyen on 7/26/17.
//  Copyright © 2017 TheSchoolOfGames. All rights reserved.
//

#import "SessionManager.h"

@implementation SessionManager

+ (SessionManager *)sharedInstance {
    static SessionManager *_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[SessionManager alloc] init];
        _instance.identifiedObjects = [NSMutableArray array];
    });
    
    return _instance;
}

@end
