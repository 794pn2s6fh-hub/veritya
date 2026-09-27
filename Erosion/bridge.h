//
//  bridge.h
//  Erosion
//

#ifndef bridge_h
#define bridge_h

#import "Exploits/bad_query.h"
#import <Foundation/Foundation.h>
#import "AirliftFFI/airlift.h"

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (bool)openApplicationWithBundleID:(NSString*)bundleID;
@end

#endif /* bridge_h */
