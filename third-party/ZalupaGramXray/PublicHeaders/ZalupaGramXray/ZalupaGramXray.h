#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ZalupaGram fork: Xray-core running inside the app.
@interface ZGXrayRunner : NSObject

// Starts Xray with a JSON config, stopping the running one first.
// Returns nil on success or the error text.
+ (NSString * _Nullable)startWithConfig:(NSString *)config;
+ (void)stop;

@end

NS_ASSUME_NONNULL_END
