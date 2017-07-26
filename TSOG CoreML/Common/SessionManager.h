//
//  SessionManager.h
//  TSOG CoreML
//
//  Created by Van Nguyen on 7/26/17.
//  Copyright © 2017 TheSchoolOfGames. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SessionManager : NSObject

@property (nonatomic, strong) NSMutableArray *identifiedObjects;

+ (SessionManager *)sharedInstance;

@end
