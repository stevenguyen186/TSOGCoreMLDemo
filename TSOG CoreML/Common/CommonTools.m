//
//  CommonTools.m
//  TSOG CoreML
//
//  Created by Van Nguyen on 7/26/17.
//  Copyright © 2017 TheSchoolOfGames. All rights reserved.
//

#import "CommonTools.h"

@implementation CommonTools

+ (void)showAlertInViewController:(UIViewController *)viewController
                                withTitle:(NSString *)title
                                  message:(NSString *)message {
    UIAlertController *strongController = [UIAlertController alertControllerWithTitle:title
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    __weak UIAlertController *controller = strongController;
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"OK"
                                                           style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction *action){
                                                         }];
    [controller addAction:cancelAction];
    [viewController presentViewController:controller animated:YES completion:nil];
}

@end
