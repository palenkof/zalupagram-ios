#import <ZalupaGramXray/ZalupaGramXray.h>

// Exported by zalupagram/xray/main.go.
extern char *ZGXrayStart(char *config);
extern void ZGXrayStop(void);
extern void ZGXrayFree(char *value);

@implementation ZGXrayRunner

+ (NSString * _Nullable)startWithConfig:(NSString *)config {
    char *error = ZGXrayStart((char *)config.UTF8String);
    if (error == NULL) {
        return nil;
    }
    NSString *result = [NSString stringWithUTF8String:error] ?: @"unknown error";
    ZGXrayFree(error);
    return result;
}

+ (void)stop {
    ZGXrayStop();
}

@end
